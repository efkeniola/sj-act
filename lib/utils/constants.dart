// Global constants for SJ ACT
class AppConstants {
  static const String appName = "SJ ACT";
  static const String orgName = "SmartJAMB";

  // ── API ─────────────────────────────────────────────
  static const String baseApiUrl = "https://smartjamb.com/act/api";
  static const String apiKeyHeader = "X-SmartJAMB-Act-Key";

  // Build-time injectable key — must match SJACT_API_KEY in Django settings.
  //   flutter build apk --dart-define=ACT_API_KEY=your_key_here
  static const String apiKeyValue = String.fromEnvironment(
    'ACT_API_KEY',
    defaultValue: 'SJACT-2026-98NS6GBERNGJIZT9GHYMX65OKUSZT0BH',
  );
  static const Duration apiTimeout = Duration(seconds: 12);
  static const Duration storageTimeout = Duration(seconds: 6);

  // ── Activation code prefixes ─────────────────────────
  // Standard           → SJACTS-YYXXXX-XXXX-XX
  // Online Challenge   → SJACT-ONLINE-YYXXXX-XXXX-XX
  // WiFi Challenge     → SJACT-WIFI-YYXXXX-XXXX-XX
  // All Access         → SJACT-ALL-YYXXXX-XXXX-XX
  static const String codePrefixStandard = "SJACTS";
  static const String codePrefixOnline   = "SJACT-ONLINE";
  static const String codePrefixWifi     = "SJACT-WIFI";
  static const String codePrefixAll      = "SJACT-ALL";

  // Code detection is intentionally minimal: the only thing the app checks
  // client-side is that the code starts with "SJACT" — everything else
  // about whether it's a real, unused, valid code is decided by the
  // activation server. This used to also validate the exact SJACTS-/
  // SJACT-ONLINE-/SJACT-WIFI-/SJACT-ALL- structure (digits/letter counts,
  // dash placement), but that extra client-side "detection" has been
  // removed on purpose — the server is the single source of truth.
  static final RegExp codePattern = RegExp(r'^SJACT', caseSensitive: false);

  // ── Categories ───────────────────────────────────────
  static const String catStandard = "standard";
  static const String catOnlineChallenge = "online_challenge";
  static const String catWifiChallenge = "wifi_challenge";

  static const int standardGraceDays = 15;
  static const int challengeGraceDays = 7;

  // ── TEMPORARY testing override ───────────────────────
  // While this is true, WiFi Challenge and Online Challenge are unlocked for
  // everyone regardless of activation status, so they can be tested without
  // needing an activation code yet. Standard activation is NOT affected.
  // Set this back to `false` once testing is done to re-lock them.
  static const bool tempUnlockWifiAndOnlineChallenge = false;

  // Same idea, just for the Leaderboard screen — unlocked for testing
  // regardless of Standard activation. Set back to `false` to re-lock it
  // behind Standard activation once testing is done.
  static const bool tempUnlockLeaderboard = false;

  // ── Store / Support ──────────────────────────────────
  static const String codeStoreUrl = "https://smartjamb.com/act-app/";
  static const String supportEmail = "smartjamb8505@gmail.com";

  // ── ACT Structure ────────────────────────────────────
  // Real ACT format:
  //   English:    75 questions, 45 minutes
  //   Math:       60 questions, 60 minutes
  //   Reading:    40 questions, 35 minutes
  //   Science:    40 questions, 35 minutes
  //   (Optional Writing: 1 essay, 40 minutes)
  static const int englishQuestionCount = 75;
  static const int mathQuestionCount    = 60;
  static const int readingQuestionCount = 40;
  static const int scienceQuestionCount = 40;
  static const int fullTestTotal        = 215; // all 4 sections

  static const int englishMinutes = 45;
  static const int mathMinutes    = 60;
  static const int readingMinutes = 35;
  static const int scienceMinutes = 35;

  // ACT score range: 1-36 per section, composite is average
  static const int actMinScore = 1;
  static const int actMaxScore = 36;

  // ── ACT Section Names ────────────────────────────────
  static const String secEnglish = "English";
  static const String secMath    = "Mathematics";
  static const String secReading = "Reading";
  static const String secScience = "Science";

  // ── English skill areas ──────────────────────────────
  static const List<String> englishSkills = [
    "Production of Writing",
    "Knowledge of Language",
    "Conventions of Standard English",
  ];

  // ── Math skill areas ─────────────────────────────────
  static const List<String> mathSkills = [
    "Preparing for Higher Math",
    "Integrating Essential Skills",
    "Modeling",
  ];

  static const List<String> mathSubSkills = [
    "Number and Quantity",
    "Algebra",
    "Functions",
    "Geometry",
    "Statistics and Probability",
  ];

  // ── Reading skill areas ──────────────────────────────
  static const List<String> readingSkills = [
    "Key Ideas and Details",
    "Craft and Structure",
    "Integration of Knowledge and Ideas",
  ];

  // ── Science skill areas ──────────────────────────────
  static const List<String> scienceSkills = [
    "Interpretation of Data",
    "Scientific Investigation",
    "Evaluation of Models, Inferences, and Experimental Results",
  ];

  // ── Leaderboard ──────────────────────────────────────
  static const int lbUpdateIntervalMinutes = 5;
  static const int lbGroupSize = 100;

  // ── WiFi Challenge ───────────────────────────────────
  static const String wifiServiceType = "_sjact._tcp";

  // ── Free tier ────────────────────────────────────────
  static const int freeDailyQuestionCap = 20;
  static const int freeOnlineChallengesPerDay = 1;

  // ── In-app purchase (Google Play Billing) ────────────
  // Product ids MUST exactly match what's created in Play Console
  // (Monetize -> Subscriptions) and what act/play_plans.py expects.
  // "full" (lifetime WiFi Challenge, $40) is deliberately NOT sold via
  // Play — it stays website/Flutterwave-only (see that file's docstring).
  //
  // Prices here are base price + 7.5% platform fee, rounded up to the
  // nearest .99 — must match Play Console exactly. This local copy is
  // only the offline-safe fallback; PlayCatalogService prefers the live
  // /payments/play-catalog/ value whenever it can reach the server.
  static const Map<String, Map<String, double>> playPriceUsd = {
    catStandard: {'3m': 13.99, '6m': 26.99, '1y': 48.99},
    catOnlineChallenge: {'3m': 6.99, '6m': 11.99, '1y': 23.99},
    catWifiChallenge: {'3m': 7.99, '6m': 13.99, '1y': 26.99},
  };

  static const Map<String, List<String>> catPlayDurations = {
    catStandard: ['3m', '6m', '1y'],
    catOnlineChallenge: ['3m', '6m', '1y'],
    catWifiChallenge: ['3m', '6m', '1y'],
  };

  static const Map<String, String> durationLabels = {
    '3m': '3 Months',
    '6m': '6 Months',
    '1y': '1 Year',
  };

  static const Map<String, String> categoryLabels = {
    catStandard: 'Standard',
    catOnlineChallenge: 'Online Challenge',
    catWifiChallenge: 'WiFi Challenge',
  };

  static const Map<String, List<String>> categoryFeatures = {
    catStandard: [
      'Full ACT question bank across English, Math, Reading, and Science',
      'Score prediction, full syllabus, timetable, and progress analytics',
      'Built-in graphing calculator for the Math section',
      'Includes 1 free daily Online Challenge match and 2 free daily WiFi Challenge matches',
    ],
    catOnlineChallenge: [
      'Unlimited matches against a simulated opponent — no daily cap',
      'USA Room and Foreign Room, with optional bets on the outcome',
    ],
    catWifiChallenge: [
      'Real-time 1v1 battles with a friend over WiFi — no daily limit',
      'In-match chat, bet proposals, and real leaderboard ranking impact',
    ],
  };

  /// 'act_wifi_6m', 'act_standard_1y', etc. — must match
  /// act/play_plans.py product_id_for() exactly.
  static String playProductId(String category, String duration) {
    final slug = category == catWifiChallenge
        ? 'wifi'
        : category == catOnlineChallenge
            ? 'online'
            : 'standard';
    return 'act_${slug}_$duration';
  }

  static const double platformFeeRate = 0.075;
}
