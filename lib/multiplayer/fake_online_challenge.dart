import 'dart:async';
import 'dart:math';
import 'package:http/http.dart' as http;

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

  // ── Name pools ─────────────────────────────────────────────────────────────
  static const _usaNames = [
    "AidanR_ACT", "AlexandraH", "AndrewK_99", "AshleyM_Pro", "AuroraBell",
    "BeatrizV_ACT", "BenjaminF", "BriannaC", "CalebWright", "CarolineS",
    "CharlotteM", "ChristianB", "CooperLane", "DakotaHill", "DanielleP",
    "DerekACT26", "EthanThomas", "EvelynNash", "FinnleyR", "GabrielleH",
    "GraceLinton", "HannahPark", "HarperEllis", "HaydenWolf", "IsabellaC",
    "JacksonB_99", "JadenACT", "JasmineWu", "JuliaFord", "KaileyBrown",
    "KathrynV", "KevinMoore", "LandonS_ACT", "LaurenBach", "LilyOwen",
    "LoganGrant", "LucasACT35", "MadisonHall", "MasonPrice", "MeganACT",
    "MiloFischer", "NatalieCox", "NathanielP", "NoahACT36", "OliviaKing",
    "ParkerReed", "PenelopeW", "QuinnMorris", "RebeccaACT", "RileySTEM",
    "RyanTurner", "SamanthaL", "SarahACT34", "SkylerHunt", "SofiaJames",
    "SpencerACT", "TaylorBritt", "TristanACT", "VioletShaw", "WillowACT",
    "XanderPro", "YasmineStar", "ZacharyR35", "ZoeyACT_Top", "AmeliaFox",
    "BradleyACT", "CassandraW", "DominicACT", "EleanorS_36", "FelixTopACT",
    "GeorgiaACT", "HudsonElite", "IvyTopScore", "JadaACT_Pro", "KendallW",
    "LeahACT_35", "MarcellaT", "NicholasW", "OscarRivera", "PaigeTurner",
    "RolandACT", "ScarlettR36", "SebastianH", "StellaACTTop", "TheodoreW",
    "UrielACT35", "VanessaACT", "WestonElite", "XimenaTop", "YolandaACT",
    "ZephyrACT36", "AbigailACT", "BroderickP", "CeliaACTTop", "DexterACT",
    "EthanF_ACT", "FinnACT_US", "GwendolynS", "HectorR_ACT", "IrinaACT35",
  ];

  static const _foreignNames = [
    "LiamUK_ACT", "EmmaCA_Pro", "OliviaNZ35", "NathanDE_A", "SofiaFR_ACT",
    "LucasAU36", "MeiJP_Top", "PriyaIN_ACT", "RajGlobal35", "AnastasiaRU",
    "YukiJP_Pro", "PierreF_ACT", "HansDE_36", "FreyaNZ_ACT", "CarlosES35",
    "GretaSE_ACT", "SvenNO_Pro", "IsabelCN35", "KenjiJP35", "LaylaUAE_ACT",
    "ValentinaIT", "DiegoMX_ACT", "AnaGR_ACT35", "IvanPL_ACT", "BiancaBR35",
    "MatthewCA35", "OscarDE_ACT", "ChloeAU_Pro", "NicolasF_ACT", "AmeliaUK35",
    "HarrisNZ_36", "SophieIN_ACT", "MarcAU_ACT", "RosaES_Pro", "KlausDE36",
    "AnnaSE_ACT", "MiguelMX35", "LinCN_ACT35", "YuriRU_Pro", "AishaBR35",
    "FerdinandPH", "VictoriaAR", "TakeshiJP35", "BeatriceIT", "ArjunIN35",
    "ZaraUK_ACT", "PhilippeF35", "AkiraJP36", "ElenaRU_Pro", "RuiCN_ACT",
  ];

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
    yield 'joined:${pool[_rng.nextInt(pool.length)]}';
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
    yield 'joined:${pool[_rng.nextInt(pool.length)]}';
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

    return pool[_rng.nextInt(pool.length)];
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
    return pool[_rng.nextInt(pool.length)];
  }

  // ── Bet proposals ──────────────────────────────────────────────────────────
  static ChallengeBetProposal? fakeOpponentBetProposal() {
    // 55% chance at high activity, 30% late night (distracted opponents don't bother)
    final activity = _activityFactor();
    final proposalChance = 0.30 + activity * 0.25;
    if (_rng.nextDouble() > proposalChance) return null;

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
