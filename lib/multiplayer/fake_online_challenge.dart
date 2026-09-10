import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

enum OnlineChallengeRegion { usa, foreign }

/// Everything about the fake opponent is driven by this profile.
/// Different personalities produce measurably different play patterns.
class _OpponentProfile {
  final String name;

  /// Base speed in seconds per question — lower = faster
  final double baseSpeedSec;

  /// Probability of skipping / timing out on a question (0.0–1.0)
  final double skipRate;

  /// Probability of going AFK mid-match for a short break
  final double afkRate;

  /// Accuracy (0.0–1.0) — how often they answer correctly
  final double accuracy;

  /// Variability multiplier — high = erratic timing, low = consistent
  final double variability;

  const _OpponentProfile({
    required this.name,
    required this.baseSpeedSec,
    required this.skipRate,
    required this.afkRate,
    required this.accuracy,
    required this.variability,
  });
}

/// Simulates the complete online challenge experience client-side.
///
/// Key human-behaviour principles implemented:
///   1. Time-of-day governs who is online and how alert they are.
///   2. Every opponent has a distinct personality (speed, accuracy, skip rate).
///   3. Answer timing is randomised per-question (fast/medium/slow) with natural
///      variance, never robot-constant.
///   4. Opponents sometimes skip (time runs out) — just like a distracted human.
///   5. Opponents sometimes pause (AFK) mid-match — bathroom break, notification.
///   6. Late-night sessions are sparse: few opponents, longer wait times, lower
///      activity.  Midnight is nearly empty.
///   7. Weekend mornings are busier.  Weekday afternoons are moderate.
///   8. Matchmaking wait time reflects real online-user density for the hour.
class FakeOnlineChallenge {
  static final _rng = Random();

  // ── "Feels like a real person" freshness pools ─────────────────────────────
  // Real opponents don't reappear seconds after you last saw them, and a real
  // person doesn't say the exact same line twice in a row. These two pools
  // remember what was recently used and steer future picks away from it for
  // a random cool-down window, so the same name or line won't resurface for
  // a while — without ever permanently banning anything (if the whole pool
  // is on cooldown we just fall back to using it anyway).
  //
  // Opponent names persist across app restarts (SharedPreferences) since a
  // 30–60 minute memory should survive the app being closed and reopened.
  // Chat/opening/closing lines only need to avoid repeating within the
  // current session, so those stay in memory only.
  static SharedPreferences? _prefsCache;
  static Future<SharedPreferences> _prefs() async =>
      _prefsCache ??= await SharedPreferences.getInstance();

  static const _nameCooldownKey = 'sj_act_recent_opponent_names_v1';
  static Map<String, int>? _nameCooldownCache;

  static Future<Map<String, int>> _loadNameCooldowns() async {
    if (_nameCooldownCache != null) return _nameCooldownCache!;
    final now = DateTime.now().millisecondsSinceEpoch;
    var result = <String, int>{};
    try {
      final p = await _prefs();
      final raw = p.getString(_nameCooldownKey);
      if (raw != null) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        map.forEach((k, v) {
          final exp = v is int ? v : int.tryParse(v.toString()) ?? 0;
          if (exp > now) result[k] = exp;
        });
      }
    } catch (_) {}
    _nameCooldownCache = result;
    return result;
  }

  static Future<void> _saveNameCooldowns() async {
    if (_nameCooldownCache == null) return;
    try {
      final p = await _prefs();
      await p.setString(_nameCooldownKey, jsonEncode(_nameCooldownCache));
    } catch (_) {}
  }

  /// Picks a name from [pool] that hasn't been used as an opponent in the
  /// last 30–60 minutes (randomised per pick, just like the rest of this
  /// file's "feels human" timing), then puts it on cooldown for a fresh
  /// random 30–60 minute window.
  static Future<String> _pickFreshName(List<String> pool) async {
    final cooldowns = await _loadNameCooldowns();
    final now = DateTime.now().millisecondsSinceEpoch;
    var available = pool.where((n) => (cooldowns[n] ?? 0) <= now).toList();
    if (available.isEmpty) available = pool; // pool exhausted — better a repeat than nobody
    final name = available[_rng.nextInt(available.length)];
    final minutes = 30 + _rng.nextInt(31); // 30–60 minutes
    cooldowns[name] = now + minutes * 60 * 1000;
    if (cooldowns.length > 600) {
      cooldowns.removeWhere((_, v) => v <= now); // periodic housekeeping
    }
    unawaited(_saveNameCooldowns());
    return name;
  }

  // In-memory only — chat lines just need to avoid repeating within the
  // current session, not across app restarts.
  static final Map<String, int> _recentMessages = {};

  static String _pickFreshMessage(List<String> pool, {int minMinutes = 20, int maxMinutes = 40}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    var available = pool.where((m) => (_recentMessages[m] ?? 0) <= now).toList();
    if (available.isEmpty) available = pool;
    final msg = available[_rng.nextInt(available.length)];
    final minutes = minMinutes + _rng.nextInt(maxMinutes - minMinutes + 1);
    _recentMessages[msg] = now + minutes * 60 * 1000;
    if (_recentMessages.length > 400) {
      _recentMessages.removeWhere((_, v) => v <= now);
    }
    return msg;
  }

  // ── Name pools ─────────────────────────────────────────────────────────────
  // Built programmatically from first-name × surname/tag pools instead of one
  // giant hand-typed list, so each room has hundreds of distinct-looking
  // opponent names without repeating the same handful over and over.
  static final List<String> _usaNames = _buildUsaNamePool();
  static final List<String> _foreignNames = _buildForeignNamePool();

  static const List<String> _usaFirstNames = [
    "Aidan", "Alexandra", "Andrew", "Ashley", "Aurora", "Beatriz", "Benjamin",
    "Brianna", "Caleb", "Caroline", "Charlotte", "Christian", "Cooper",
    "Dakota", "Danielle", "Derek", "Ethan", "Evelyn", "Finnley", "Gabrielle",
    "Grace", "Hannah", "Harper", "Hayden", "Isabella", "Jackson", "Jaden",
    "Jasmine", "Julia", "Kailey", "Kathryn", "Kevin", "Landon", "Lauren",
    "Lily", "Logan", "Lucas", "Madison", "Mason", "Megan", "Milo", "Natalie",
    "Nathaniel", "Noah", "Olivia", "Parker", "Penelope", "Quinn", "Rebecca",
    "Riley", "Ryan", "Samantha", "Sarah", "Skyler", "Sofia", "Spencer",
    "Taylor", "Tristan", "Violet", "Willow", "Xander", "Yasmine", "Zachary",
    "Zoey", "Amelia", "Bradley", "Cassandra", "Dominic", "Eleanor", "Felix",
    "Georgia", "Hudson", "Ivy", "Jada", "Kendall", "Leah", "Marcella",
    "Nicholas", "Oscar", "Paige", "Roland", "Scarlett", "Sebastian", "Stella",
    "Theodore", "Uriel", "Vanessa", "Weston", "Ximena", "Yolanda", "Zephyr",
    "Abigail", "Broderick", "Celia", "Dexter", "Gwendolyn", "Hector", "Irina",
    "Jordan", "Kyle",
  ];

  static const List<String> _usaSurnameTags = [
    "Reed", "Hart", "Wright", "Stone", "Bell", "Ford", "Brown", "Moore",
    "Bach", "Owen", "Grant", "Hall", "Price", "Cox", "King", "Morris",
    "Turner", "Hunt", "James", "Britt", "Shaw", "Fox", "Ward", "Rivera",
    "Elite", "Pro", "ACT", "Top", "STEM", "35", "36", "99", "26", "2026",
    "_US", "X", "Star",
  ];

  static List<String> _buildUsaNamePool() {
    final result = <String>[];
    for (final first in _usaFirstNames) {
      for (final tag in _usaSurnameTags) {
        result.add('$first$tag');
      }
    }
    return result;
  }

  static const List<String> _foreignFirstNames = [
    "Liam", "Emma", "Olivia", "Nathan", "Sofia", "Lucas", "Mei", "Priya",
    "Raj", "Anastasia", "Yuki", "Pierre", "Hans", "Freya", "Carlos", "Greta",
    "Sven", "Isabel", "Kenji", "Layla", "Valentina", "Diego", "Ana", "Ivan",
    "Bianca", "Matthew", "Oscar", "Chloe", "Nicolas", "Amelia", "Harris",
    "Sophie", "Marc", "Rosa", "Klaus", "Anna", "Miguel", "Lin", "Yuri",
    "Aisha", "Ferdinand", "Victoria", "Takeshi", "Beatrice", "Arjun", "Zara",
    "Philippe", "Akira", "Elena", "Rui", "Noor", "Mateus", "Ingrid", "Dmitri",
    "Camila", "Youssef", "Katarina", "Tomas", "Alina", "Rafael", "Mira",
  ];

  static const List<String> _foreignCountryTags = [
    "UK", "CA", "NZ", "DE", "FR", "AU", "JP", "IN", "RU", "ES", "SE", "NO",
    "CN", "AE", "IT", "MX", "GR", "PL", "BR", "PH", "AR", "KR", "NL", "CH",
    "PT",
  ];

  static const List<String> _foreignFlairTags = [
    "", "_ACT", "_Pro", "35", "36", "_Top", "_Global",
  ];

  static List<String> _buildForeignNamePool() {
    final result = <String>[];
    for (final first in _foreignFirstNames) {
      for (final code in _foreignCountryTags) {
        final flair = _foreignFlairTags[(first.length + code.length) % _foreignFlairTags.length];
        result.add('$first$code$flair');
      }
    }
    return result;
  }

  // ── Free-form chat replies ─────────────────────────────────────────────────
  // Instead of picking from one short fixed list (which repeats fast),
  // replies are assembled from three independent phrase banks. That gives
  // thousands of distinct combinations, so a real back-and-forth chat never
  // sounds like it's playing back the same handful of lines.
  static const List<String> _replyOpeners = [
    "Ha!", "Nice.", "For real?", "Haha", "Okay", "Solid.", "Word.",
    "Respect.", "Bet.", "True.", "Fair enough.", "Same here.", "Real talk.",
    "Facts.", "I hear you.", "Makes sense.", "Good point.", "Interesting.",
    "Right?", "Totally.", "For sure.", "Yep.", "Definitely.", "Agreed.",
    "Lol.", "Oh really?", "Fair.", "Noted.", "Gotcha.", "Hah, fair.",
  ];

  static const List<String> _replyMiddles = [
    "good luck out there", "let's see how this goes", "this should be fun",
    "may the best score win", "ready when you are", "let's get into it",
    "hope you studied", "I've been grinding for this", "bring your A-game",
    "let's make it a good one", "here we go", "let's do this thing",
    "time to lock in", "focus mode on", "no pressure, okay maybe a little",
    "let's see who's sharper today", "game time", "let's find out",
    "curious how this plays out", "should be a good match",
    "I've got my calculator ready", "let's keep it clean",
    "may the odds be in your favor", "hope your wifi holds up",
    "this is going to be close I bet", "let's see those brain cells work",
  ];

  static const List<String> _replyClosers = [
    "!", ".", " 😅", " lol", " haha", "!!", "...", " for real", " though",
    " honestly", "", "", "", "",
  ];

  /// Returns a random, natural-sounding chat reply assembled from the three
  /// phrase banks above (openers × middles × closers = 4,000+ combinations).
  static String randomChatReply() {
    // Openers and middles are picked fresh (not repeated for a while) so
    // back-to-back replies never feel like they're playing back the same
    // line; closers are tiny flourishes so they're left free to repeat.
    final opener = _pickFreshMessage(_replyOpeners, minMinutes: 3, maxMinutes: 12);
    final middle = _pickFreshMessage(_replyMiddles, minMinutes: 15, maxMinutes: 35);
    final closer = _replyClosers[_rng.nextInt(_replyClosers.length)];
    return '$opener ${middle[0].toUpperCase()}${middle.substring(1)}$closer';
  }

  // ── Time-of-day activity model ─────────────────────────────────────────────
  /// Returns a multiplier (0.05–1.0) representing how many players are
  /// likely online right now.  Drives wait times and timeout probability.
  ///
  /// Based on realistic US student study patterns:
  ///   00-05  nearly empty (midnight/early hours)
  ///   06-07  very sparse (before school)
  ///   08-11  moderate (school hours, some free periods)
  ///   12-14  decent (lunch, study hall)
  ///   15-18  peak (after school)
  ///   19-22  high (evening study)
  ///   23     dropping off (late night)
  static double _activityFactor() {
    final hour = DateTime.now().hour;
    final dayOfWeek = DateTime.now().weekday; // 1=Mon … 7=Sun
    final isWeekend = dayOfWeek == 6 || dayOfWeek == 7;

    final double base;
    if (hour >= 0 && hour < 5)       base = 0.04; // midnight–5am: almost empty
    else if (hour == 5)              base = 0.08; // 5am: near-empty
    else if (hour == 6)              base = 0.15; // early risers
    else if (hour == 7)              base = 0.22; // getting ready for school
    else if (hour >= 8 && hour < 12) base = isWeekend ? 0.65 : 0.30; // school/weekend morning
    else if (hour >= 12 && hour < 14)base = isWeekend ? 0.70 : 0.50; // lunch
    else if (hour >= 14 && hour < 16)base = isWeekend ? 0.80 : 0.45; // afternoon
    else if (hour >= 16 && hour < 18)base = isWeekend ? 0.85 : 0.90; // after school PEAK
    else if (hour >= 18 && hour < 21)base = 0.95; // evening PEAK
    else if (hour == 21)             base = 0.80; // winding down
    else if (hour == 22)             base = 0.55; // late evening
    else                             base = 0.20; // 23:00 — late night, sparse

    return base.clamp(0.04, 1.0);
  }

  /// Returns a human-readable status for the matchmaking screen.
  static String _activityStatusLabel() {
    final f = _activityFactor();
    if (f >= 0.85) return 'High activity — lots of students online right now.';
    if (f >= 0.60) return 'Active — good chance of finding an opponent.';
    if (f >= 0.35) return 'Moderate activity — may take a moment.';
    if (f >= 0.15) return 'Quiet period — fewer students online at this hour.';
    return 'Very quiet — most students are offline. Searching...';
  }

  // ── Opponent personality profiles ──────────────────────────────────────────
  /// Different human personalities — chosen randomly weighted by time of day.
  /// Night owls appear more at late hours; fast competitive types peak in
  /// the afternoon.
  static const List<_OpponentProfile> _personalityPool = [
    _OpponentProfile(name: '',  baseSpeedSec: 8,  skipRate: 0.04, afkRate: 0.02, accuracy: 0.88, variability: 0.6),   // fast, focused
    _OpponentProfile(name: '',  baseSpeedSec: 14, skipRate: 0.08, afkRate: 0.04, accuracy: 0.72, variability: 0.9),   // average student
    _OpponentProfile(name: '',  baseSpeedSec: 22, skipRate: 0.14, afkRate: 0.07, accuracy: 0.60, variability: 1.2),   // slower, easily distracted
    _OpponentProfile(name: '',  baseSpeedSec: 10, skipRate: 0.05, afkRate: 0.01, accuracy: 0.95, variability: 0.4),   // high-achiever, very consistent
    _OpponentProfile(name: '',  baseSpeedSec: 30, skipRate: 0.20, afkRate: 0.15, accuracy: 0.50, variability: 1.8),   // casual/unmotivated (night owl)
    _OpponentProfile(name: '',  baseSpeedSec: 18, skipRate: 0.10, afkRate: 0.05, accuracy: 0.78, variability: 1.0),   // slightly-above-average
    _OpponentProfile(name: '',  baseSpeedSec: 12, skipRate: 0.07, afkRate: 0.03, accuracy: 0.82, variability: 0.7),   // competitive afternoon student
    _OpponentProfile(name: '',  baseSpeedSec: 40, skipRate: 0.25, afkRate: 0.20, accuracy: 0.45, variability: 2.0),   // very distracted (midnight)
  ];

  static _OpponentProfile _pickPersonality() {
    final f = _activityFactor();
    // At low activity (late night) weight toward slow/distracted profiles
    if (f < 0.15) {
      return _personalityPool[_rng.nextBool() ? 7 : 4]; // distracted / casual
    }
    if (f < 0.35) {
      return _personalityPool[_rng.nextInt(3) + 3]; // mix of average/high/casual
    }
    // Normal hours: any profile
    return _personalityPool[_rng.nextInt(_personalityPool.length)];
  }

  // ── Internet check ─────────────────────────────────────────────────────────
  static Future<bool> hasRealInternet({Duration timeout = const Duration(seconds: 6)}) async {
    const probeUrls = [
      'https://www.google.com/generate_204',
      'https://www.gstatic.com/generate_204',
      'https://cloudflare.com/cdn-cgi/trace',
      'https://www.apple.com/library/test/success.html',
    ];
    final completer = Completer<bool>();
    var remaining = probeUrls.length;
    for (final url in probeUrls) {
      _probe(url, timeout).then((ok) {
        if (completer.isCompleted) return;
        if (ok) {
          completer.complete(true);
        } else {
          remaining--;
          if (remaining == 0) completer.complete(false);
        }
      });
    }
    return completer.future;
  }

  static Future<bool> _probe(String url, Duration timeout) async {
    try {
      final r = await http.get(Uri.parse(url)).timeout(timeout);
      return r.statusCode >= 200 && r.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  // ── Matchmaking ────────────────────────────────────────────────────────────
  /// Yields status strings while searching, then either:
  ///   "joined:<name>"    — opponent found
  ///   "timeout"          — nobody joined
  ///   "no_internet"      — offline
  static Stream<String> hostWait(OnlineChallengeRegion region) async* {
    yield 'Creating your match...';
    final hasNet = await hasRealInternet();
    if (!hasNet) { yield 'no_internet'; return; }

    yield _activityStatusLabel();
    await Future.delayed(const Duration(seconds: 2));

    final activity = _activityFactor();

    // Probability no one joins scales inversely with activity
    final timeoutChance = (1.0 - activity) * 0.55;
    if (_rng.nextDouble() < timeoutChance) {
      // Long wait, then nobody
      final waitSec = _waitSeconds(activity);
      int elapsed = 0;
      while (elapsed < waitSec) {
        final chunk = min(5, waitSec - elapsed);
        await Future.delayed(Duration(seconds: chunk));
        elapsed += chunk;
        yield _searchingLabel(elapsed, waitSec);
      }
      yield 'timeout';
      return;
    }

    // Someone joins after a time that feels natural for the hour
    final joinDelaySec = _joinDelaySec(activity);
    int elapsed = 0;
    while (elapsed < joinDelaySec) {
      final chunk = min(4, joinDelaySec - elapsed);
      await Future.delayed(Duration(seconds: chunk));
      elapsed += chunk;
      yield _searchingLabel(elapsed, joinDelaySec);
    }

    final pool = region == OnlineChallengeRegion.usa ? _usaNames : _foreignNames;
    yield 'joined:${await _pickFreshName(pool)}';
  }

  static Stream<String> joinMatch(OnlineChallengeRegion region) async* {
    yield 'Looking for an open match...';
    final hasNet = await hasRealInternet();
    if (!hasNet) { yield 'no_internet'; return; }

    final activity = _activityFactor();
    await Future.delayed(Duration(seconds: 1 + _rng.nextInt(3)));

    final noMatchChance = (1.0 - activity) * 0.50;
    if (_rng.nextDouble() < noMatchChance) { yield 'no_open_match'; return; }

    final pool = region == OnlineChallengeRegion.usa ? _usaNames : _foreignNames;
    yield 'joined:${await _pickFreshName(pool)}';
  }

  static int _waitSeconds(double activity) {
    // Activity 1.0 → ~6s wait,  0.04 → ~90s wait
    final base = 6 + ((1.0 - activity) * 84).round();
    return base + _rng.nextInt(15);
  }

  static int _joinDelaySec(double activity) {
    final base = 2 + ((1.0 - activity) * 28).round();
    return (base + _rng.nextInt(8)).clamp(2, 50);
  }

  static String _searchingLabel(int elapsed, int total) {
    if (elapsed < 5)  return 'Searching for a challenger...';
    if (elapsed < 12) return 'Matching you with a student...';
    if (elapsed < 22) return 'Still searching — this might take a moment.';
    if (elapsed < 35) return 'Looking further afield...';
    return 'Almost there — checking remaining open rooms...';
  }

  // ── Per-question opponent timing ───────────────────────────────────────────
  /// Returns how many seconds the opponent takes to answer question [qIndex].
  ///
  /// Models realistic human behaviour:
  ///   - Earlier questions tend to be answered faster (still warm-up)
  ///   - Later questions slow down (fatigue, harder material)
  ///   - Night-time opponents are slower and more erratic
  ///   - Occasionally an opponent is "thinking hard" and takes much longer
  static int opponentThinkSeconds({
    required _OpponentProfile profile,
    required int qIndex,
    required int totalQuestions,
  }) {
    // Fatigue factor: slow down slightly as match progresses
    final fatigue = 1.0 + (qIndex / totalQuestions) * 0.35;

    // Night-time makes everyone slower
    final hour = DateTime.now().hour;
    final nightPenalty = (hour >= 23 || hour < 5) ? 1.6 : (hour >= 21 ? 1.2 : 1.0);

    // Base seconds with variability
    final variance = 1.0 + (_rng.nextDouble() * 2 - 1) * profile.variability * 0.5;
    var seconds = (profile.baseSpeedSec * fatigue * nightPenalty * variance).round();

    // Occasionally the opponent "thinks really hard" (2× slower)
    if (_rng.nextDouble() < 0.10) seconds = (seconds * 2.1).round();

    // Very rarely they're suspiciously fast (they guessed without thinking)
    if (_rng.nextDouble() < 0.04) seconds = 2 + _rng.nextInt(3);

    return seconds.clamp(2, 90);
  }

  /// Returns true if the opponent skips (times out) on this question.
  static bool opponentSkipsQuestion(_OpponentProfile profile) {
    final hour = DateTime.now().hour;
    final nightBoost = (hour >= 23 || hour < 5) ? 1.8 : 1.0;
    return _rng.nextDouble() < (profile.skipRate * nightBoost).clamp(0.0, 0.45);
  }

  /// Returns seconds of an AFK pause (if the opponent goes AFK this round).
  static int? opponentAfkDuration(_OpponentProfile profile) {
    final hour = DateTime.now().hour;
    final nightBoost = (hour >= 22) ? 1.5 : 1.0;
    if (_rng.nextDouble() >= (profile.afkRate * nightBoost).clamp(0, 0.40)) return null;
    // AFK: 8–45 seconds (bathroom, notification, distraction)
    return 8 + _rng.nextInt(37);
  }

  /// Whether the opponent is correct on this question.
  static bool opponentIsCorrect(_OpponentProfile profile) {
    return _rng.nextDouble() < profile.accuracy;
  }

  // ── Per-question opponent session (fixes a bug where re-simulating the
  // whole match from question 0 every round produced impossible progress
  // numbers, e.g. "2 correct out of 1 answered") ─────────────────────────────
  static final Map<int, _OpponentProfile> _sessionProfiles = {};
  static int _nextSessionId = 1;

  /// Call once when a live match begins. Returns an opaque session id that
  /// keeps the opponent's "personality" (speed, accuracy, skip/AFK
  /// tendencies) consistent across every question in that match, instead of
  /// re-rolling it (and re-simulating from scratch) each round.
  static int startOpponentSession() {
    final id = _nextSessionId++;
    _sessionProfiles[id] = _pickPersonality();
    return id;
  }

  static void endOpponentSession(int sessionId) {
    _sessionProfiles.remove(sessionId);
  }

  /// Simulates the opponent working exactly ONE question (thinking, maybe
  /// going AFK, then answering or skipping) using the personality picked
  /// for [sessionId]. Call this fresh for every question the player is on —
  /// it does not loop over the whole match, so it can't drift out of sync
  /// with which question is actually on screen.
  static Stream<OpponentEvent> opponentAnswerForQuestion({
    required int sessionId,
    required int qIndex,
    required int totalQuestions,
  }) async* {
    final profile = _sessionProfiles[sessionId] ?? _pickPersonality();

    yield OpponentEvent.thinking(questionIndex: qIndex);

    final afkSec = opponentAfkDuration(profile);
    if (afkSec != null) {
      yield OpponentEvent.afk(seconds: afkSec);
      await Future.delayed(Duration(seconds: afkSec));
    }

    final thinkSec = opponentThinkSeconds(profile: profile, qIndex: qIndex, totalQuestions: totalQuestions);
    await Future.delayed(Duration(seconds: thinkSec));

    // NOTE: this used to also roll an independent opponentSkipsQuestion()
    // chance here and yield a "skipped" event on its own, completely
    // separate from the actual per-question clock the player sees. That
    // meant the opponent could show as having "skipped" a question at, say,
    // 8 seconds into a 60-second timer, for no visible reason — which
    // isn't how a real opponent works: they only miss a question because
    // the clock actually ran out, not because of some independent internal
    // coin flip. The only place a skip should ever come from is the match
    // screen's own timeout handling (_forceAdvanceOnTimeout), which already
    // covers "they were too slow" naturally via how long thinkSec/afkSec
    // above can run — a genuinely slow or distracted profile will
    // sometimes still be mid-thought when the real timer hits zero, and
    // that's scored as a timeout there. This function itself now always
    // resolves to an actual answer.
    final isCorrect = opponentIsCorrect(profile);
    yield OpponentEvent.answered(questionIndex: qIndex, answeredSoFar: 0, isCorrect: isCorrect);
  }

  // ── Full match simulation ──────────────────────────────────────────────────
  /// Streams per-question events as the opponent plays through the match.
  ///
  /// Each event is one of:
  ///   "thinking"         — opponent has started thinking
  ///   "afk:<seconds>"    — opponent went AFK for N seconds
  ///   "answered:<A|B|C|D|skip>" — opponent answered (or skipped)
  ///   "done:<score>"     — match complete, final score
  static Stream<String> simulateOpponentMatch({
    required int totalQuestions,
    required double userAccuracy,
    String? opponentName,
  }) async* {
    final profile = _pickPersonality();

    int opponentCorrect = 0;

    for (int q = 0; q < totalQuestions; q++) {
      yield 'thinking';

      // AFK check BEFORE answering this question
      final afkSec = opponentAfkDuration(profile);
      if (afkSec != null) {
        yield 'afk:$afkSec';
        await Future.delayed(Duration(seconds: afkSec));
      }

      // Think time
      final thinkSec = opponentThinkSeconds(
        profile: profile,
        qIndex: q,
        totalQuestions: totalQuestions,
      );
      await Future.delayed(Duration(seconds: thinkSec));

      // Did they skip (time out)?
      if (opponentSkipsQuestion(profile)) {
        yield 'answered:skip';
        continue;
      }

      // Answer — correct or not
      final correct = opponentIsCorrect(profile);
      if (correct) opponentCorrect++;

      // Pick a random letter (A/B/C/D) — we don't track which is right
      const letters = ['A', 'B', 'C', 'D'];
      yield 'answered:${letters[_rng.nextInt(4)]}';
    }

    // Convert raw correct count to ACT 1-36 scale
    final pct = totalQuestions == 0 ? 0.0 : opponentCorrect / totalQuestions;
    final actScore = (1 + pct * 35).clamp(1.0, 36.0);
    yield 'done:${actScore.toStringAsFixed(1)}';
  }

  // ── Simple score generation (used when full simulation isn't needed) ───────
  /// Generate a realistic ACT composite score for the opponent.
  static double simulateOpponentScore(int totalQuestions, double userAccuracy) {
    if (totalQuestions <= 0) return 1.0;
    final profile = _pickPersonality();
    // Opponent accuracy influenced by their profile but also pulled toward
    // the user's accuracy (makes for a competitive, not punishing, match)
    final opAcc = (profile.accuracy * 0.6 + userAccuracy * 0.4 +
        (_rng.nextDouble() * 0.14 - 0.07)).clamp(0.20, 1.0);
    return (1 + opAcc * 35).clamp(1.0, 36.0);
  }

  // ── Pre-match chat messages from opponent ──────────────────────────────────
  /// Returns a realistic opening message from the opponent.
  /// Message style varies by time of day.
  static String opponentOpeningMessage(String opponentName) {
    final hour = DateTime.now().hour;
    final isLateNight = hour >= 23 || hour < 5;
    final isEarlyMorning = hour >= 5 && hour < 8;
    final isEvening = hour >= 18 && hour < 22;

    final lateNightMessages = [
      "Can\'t sleep, might as well study lol",
      "Up late cramming. Let\'s go.",
      "Everyone\'s asleep but me. Ready.",
      "Night session. Let\'s do this.",
      "Couldn\'t sleep. Good timing.",
    ];
    final morningMessages = [
      "Early morning session. Let\'s go!",
      "Good morning! Ready to start.",
      "Starting the day with practice.",
      "Morning grind. Good luck!",
      "Up early. Let\'s get it done.",
    ];
    final eveningMessages = [
      "Evening study session — ready!",
      "Done with dinner. Let\'s go.",
      "Good luck tonight!",
      "Evening grind. May the best student win.",
      "Ready. Let\'s get this done.",
    ];
    final defaultMessages = [
      "Good luck!",
      "Ready when you are.",
      "Let\'s see what you\'ve got.",
      "Ready. May the best score win.",
      "This should be close. Good luck!",
      "Let\'s go!",
      "Ready.",
      "Good luck — you\'ll need it.",
      "Feeling good about this. Let\'s go.",
    ];

    List<String> pool;
    if (isLateNight)      pool = lateNightMessages;
    else if (isEarlyMorning) pool = morningMessages;
    else if (isEvening)   pool = eveningMessages;
    else                  pool = defaultMessages;

    return _pickFreshMessage(pool);
  }

  /// Returns a reaction from the opponent after the match ends.
  static String opponentEndMessage({required bool opponentWon}) {
    final wonMessages = [
      "Good game! Keep practising.",
      "Nice match. You\'ll get it next time.",
      "GG! That was close.",
      "Good effort. See you next time.",
      "Well played — keep going.",
    ];
    final lostMessages = [
      "Good game! You got me.",
      "Nice one. You were sharper today.",
      "GG. Well played.",
      "You earned it. Well done.",
      "Solid. I\'ll do better next time.",
    ];
    final pool = opponentWon ? wonMessages : lostMessages;
    return _pickFreshMessage(pool);
  }

  // ── Bet proposals ──────────────────────────────────────────────────────────
  static ChallengeBetProposal? fakeOpponentBetProposal({bool guaranteed = false}) {
    if (!guaranteed) {
      // 55% chance at high activity, up to 90% at peak — bumped up from the
      // original 30-55% because compounded with an outer "does the host even
      // consider it" check elsewhere, bets were showing up far too rarely to
      // ever be seen in normal testing.
      final activity = _activityFactor();
      final proposalChance = 0.55 + activity * 0.35;
      if (_rng.nextDouble() > proposalChance) return null;
    }

    final bets = [
      ChallengeBetProposal(
        type: 'ranking',
        value: '${_rng.nextInt(5) + 1}_points',
        description: 'Winner gains ${_rng.nextInt(5) + 1} ranking points; loser loses the same.',
      ),
      ChallengeBetProposal(
        type: 'badge',
        value: 'challenger_badge',
        description: 'Loser forfeits their Challenger badge for 24 hours.',
      ),
      ChallengeBetProposal(
        type: 'access',
        value: '${(_rng.nextInt(4) + 1) * 2}_hours',
        description: 'Loser\'s online challenge access is paused for ${(_rng.nextInt(4) + 1) * 2} hours.',
      ),
      ChallengeBetProposal(
        type: 'ranking_reset',
        value: 'top10_slot',
        description: 'Loser drops one leaderboard tier for this session.',
      ),
      ChallengeBetProposal(
        type: 'bragging_rights',
        value: 'top_challenger',
        description: 'Winner gets pinned as "Top Challenger" in the room for the rest of the day.',
      ),
      ChallengeBetProposal(
        type: 'study_task',
        value: 'extra_set',
        description: 'Loser has to finish one extra practice set before their next Online Challenge.',
      ),
    ];
    return bets[_rng.nextInt(bets.length)];
  }

  // ── Opponent progress event stream ─────────────────────────────────────────
  /// Used by the match screen to show what the opponent is doing in real time.
  static Stream<OpponentEvent> opponentEventStream({
    required int totalQuestions,
    required double userAccuracy,
  }) async* {
    final profile = _pickPersonality();
    int answered = 0;
    int correct = 0;

    for (int q = 0; q < totalQuestions; q++) {
      yield OpponentEvent.thinking(questionIndex: q);

      // AFK
      final afkSec = opponentAfkDuration(profile);
      if (afkSec != null) {
        yield OpponentEvent.afk(seconds: afkSec);
        await Future.delayed(Duration(seconds: afkSec));
      }

      // Think
      final thinkSec = opponentThinkSeconds(
        profile: profile,
        qIndex: q,
        totalQuestions: totalQuestions,
      );
      await Future.delayed(Duration(seconds: thinkSec));

      // Skip?
      if (opponentSkipsQuestion(profile)) {
        yield OpponentEvent.skipped(questionIndex: q, answeredSoFar: answered);
        continue;
      }

      // Answer
      final isCorrect = opponentIsCorrect(profile);
      if (isCorrect) correct++;
      answered++;
      yield OpponentEvent.answered(
        questionIndex: q,
        answeredSoFar: answered,
        isCorrect: isCorrect,
      );
    }

    final pct = totalQuestions == 0 ? 0.0 : correct / totalQuestions;
    final actScore = (1 + pct * 35).clamp(1.0, 36.0);
    yield OpponentEvent.finished(actScore: actScore, totalAnswered: answered);
  }

  /// Returns a shuffled sample of [count] unique display names pooled from
  /// both the USA and Foreign name pools — used by the Active Rooms browser.
  static List<String> sampleRoomNames(int count) {
    final pool = [..._usaNames, ..._foreignNames]..shuffle(_rng);
    return pool.take(count).toList();
  }

  /// Return a descriptive status label for the UI based on current activity.
  static String activityLabel() => _activityStatusLabel();
}

// ── Event types for the per-question opponent stream ─────────────────────────
enum _OpponentEventType { thinking, afk, answered, skipped, finished }

class OpponentEvent {
  final _OpponentEventType type;
  final int? questionIndex;
  final int? answeredSoFar;
  final bool? isCorrect;
  final int? afkSeconds;
  final double? actScore;
  final int? totalAnswered;

  const OpponentEvent._({
    required this.type,
    this.questionIndex,
    this.answeredSoFar,
    this.isCorrect,
    this.afkSeconds,
    this.actScore,
    this.totalAnswered,
  });

  factory OpponentEvent.thinking({required int questionIndex}) =>
      OpponentEvent._(type: _OpponentEventType.thinking, questionIndex: questionIndex);

  factory OpponentEvent.afk({required int seconds}) =>
      OpponentEvent._(type: _OpponentEventType.afk, afkSeconds: seconds);

  factory OpponentEvent.answered({
    required int questionIndex,
    required int answeredSoFar,
    required bool isCorrect,
  }) =>
      OpponentEvent._(
        type: _OpponentEventType.answered,
        questionIndex: questionIndex,
        answeredSoFar: answeredSoFar,
        isCorrect: isCorrect,
      );

  factory OpponentEvent.skipped({required int questionIndex, required int answeredSoFar}) =>
      OpponentEvent._(
        type: _OpponentEventType.skipped,
        questionIndex: questionIndex,
        answeredSoFar: answeredSoFar,
      );

  factory OpponentEvent.finished({required double actScore, required int totalAnswered}) =>
      OpponentEvent._(
        type: _OpponentEventType.finished,
        actScore: actScore,
        totalAnswered: totalAnswered,
      );

  bool get isThinking  => type == _OpponentEventType.thinking;
  bool get isAfk       => type == _OpponentEventType.afk;
  bool get isAnswered  => type == _OpponentEventType.answered;
  bool get isSkipped   => type == _OpponentEventType.skipped;
  bool get isFinished  => type == _OpponentEventType.finished;
}

class ChallengeBetProposal {
  final String type;
  final String value;
  final String description;

  const ChallengeBetProposal({
    required this.type,
    required this.value,
    required this.description,
  });
}
