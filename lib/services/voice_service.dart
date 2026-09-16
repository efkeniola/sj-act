import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Voice reading (text-to-speech) for ACT questions.
///
/// NOTE: Speech-to-text "answer by voice" (mic input for A/B/C/D) has been
/// removed app-wide — it was unreliable across devices and is no longer
/// exposed anywhere in the UI (Settings, Full Practice Exam, Practice
/// Sections, etc.). This service now only handles reading questions aloud.
class VoiceService {
  static final VoiceService instance = VoiceService._();
  VoiceService._();

  final FlutterTts _tts = FlutterTts();

  bool _ttsReady = false;
  bool _isReading = false;

  static const _prefKey = 'sj_act_voice_enabled';

  // ── Init ──────────────────────────────────────────────────────────────────
  Future<void> init() async {
    await _initTts();
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.48);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      _ttsReady = true;
    } catch (_) { _ttsReady = false; }
  }

  // ── Prefs ─────────────────────────────────────────────────────────────────
  Future<bool> isTtsEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_prefKey) ?? false;
  }
  Future<void> setTtsEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_prefKey, v);
    if (!v) stopReading();
  }

  bool get ttsReady => _ttsReady;

  // ── TTS ───────────────────────────────────────────────────────────────────
  Future<void> readQuestion({required String questionText, required List<String> options}) async {
    if (!_ttsReady) return;
    // Always cut off whatever is currently being (or queued to be) spoken
    // first. flutter_tts queues utterances by default, so without this a
    // question read while a previous question/answer is still talking would
    // just get queued up behind it instead of starting immediately — this is
    // what made it seem like the voice "didn't detect" that a new question
    // had loaded.
    await _stopAndSettle();
    _isReading = true;
    final letters = ['A', 'B', 'C', 'D'];
    final buffer = StringBuffer();
    buffer.writeln(questionText);
    for (int i = 0; i < options.length && i < 4; i++) {
      buffer.writeln('${letters[i]}. ${options[i]}');
    }
    await _tts.speak(buffer.toString());
  }

  Future<void> readText(String text) async {
    if (!_ttsReady) return;
    // Same reasoning as above: stop anything still playing (e.g. the
    // question being read) before speaking the correct/incorrect feedback,
    // so the feedback is always heard immediately instead of after a delay.
    await _stopAndSettle();
    await _tts.speak(text);
  }

  /// Stops any in-progress speech and gives the native TTS engine a brief
  /// moment to actually finish cancelling before the next speak() call goes
  /// out. Without this pause, flutter_tts's stop() future can resolve
  /// slightly before the native (especially Android) engine has really
  /// stopped, so an immediate speak() right after gets silently swallowed —
  /// this is what caused every other question to go silent instead of every
  /// question reading aloud.
  Future<void> _stopAndSettle() async {
    await _tts.stop();
    await Future.delayed(const Duration(milliseconds: 80));
  }

  void stopReading() {
    _tts.stop();
    _isReading = false;
  }

  // ── Keyboard shortcuts reference ──────────────────────────────────────────
  static const Map<String, String> keyboardShortcuts = {
    'A / 1': 'Select option A',
    'B / 2': 'Select option B',
    'C / 3': 'Select option C',
    'D / 4': 'Select option D',
    'Enter / Space': 'Confirm answer / Next question',
    '→ Right Arrow': 'Confirm / Next',
    '← Left Arrow': 'Previous question',
    'V': 'Toggle voice reading',
    'Escape': 'Exit session',
  };
}
