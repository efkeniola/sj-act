import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:flutter/services.dart' show rootBundle;

import '../models/models.dart';

/// ───────────────────────────────────────────────────────────────────────
/// Single source of truth for every ACT question bank set: ACT 1–ACT 100,
/// 215 questions each (English 75 / Math 60 / Reading 40 / Science 40 =
/// 215), 21,500 questions in total.
///
/// All of it lives in ONE bundled data file — assets/data/act_question_bank
/// .b64.txt — instead of the 100 separate source files it was generated
/// from, and instead of being hand-written here as Dart const literals.
/// The file is plain-text base64 of gzip-compressed JSON (not a raw binary
/// .gz): some web-based build/upload pipelines mangle binary files in
/// transit, while plain ASCII text survives untouched.
///
/// LAZY PER-SET LOADING — this is what keeps startup fast even with 100
/// sets bundled: the outer JSON doesn't nest each set's 215 questions as
/// real objects. Each set's data is stored as its own already-encoded JSON
/// *string* (see convert step), so the one-time startup parse only has to
/// tokenize 100 short string values — it never builds a single ActQuestion.
/// A specific set's ~215 questions are only decoded and built the first
/// time that set is actually opened (forSet), then cached. So opening the
/// app costs "read the index," not "parse and build all 21,500 questions
/// up front" — the thing that made the original eager-build design take
/// several seconds (or worse on constrained web/JS runtimes, where
/// `compute`'s background isolate has to message the ENTIRE built object
/// graph back to the UI isolate — expensive for 21,500 objects, cheap for
/// 100 strings).
///
/// QuestionBank.ensureLoaded() is called once, at startup, from
/// splash_screen.dart — it only does the lightweight index parse. Every
/// existing call site (questionsForSection, questionsForRandomMix) keeps
/// the exact same signature it always had, so nothing else in the app
/// needs to change to keep working.
/// ───────────────────────────────────────────────────────────────────────

class QuestionBank {
  QuestionBank._();

  static const String assetPath = 'assets/data/act_question_bank.b64.txt';

  // The lightweight index: each set's still-encoded JSON string, keyed by
  // set number. Populated once by ensureLoaded(). Cheap to hold in memory
  // (it's just text) even for all 100 sets.
  static Map<int, String> _rawSetJson = {};
  static List<int> _availableSetNumbers = const [];
  static bool _loaded = false;
  static Future<void>? _loadingFuture;

  // Per-set BUILT question cache — populated lazily, the first time each
  // set's questions are actually needed, and kept afterward so re-opening
  // the same set is instant.
  static final Map<int, Map<ActSection, List<ActQuestion>>> _builtSets = {};

  /// True once the index has finished loading (or failed and given up —
  /// either way, callers can stop showing a loading spinner).
  static bool get isLoaded => _loaded;

  /// Set when [_load] fails, so the picker/exam screens can show *why*
  /// instead of a bare empty state. Null when loading succeeded (or
  /// hasn't been attempted yet).
  static String? loadError;

  /// Call once at app startup. Safe to call more than once or from more
  /// than one place — later calls just await the same load.
  static Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loadingFuture ??= _load();
  }

  static Future<void> _load() async {
    try {
      // Load as text (rootBundle.loadString), not bytes — this asset is
      // plain base64 ASCII specifically so the read-and-bundle path never
      // touches it as binary data. The base64 decode, gunzip, UTF-8
      // decode, and JSON parse of the OUTER structure happen inside
      // `compute`'s background isolate; because that outer parse only
      // produces 100 short strings (not 21,500 built objects), the result
      // is cheap to send back across the isolate boundary too.
      final String base64Text = await rootBundle.loadString(assetPath);
      final parsed = await compute(_parseIndex, base64Text);
      _rawSetJson = parsed.rawSetJson;
      _availableSetNumbers = parsed.setNumbers;
      loadError = null;
      debugPrint('QuestionBank: index ready for ${_availableSetNumbers.length} '
          'sets (each set\'s questions build on first open).');
    } catch (e, st) {
      // Don't crash app startup over a bad asset — but DO surface exactly
      // what went wrong (asset missing from the bundle because pubspec
      // wasn't picked up, corrupt base64/gzip, malformed JSON, etc).
      // Silently leaving this empty is what makes "no questions available"
      // so confusing to debug from the UI alone — this print is what
      // you'd look for in `flutter run`'s console output.
      debugPrint('QuestionBank FAILED TO LOAD: $e');
      debugPrint('$st');
      _rawSetJson = {};
      _availableSetNumbers = const [];
      loadError = e.toString();
    } finally {
      _loaded = true;
    }
  }

  /// Returns the built questions for [setNumber], building and caching
  /// them from that set's raw JSON the first time it's asked for. This
  /// runs synchronously, directly on the calling isolate: parsing ~215
  /// questions' worth of JSON takes low single-digit milliseconds, so
  /// there's no need to hop to a background isolate for it the way the
  /// (much bigger) startup index load does.
  static Map<ActSection, List<ActQuestion>>? forSet(int setNumber) {
    final cached = _builtSets[setNumber];
    if (cached != null) return cached;

    final raw = _rawSetJson[setNumber];
    if (raw == null) return null;

    final built = _buildSetFromRawJson(setNumber, raw);
    _builtSets[setNumber] = built;
    return built;
  }

  /// Set numbers available in the app, in display order (1, 2, 3 ... 100).
  static List<int> get availableSetNumbers => _availableSetNumbers;
}

class _ParsedIndex {
  final Map<int, String> rawSetJson;
  final List<int> setNumbers;
  _ParsedIndex(this.rawSetJson, this.setNumbers);
}

/// Runs on a background isolate via `compute` — must be a top-level (or
/// static) function. Only decodes the OUTER structure (base64 → gunzip →
/// UTF-8 → JSON), which is just an index of 100 raw JSON strings — it
/// deliberately does NOT parse any individual set's questions, so this
/// stays fast regardless of how many sets are bundled.
_ParsedIndex _parseIndex(String base64Text) {
  final Uint8List gzippedBytes = base64.decode(base64Text.trim());
  // Pure-Dart gzip decode (package:archive) instead of dart:io's gzip —
  // works on every compile target, including web/JS, where dart:io's
  // native-zlib-backed decoder throws
  // "Unsupported operation: _newZLibInflateFilter".
  final List<int> jsonBytes = GZipDecoder().decodeBytes(gzippedBytes);
  final String raw = utf8.decode(jsonBytes);
  final Map<String, dynamic> decoded = json.decode(raw) as Map<String, dynamic>;

  final List<dynamic> setNumbersJson = decoded['setNumbers'] as List<dynamic>;
  final List<dynamic> setsRawJson = decoded['setsRaw'] as List<dynamic>;

  final Map<int, String> rawMap = {};
  for (var i = 0; i < setNumbersJson.length; i++) {
    rawMap[setNumbersJson[i] as int] = setsRawJson[i] as String;
  }

  final setNumbers = rawMap.keys.toList()..sort();
  return _ParsedIndex(rawMap, setNumbers);
}

/// Parses ONE set's raw JSON string into its built questions, grouped by
/// section. Only ever does 215 questions' worth of work, never all 100
/// sets' worth — that's the whole point of the lazy design above.
Map<ActSection, List<ActQuestion>> _buildSetFromRawJson(int setNumber, String raw) {
  final Map<String, dynamic> setMap = json.decode(raw) as Map<String, dynamic>;
  final List<dynamic> questionsJson = setMap['questions'] as List<dynamic>;

  final Map<ActSection, List<ActQuestion>> bySection = {
    ActSection.english: <ActQuestion>[],
    ActSection.math: <ActQuestion>[],
    ActSection.reading: <ActQuestion>[],
    ActSection.science: <ActQuestion>[],
  };

  for (final q in questionsJson) {
    final m = q as Map<String, dynamic>;
    final section = actSectionFromString(m['section'] as String);
    bySection[section]!.add(ActQuestion(
      id: m['id'] as String,
      setNumber: setNumber,
      section: section,
      skillArea: (m['skillArea'] as String?) ?? '',
      difficulty: difficultyFromString((m['difficulty'] as String?) ?? 'medium'),
      questionText: m['questionText'] as String,
      passageText: m['passageText'] as String?,
      options: List<String>.from(m['options'] as List),
      correctAnswer: m['correctAnswer'] as String,
      explanation: (m['explanation'] as String?) ?? '',
    ));
  }

  return bySection;
}

/// Set numbers available in the app, in display order (ACT 1..ACT 100).
/// Empty until QuestionBank.ensureLoaded() has completed.
List<int> get availableSetNumbers => QuestionBank.availableSetNumbers;

/// Get questions for a section, for a specific set (defaults to Set 1).
/// Returns an empty list if the bank hasn't finished loading yet, or the
/// set/section doesn't exist — every call site already handles an empty
/// list gracefully (e.g. exam_mode_screen skips sections with 0 questions).
List<ActQuestion> questionsForSection(ActSection section, {int setNumber = 1}) {
  return QuestionBank.forSet(setNumber)?[section] ?? const [];
}

/// Every question from every section pooled together for a given set —
/// used by the "Random Mix" subject option (Online Challenge & WiFi
/// Challenge) so a session can pull questions across subjects instead of
/// just one.
List<ActQuestion> questionsForRandomMix({int setNumber = 1}) {
  final set = QuestionBank.forSet(setNumber);
  if (set == null) return const [];
  return [
    ...?set[ActSection.english],
    ...?set[ActSection.math],
    ...?set[ActSection.reading],
    ...?set[ActSection.science],
  ];
}

/// ───────────────────────────────────────────────────────────────────────
/// Full Practice Exam randomization — a fresh shuffle every time someone
/// starts an exam, so question 1 this attempt might be question 23 next
/// time, and each question's A/B/C/D order is reshuffled too. The
/// underlying question bank itself is never touched (this always
/// operates on a COPY); only the list handed to that one exam session is
/// reordered.
/// ───────────────────────────────────────────────────────────────────────

const List<String> _optionLetters = ['A', 'B', 'C', 'D'];

/// Returns a new list with the same questions, in randomized order,
/// EXCEPT that a Reading/Science passage's own questions stay together
/// and in their original relative order — only which passage comes first
/// gets shuffled. Without this, a fully random shuffle could interleave
/// two different passages question-by-question, which would mean
/// constantly flipping between unrelated passages, since ACT reading/
/// science questions are written to be answered in sequence against "the
/// passage above." English/Math questions have no shared passage, so
/// each ends up as its own single-question block and shuffles freely.
List<ActQuestion> _shuffleQuestionOrder(List<ActQuestion> questions, Random rng) {
  final blocks = <List<ActQuestion>>[];
  String? currentPassage;
  List<ActQuestion>? currentBlock;

  for (final q in questions) {
    final samePassageAsPrevious =
        q.passageText != null && currentBlock != null && q.passageText == currentPassage;
    if (samePassageAsPrevious) {
      currentBlock!.add(q);
    } else {
      currentBlock = [q];
      blocks.add(currentBlock);
      currentPassage = q.passageText;
    }
  }

  blocks.shuffle(rng);
  return [for (final block in blocks) ...block];
}

/// Returns a new [ActQuestion] with its options in a random order and
/// [ActQuestion.correctAnswer] recalculated to match the new positions —
/// grading (which just compares the chosen letter to correctAnswer) keeps
/// working exactly as before, with no separate "which option is right"
/// bookkeeping needed anywhere else in the app.
ActQuestion _shuffleOptions(ActQuestion q, Random rng) {
  final correctIndex = _optionLetters.indexOf(q.correctAnswer);
  final order = List<int>.generate(q.options.length, (i) => i)..shuffle(rng);
  final newOptions = [for (final i in order) q.options[i]];
  final newCorrectIndex = order.indexOf(correctIndex);
  return ActQuestion(
    id: q.id,
    setNumber: q.setNumber,
    section: q.section,
    skillArea: q.skillArea,
    difficulty: q.difficulty,
    questionText: q.questionText,
    passageText: q.passageText,
    options: newOptions,
    correctAnswer: _optionLetters[newCorrectIndex],
    explanation: q.explanation,
    topicTip: q.topicTip,
  );
}

/// Call this once per exam attempt, right after fetching a section's
/// questions and before handing them to the exam session — shuffles
/// question order (passage-aware, see [_shuffleQuestionOrder]) and each
/// question's option order, both freshly randomized on every call.
List<ActQuestion> randomizeForExamAttempt(List<ActQuestion> questions, [Random? rng]) {
  final r = rng ?? Random();
  final reordered = _shuffleQuestionOrder(questions, r);
  return [for (final q in reordered) _shuffleOptions(q, r)];
}
