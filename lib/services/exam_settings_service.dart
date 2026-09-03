import 'package:shared_preferences/shared_preferences.dart';

/// Manages all exam mode settings — persisted via SharedPreferences.
/// Settings are accessible from Settings screen and from the Exam setup dialog.
class ExamSettingsService {
  static const _keyEnglishMinutes  = 'exam_english_minutes';
  static const _keyMathMinutes     = 'exam_math_minutes';
  static const _keyReadingMinutes  = 'exam_reading_minutes';
  static const _keyScienceMinutes  = 'exam_science_minutes';
  static const _keyIncludeEnglish  = 'exam_include_english';
  static const _keyIncludeMath     = 'exam_include_math';
  static const _keyIncludeReading  = 'exam_include_reading';
  static const _keyIncludeScience  = 'exam_include_science';
  static const _keyShowCalculator  = 'exam_show_calculator';
  static const _keyAutoSave        = 'exam_auto_save';
  static const _keyAnswerReveal    = 'exam_answer_reveal'; // 'immediate' | 'end'
  static const _keyProfileSetup   = 'exam_profile_setup_done';
  static const _keyStudentName    = 'exam_student_name';
  static const _keyTargetScore    = 'exam_target_score';
  // answerReveal: 'immediate' = show after each question (practice), 'end' = only at results (real ACT)

  // Real ACT defaults (minutes) — matches official ACT timing exactly
  // English: 75 q / 45 min = 36 sec/q  |  Math: 60 q / 60 min = 60 sec/q
  // Reading: 40 q / 35 min = 52 sec/q  |  Science: 40 q / 35 min = 52 sec/q
  static const int defaultEnglishMinutes  = 45;
  static const int defaultMathMinutes     = 60;
  static const int defaultReadingMinutes  = 35;
  static const int defaultScienceMinutes  = 35;

  static Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  // ── Time limits ────────────────────────────────────────────────────────────

  static Future<int> getEnglishMinutes() async =>
      (await _prefs).getInt(_keyEnglishMinutes) ?? defaultEnglishMinutes;

  static Future<int> getMathMinutes() async =>
      (await _prefs).getInt(_keyMathMinutes) ?? defaultMathMinutes;

  static Future<int> getReadingMinutes() async =>
      (await _prefs).getInt(_keyReadingMinutes) ?? defaultReadingMinutes;

  static Future<int> getScienceMinutes() async =>
      (await _prefs).getInt(_keyScienceMinutes) ?? defaultScienceMinutes;

  static Future<void> setEnglishMinutes(int v) async =>
      (await _prefs).setInt(_keyEnglishMinutes, v.clamp(10, 90));

  static Future<void> setMathMinutes(int v) async =>
      (await _prefs).setInt(_keyMathMinutes, v.clamp(10, 120));

  static Future<void> setReadingMinutes(int v) async =>
      (await _prefs).setInt(_keyReadingMinutes, v.clamp(10, 90));

  static Future<void> setScienceMinutes(int v) async =>
      (await _prefs).setInt(_keyScienceMinutes, v.clamp(10, 90));

  static Future<void> resetTimesToDefault() async {
    final p = await _prefs;
    p.setInt(_keyEnglishMinutes, defaultEnglishMinutes);
    p.setInt(_keyMathMinutes, defaultMathMinutes);
    p.setInt(_keyReadingMinutes, defaultReadingMinutes);
    p.setInt(_keyScienceMinutes, defaultScienceMinutes);
  }

  // ── Section inclusion ──────────────────────────────────────────────────────

  static Future<bool> getIncludeEnglish() async =>
      (await _prefs).getBool(_keyIncludeEnglish) ?? true;
  static Future<bool> getIncludeMath() async =>
      (await _prefs).getBool(_keyIncludeMath) ?? true;
  static Future<bool> getIncludeReading() async =>
      (await _prefs).getBool(_keyIncludeReading) ?? true;
  static Future<bool> getIncludeScience() async =>
      (await _prefs).getBool(_keyIncludeScience) ?? true;

  static Future<void> setIncludeEnglish(bool v) async =>
      (await _prefs).setBool(_keyIncludeEnglish, v);
  static Future<void> setIncludeMath(bool v) async =>
      (await _prefs).setBool(_keyIncludeMath, v);
  static Future<void> setIncludeReading(bool v) async =>
      (await _prefs).setBool(_keyIncludeReading, v);
  static Future<void> setIncludeScience(bool v) async =>
      (await _prefs).setBool(_keyIncludeScience, v);

  // ── Features ───────────────────────────────────────────────────────────────

  static Future<bool> getShowCalculator() async =>
      (await _prefs).getBool(_keyShowCalculator) ?? true;
  static Future<void> setShowCalculator(bool v) async =>
      (await _prefs).setBool(_keyShowCalculator, v);

  static Future<bool> getAutoSave() async =>
      (await _prefs).getBool(_keyAutoSave) ?? true;
  /// 'immediate' = show correct answer after each question
  /// 'end'       = show all answers only at the results screen (real ACT behaviour)
  static Future<String> getAnswerReveal() async =>
      (await _prefs).getString(_keyAnswerReveal) ?? 'immediate';
  static Future<void> setAnswerReveal(String v) async =>
      (await _prefs).setString(_keyAnswerReveal, v == 'end' ? 'end' : 'immediate');

  static Future<void> setAutoSave(bool v) async =>
      (await _prefs).setBool(_keyAutoSave, v);

  // ── Profile ────────────────────────────────────────────────────────────────

  static Future<bool> isProfileSetupDone() async =>
      (await _prefs).getBool(_keyProfileSetup) ?? false;
  static Future<void> markProfileSetupDone() async =>
      (await _prefs).setBool(_keyProfileSetup, true);

  static Future<String?> getStudentName() async =>
      (await _prefs).getString(_keyStudentName);
  static Future<void> setStudentName(String v) async =>
      (await _prefs).setString(_keyStudentName, v.trim());

  static Future<int> getTargetScore() async =>
      (await _prefs).getInt(_keyTargetScore) ?? 28;
  static Future<void> setTargetScore(int v) async =>
      (await _prefs).setInt(_keyTargetScore, v.clamp(1, 36));

  // ── Load all settings at once ──────────────────────────────────────────────

  static Future<ExamSettings> loadAll() async {
    return ExamSettings(
      englishMinutes: await getEnglishMinutes(),
      mathMinutes: await getMathMinutes(),
      readingMinutes: await getReadingMinutes(),
      scienceMinutes: await getScienceMinutes(),
      includeEnglish: await getIncludeEnglish(),
      includeMath: await getIncludeMath(),
      includeReading: await getIncludeReading(),
      includeScience: await getIncludeScience(),
      showCalculator: await getShowCalculator(),
      answerReveal: await getAnswerReveal(),
      autoSave: await getAutoSave(),
      studentName: await getStudentName(),
      targetScore: await getTargetScore(),
    );
  }

  static Future<void> saveAll(ExamSettings s) async {
    await setEnglishMinutes(s.englishMinutes);
    await setMathMinutes(s.mathMinutes);
    await setReadingMinutes(s.readingMinutes);
    await setScienceMinutes(s.scienceMinutes);
    await setIncludeEnglish(s.includeEnglish);
    await setIncludeMath(s.includeMath);
    await setIncludeReading(s.includeReading);
    await setIncludeScience(s.includeScience);
    await setShowCalculator(s.showCalculator);
    await setAutoSave(s.autoSave);
    if (s.studentName != null) await setStudentName(s.studentName!);
    await setTargetScore(s.targetScore);
  }
}

/// Snapshot of all exam settings.
class ExamSettings {
  final int englishMinutes;
  final int mathMinutes;
  final int readingMinutes;
  final int scienceMinutes;
  final bool includeEnglish;
  final bool includeMath;
  final bool includeReading;
  final bool includeScience;
  final bool showCalculator;
  final String answerReveal; // 'immediate' | 'end'
  final bool autoSave;
  final String? studentName;
  final int targetScore;

  const ExamSettings({
    required this.englishMinutes,
    required this.mathMinutes,
    required this.readingMinutes,
    required this.scienceMinutes,
    required this.includeEnglish,
    required this.includeMath,
    required this.includeReading,
    required this.includeScience,
    required this.showCalculator,
    required this.answerReveal,
    required this.autoSave,
    required this.studentName,
    required this.targetScore,
  });

  int get totalMinutes =>
      (includeEnglish ? englishMinutes : 0) +
      (includeMath ? mathMinutes : 0) +
      (includeReading ? readingMinutes : 0) +
      (includeScience ? scienceMinutes : 0);

  ExamSettings copyWith({
    int? englishMinutes,
    int? mathMinutes,
    int? readingMinutes,
    int? scienceMinutes,
    bool? includeEnglish,
    bool? includeMath,
    bool? includeReading,
    bool? includeScience,
    bool? showCalculator,
    String? answerReveal,
    bool? autoSave,
    String? studentName,
    int? targetScore,
  }) => ExamSettings(
    englishMinutes: englishMinutes ?? this.englishMinutes,
    mathMinutes: mathMinutes ?? this.mathMinutes,
    readingMinutes: readingMinutes ?? this.readingMinutes,
    scienceMinutes: scienceMinutes ?? this.scienceMinutes,
    includeEnglish: includeEnglish ?? this.includeEnglish,
    includeMath: includeMath ?? this.includeMath,
    includeReading: includeReading ?? this.includeReading,
    includeScience: includeScience ?? this.includeScience,
    showCalculator: showCalculator ?? this.showCalculator,
    answerReveal: answerReveal ?? this.answerReveal,
    autoSave: autoSave ?? this.autoSave,
    studentName: studentName ?? this.studentName,
    targetScore: targetScore ?? this.targetScore,
  );
}
