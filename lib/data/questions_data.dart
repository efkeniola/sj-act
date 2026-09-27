import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:flutter/services.dart' show rootBundle;

import '../models/models.dart';

/// ───────────────────────────────────────────────────────────────────────
/// Single source of truth for every ACT question bank set: ACT 1–ACT 100,
/// 215 questions each (English 75 / Math 60 / Reading 40 / Science 40 =
/// 215), 21,500 questions in total.
///
/// All of it lives in ONE bundled data file — assets/data/act_question_bank
/// .json.gz — instead of the 100 separate source files it was generated
/// from, and instead of being hand-written here as Dart const literals. A
/// 100-set const literal would be tens of megabytes of Dart source, which
/// is not something the analyzer/compiler handles gracefully; loading one
/// JSON asset at startup is the version of "everything in one file" that
/// actually keeps the app fast to build and run. It's gzip-compressed
/// (JSON text compresses ~9x) so it stays well under GitHub's 25MB
/// web-upload limit and shrinks the app's own footprint, and it's
/// decompressed on the same background isolate that parses it, so that
/// costs the UI thread nothing either.
///
/// QuestionBank.ensureLoaded() is called once, at startup, from
/// splash_screen.dart, before the person can reach any screen that needs
/// question data. The heavy JSON decode + object-building work happens on
/// a background isolate (via `compute`) so it never blocks the UI thread.
/// Every existing call site (questionsForSection, questionsForRandomMix)
/// keeps the exact same signature it always had, so nothing else in the
/// app needs to change to keep working.
/// ───────────────────────────────────────────────────────────────────────

class QuestionBank {
  QuestionBank._();

  static const String assetPath = 'assets/data/act_question_bank.json.gz';

  static Map<int, Map<ActSection, List<ActQuestion>>> _sets = {};
  static List<int> _availableSetNumbers = const [];
  static bool _loaded = false;
  static Future<void>? _loadingFuture;

  /// True once the bank has finished loading (or failed and given up —
  /// either way, callers can stop showing a loading spinner).
  static bool get isLoaded => _loaded;

  /// Call once at app startup. Safe to call more than once or from more
  /// than one place — later calls just await the same load.
  static Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loadingFuture ??= _load();
  }

  /// Set when [_load] fails, so the picker/exam screens can show *why*
  /// instead of a bare empty state. Null when loading succeeded (or
  /// hasn't been attempted yet).
  static String? loadError;

  static Future<void> _load() async {
    try {
      // Only the raw byte read happens on the UI isolate (fast disk I/O,
      // no CPU work). Gunzipping, the UTF-8 decode, JSON parse, and
      // object building — the actually expensive parts — all happen
      // inside `compute`'s background isolate instead, so the UI thread
      // never has a reason to stutter while this loads.
      final ByteData byteData = await rootBundle.load(assetPath);
      final Uint8List bytes = byteData.buffer.asUint8List(
          byteData.offsetInBytes, byteData.lengthInBytes);
      final parsed = await compute(_parseQuestionBank, bytes);
      _sets = parsed.sets;
      _availableSetNumbers = parsed.setNumbers;
      loadError = null;
      debugPrint('QuestionBank: loaded ${_sets.length} sets '
          '(${_sets.values.fold<int>(0, (t, s) => t + s.values.fold<int>(0, (t2, l) => t2 + l.length))} questions).');
    } catch (e, st) {
      // Don't crash app startup over a bad asset — but DO surface exactly
      // what went wrong (asset missing from the bundle because pubspec
      // wasn't picked up, corrupt gzip, malformed JSON, etc). Silently
      // leaving this empty is what makes "no questions available" so
      // confusing to debug from the UI alone — this print is what you'd
      // look for in `flutter run`'s console output.
      debugPrint('QuestionBank FAILED TO LOAD: $e');
      debugPrint('$st');
      _sets = {};
      _availableSetNumbers = const [];
      loadError = e.toString();
    } finally {
      _loaded = true;
    }
  }

  static Map<ActSection, List<ActQuestion>>? forSet(int setNumber) => _sets[setNumber];

  /// Set numbers available in the app, in display order (1, 2, 3 ... 100).
  static List<int> get availableSetNumbers => _availableSetNumbers;
}

class _ParsedBank {
  final Map<int, Map<ActSection, List<ActQuestion>>> sets;
  final List<int> setNumbers;
  _ParsedBank(this.sets, this.setNumbers);
}

/// Runs on a background isolate via `compute` — must be a top-level (or
/// static) function, and everything it returns must be safe to send
/// across the isolate boundary (plain data classes and enums are fine).
/// Takes the raw gzip-compressed bytes (not decoded text) so gunzipping,
/// UTF-8 decoding, and JSON parsing all run here, off the UI thread.
_ParsedBank _parseQuestionBank(Uint8List gzippedBytes) {
  final List<int> jsonBytes = gzip.decode(gzippedBytes);
  final String raw = utf8.decode(jsonBytes);
  final Map<String, dynamic> decoded = json.decode(raw) as Map<String, dynamic>;
  final List<dynamic> setsJson = decoded['sets'] as List<dynamic>;

  final Map<int, Map<ActSection, List<ActQuestion>>> built = {};

  for (final entry in setsJson) {
    final setMap = entry as Map<String, dynamic>;
    final int setNumber = setMap['setNumber'] as int;
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

    built[setNumber] = bySection;
  }

  final setNumbers = built.keys.toList()..sort();
  return _ParsedBank(built, setNumbers);
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
