import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// The ACT Leaderboard is entirely local — never server-backed.
/// Users are placed into a random group of ~100 simulated competitors.
/// The board updates every 5 minutes (via a timer in the UI layer),
/// so scores shift slightly on each refresh, making the board feel live.
///
/// The user's group is randomly assigned at first launch and persists,
/// meaning they will not necessarily see friends. A notice in the UI
/// explains this explicitly (per spec).
///
/// Top-3, top-5, top-10 positions trigger special badge popups when
/// the user reaches them.
class ActLeaderboardService {
  static const _stateKey = 'act_lb_sim_state_v1';
  static const _groupKey = 'act_lb_group_id_v1';
  static const _tickInterval = Duration(minutes: 5);

  // ── US name pool (hard to detect as fake) ────────────────────────────────
  static const _firstNames = [
    'Aidan', 'Alexandra', 'Andrew', 'Ashley', 'Aurora',
    'Beatriz', 'Benjamin', 'Brianna', 'Caleb', 'Caroline',
    'Charlotte', 'Christian', 'Cooper', 'Dakota', 'Danielle',
    'Derek', 'Ethan', 'Evelyn', 'Finnley', 'Gabrielle',
    'Grace', 'Hannah', 'Harper', 'Hayden', 'Isabella',
    'Jackson', 'Jaden', 'Jasmine', 'Julia', 'Kailey',
    'Kathryn', 'Kevin', 'Landon', 'Lauren', 'Lily',
    'Logan', 'Lucas', 'Madison', 'Mason', 'Megan',
    'Milo', 'Natalie', 'Nathaniel', 'Noah', 'Olivia',
    'Parker', 'Penelope', 'Quinn', 'Rebecca', 'Riley',
    'Ryan', 'Samantha', 'Sarah', 'Skyler', 'Sofia',
    'Spencer', 'Taylor', 'Tristan', 'Violet', 'Willow',
    'Xander', 'Yasmine', 'Zachary', 'Zoey', 'Amelia',
    'Bradley', 'Cassandra', 'Dominic', 'Eleanor', 'Felix',
    'Georgia', 'Hudson', 'Ivy', 'Jada', 'Kendall',
    'Leah', 'Marcella', 'Nicholas', 'Oscar', 'Paige',
    'Roland', 'Scarlett', 'Sebastian', 'Stella', 'Theodore',
    'Uriel', 'Vanessa', 'Weston', 'Ximena', 'Yolanda',
    'Zephyr', 'Abigail', 'Broderick', 'Celia', 'Dexter',
  ];

  static const _lastNames = [
    'Richards', 'Hamilton', 'Foster', 'Hill', 'Bell',
    'Valencia', 'Fischer', 'Chen', 'Wright', 'Stone',
    'Morrison', 'Park', 'Ellis', 'Wolf', 'Carver',
    'ACT26', 'Thomas', 'Nash', 'Rivera', 'Hughes',
    'Linton', 'Liu', 'Kim', 'Lopez', 'Bennett',
    'Baker', 'Moore', 'Grant', 'Ortiz', 'Price',
    'Hall', 'Coleman', 'Fox', 'Turner', 'Nguyen',
    'Santiago', 'Scott', 'Torres', 'Morris', 'Reed',
    'Wells', 'Peterson', 'Cruz', 'STEM', 'James',
    'Britt', 'ACT', 'Shaw', 'Hunter', 'Pro',
    'Clark', 'Star', 'Bryant', 'Phillips', 'Ramos',
    'Gomez', 'Edwards', 'Collins', 'Evans', 'Stewart',
    'Sanchez', 'Morris', 'Rogers', 'Reed', 'Cook',
    'Morgan', 'Bell', 'Murphy', 'Bailey', 'Rivera',
    'Cooper', 'Richardson', 'Cox', 'Howard', 'Ward',
    'Turner', 'Watson', 'Brooks', 'Kelly', 'Sanders',
    'Price', 'Bennett', 'Wood', 'Barnes', 'Ross',
    'Henderson', 'Coleman', 'Jenkins', 'Perry', 'Powell',
    'Long', 'Patterson', 'Hughes', 'Flores', 'Washington',
    'Butler', 'Simmons', 'Foster', 'Gonzales', 'Bryant',
  ];

  // ── Group assignment (persistent) ────────────────────────────────────────
  static Future<String> getOrCreateGroupId() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_groupKey);
    if (stored != null && stored.isNotEmpty) return stored;

    // 500 possible groups so the same person almost never shares a board
    // with another real user — makes the fake board undetectable by comparison.
    final groupId = 'G${(Random().nextInt(500) + 1).toString().padLeft(3, '0')}';
    await prefs.setString(_groupKey, groupId);
    return groupId;
  }

  // ── State management ──────────────────────────────────────────────────────
  static List<String> _generateIdentities() {
    final names = <String>{};
    var i = 0;
    while (names.length < 95 && i < 10000) {
      final first = _firstNames[i % _firstNames.length];
      final last = _lastNames[(i * 17 + 11) % _lastNames.length];
      final suffix = (i % 5 == 0) ? '_ACT' : (i % 7 == 0 ? '35' : (i % 9 == 0 ? '_Pro' : ''));
      names.add('$first$last$suffix'.replaceAll(' ', ''));
      i++;
    }
    return names.toList();
  }

  static Future<Map<String, dynamic>> _loadOrCreate(SharedPreferences prefs) async {
    final raw = prefs.getString(_stateKey);
    if (raw != null) {
      try {
        return jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {}
    }

    final rng = Random();
    final identities = _generateIdentities();
    final entries = <Map<String, dynamic>>[];

    for (var i = 0; i < identities.length; i++) {
      // ACT composite 1-36. Skew toward competitive upper range for
      // a leaderboard that feels genuinely challenging.
      // Top ~10 entries are clustered 33-36, rest spread 18-35.
      double score;
      if (i < 3) {
        score = 34 + rng.nextDouble() * 2; // 34-36
      } else if (i < 10) {
        score = 29 + rng.nextDouble() * 5; // 29-34
      } else if (i < 30) {
        score = 24 + rng.nextDouble() * 7; // 24-31
      } else {
        score = 18 + rng.nextDouble() * 10; // 18-28
      }
      score = score.clamp(1.0, 36.0);
      final accuracy = (0.45 + (score / 36) * 0.45 + (rng.nextDouble() * 0.06 - 0.03)).clamp(0.30, 0.99);

      entries.add({
        'displayName': identities[i],
        'compositeScore': score,
        'accuracy': accuracy,
        'attempts': rng.nextInt(35) + 3,
        'isReal': false,
      });
    }

    // Sort descending by score for initial state
    entries.sort((a, b) => (b['compositeScore'] as num).compareTo(a['compositeScore'] as num));

    final state = {
      'lastTick': DateTime.now().toIso8601String(),
      'entries': entries,
    };
    await prefs.setString(_stateKey, jsonEncode(state));
    return state;
  }

  /// Apply one tick of simulated score drift.
  /// Net slightly upward (people keep practicing) with enough downward
  /// noise that the leaderboard never looks mechanically monotonic.
  static Map<String, dynamic> _tick(Map<String, dynamic> state) {
    final lastTick = DateTime.parse(state['lastTick'] as String);
    final now = DateTime.now();
    final elapsed = now.difference(lastTick);
    if (elapsed < _tickInterval) return state;

    final ticks = min(12, (elapsed.inMinutes ~/ 5)); // cap at 12 ticks (1hr)
    final rng = Random();
    final entries = (state['entries'] as List).cast<Map<String, dynamic>>();

    for (final e in entries) {
      var score = (e['compositeScore'] as num).toDouble();
      var accuracy = (e['accuracy'] as num).toDouble();
      for (var t = 0; t < ticks; t++) {
        // ACT scale is 1-36, so drifts are small
        score += (rng.nextDouble() * 1.4) - 0.55; // net +0.85 per tick
        accuracy += (rng.nextDouble() * 0.025) - 0.010;
      }
      e['compositeScore'] = score.clamp(1.0, 36.0);
      e['accuracy'] = accuracy.clamp(0.30, 0.99);
    }

    // Re-sort after drift
    entries.sort((a, b) => (b['compositeScore'] as num).compareTo(a['compositeScore'] as num));

    return {
      'lastTick': now.toIso8601String(),
      'entries': entries,
    };
  }

  /// Simulate a brief sync delay so the UI shows a loading state,
  /// making the local board feel like a live server refresh.
  /// Fully offline — no network call needed; all data is local.
  static Future<void> _simulateSync() async {
    await Future.delayed(const Duration(milliseconds: 600));
  }

  /// Returns simulated board entries (without the real user merged in).
  static Future<List<Map<String, dynamic>>> getSimulatedEntries({bool sync = true}) async {
    if (sync) await _simulateSync();
    final prefs = await SharedPreferences.getInstance();
    var state = await _loadOrCreate(prefs);
    final ticked = _tick(state);
    if (!identical(ticked, state)) {
      state = ticked;
      await prefs.setString(_stateKey, jsonEncode(state));
    }
    return (state['entries'] as List).cast<Map<String, dynamic>>();
  }

  /// Merge the user's real entries with simulated ones.
  /// Returns full ranked list as [LeaderboardEntry] objects.
  static Future<List<LeaderboardEntry>> buildMergedBoard(
    List<Map<String, dynamic>> realRows, {
    bool sync = true,
  }) async {
    final simulated = await getSimulatedEntries(sync: sync);
    final combined = <Map<String, dynamic>>[
      ...simulated,
      ...realRows.map((r) => {
            'displayName': r['displayName'],
            'compositeScore': r['compositeScore'],
            'accuracy': r['accuracy'],
            'attempts': r['attempts'] ?? 1,
            'isReal': true,
          }),
    ];
    combined.sort((a, b) => (b['compositeScore'] as num).compareTo(a['compositeScore'] as num));

    return List.generate(combined.length, (i) {
      final e = combined[i];
      String badge = '';
      if (i == 0) badge = 'gold';
      else if (i == 1) badge = 'silver';
      else if (i == 2) badge = 'bronze';
      else if (i < 5) badge = 'top5';
      else if (i < 10) badge = 'top10';

      return LeaderboardEntry(
        rank: i + 1,
        displayName: e['displayName'] as String,
        compositeScore: (e['compositeScore'] as num).toDouble(),
        accuracy: (e['accuracy'] as num).toDouble(),
        attempts: e['attempts'] as int? ?? 0,
        isRealUser: e['isReal'] as bool? ?? false,
        badge: badge,
        updatedAt: DateTime.now(),
      );
    });
  }

  /// Record a user's score and trigger leaderboard update.
  static Future<void> recordScore(
    String displayName,
    double compositeScore,
    double accuracy,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final stateRaw = prefs.getString(_stateKey);
    if (stateRaw == null) return;

    final state = jsonDecode(stateRaw) as Map<String, dynamic>;
    // User's score is not stored in the simulated state — it is injected
    // at render time via buildMergedBoard(). Nothing to do here except
    // ensure the local DB has it (called separately from the screen).
  }

  /// Check if the user has hit a milestone rank for badge popup.
  /// Returns 'gold', 'silver', 'bronze', 'top5', 'top10', or null.
  static String? checkMilestone(int rank) {
    if (rank == 1) return 'gold';
    if (rank == 2) return 'silver';
    if (rank == 3) return 'bronze';
    if (rank <= 5) return 'top5';
    if (rank <= 10) return 'top10';
    return null;
  }
}
