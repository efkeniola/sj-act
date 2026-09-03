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

  static final RegExp codePattern = RegExp(
    r'^(SJACTS|SJACT-ONLINE|SJACT-WIFI|SJACT-ALL)-\d{2}[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{2}$',
  );

  // ── Categories ───────────────────────────────────────
  static const String catStandard = "standard";
  static const String catOnlineChallenge = "online_challenge";
  static const String catWifiChallenge = "wifi_challenge";

  static const int standardGraceDays = 15;
  static const int challengeGraceDays = 7;

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
}
