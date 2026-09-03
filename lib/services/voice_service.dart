import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Voice reading and speech recognition for ACT questions.
/// STT note: on flutlab.io (web preview) microphone STT is unavailable —
/// it requires a real Android/iOS device or desktop. TTS works on all platforms.
class VoiceService {
  static final VoiceService instance = VoiceService._();
  VoiceService._();

  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _stt = stt.SpeechToText();

  bool _ttsReady = false;
  bool _sttReady = false;
  bool _isReading = false;
  bool _isListening = false;

  static const _prefKey    = 'sj_act_voice_enabled';
  static const _sttPrefKey = 'sj_act_stt_enabled';

  // ── Init ──────────────────────────────────────────────────────────────────
  Future<void> init() async {
    await _initTts();
    if (!kIsWeb) await _initStt();
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

  Future<void> _initStt() async {
    try {
      final granted = await Permission.microphone.isGranted;
      if (!granted) return;
      _sttReady = await _stt.initialize(
        onError: (_) => _isListening = false,
        onStatus: (s) { if (s == 'done' || s == 'notListening') _isListening = false; },
      );
    } catch (_) { _sttReady = false; }
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
  Future<bool> isSttEnabled() async {
    if (kIsWeb) return false; // STT unavailable on web
    final p = await SharedPreferences.getInstance();
    return p.getBool(_sttPrefKey) ?? false;
  }
  Future<void> setSttEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_sttPrefKey, v);
    if (!v) stopListening();
  }

  bool get ttsReady => _ttsReady;
  bool get sttReady => _sttReady && !kIsWeb;
  bool get isListening => _isListening;

  /// Returns a user-facing message explaining why STT is unavailable.
  String get sttUnavailableReason {
    if (kIsWeb) return 'Voice answer input is not available in the web/flutlab preview. '
        'Install the app on a real Android or iOS device to use this feature.';
    return 'Microphone permission required. Enable it in device settings.';
  }

  // ── TTS ───────────────────────────────────────────────────────────────────
  Future<void> readQuestion({required String questionText, required List<String> options}) async {
    if (!_ttsReady) return;
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
    await _tts.speak(text);
  }

  void stopReading() {
    _tts.stop();
    _isReading = false;
  }

  // ── STT ───────────────────────────────────────────────────────────────────
  Future<void> listenForAnswer({
    required void Function(String letter) onResult,
    void Function()? onUnrecognised,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    // STT not available on web (flutlab.io)
    if (kIsWeb) {
      onUnrecognised?.call();
      return;
    }
    if (_isListening) return;

    // Request mic permission
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      onUnrecognised?.call();
      return;
    }

    // Initialise if needed
    if (!_sttReady) {
      _sttReady = await _stt.initialize(
        onError: (_) => _isListening = false,
        onStatus: (s) { if (s == 'done' || s == 'notListening') _isListening = false; },
      );
    }
    if (!_sttReady) { onUnrecognised?.call(); return; }

    _isListening = true;

    // Set a hard timeout in case the STT callback never fires
    Timer(timeout + const Duration(seconds: 2), () {
      if (_isListening) {
        _isListening = false;
        _stt.stop();
        onUnrecognised?.call();
      }
    });

    try {
      bool resultFired = false;
      await _stt.listen(
        onResult: (result) {
          if (!result.finalResult || resultFired) return;
          resultFired = true;
          _isListening = false;
          final spoken = result.recognizedWords.toLowerCase().trim();
          final detected = _detectOptionFromSpeech(spoken);
          if (detected != null) {
            onResult(detected);
          } else {
            onUnrecognised?.call();
          }
        },
        listenFor: timeout,
        pauseFor: const Duration(seconds: 3),
        localeId: 'en_US',
        cancelOnError: true,
        listenMode: stt.ListenMode.confirmation,
      );
    } catch (e) {
      _isListening = false;
      onUnrecognised?.call();
    }
  }

  void stopListening() {
    if (!kIsWeb) _stt.stop();
    _isListening = false;
  }

  // ── Speech → letter detection ─────────────────────────────────────────────
  static String? _detectOptionFromSpeech(String spoken) {
    final s = spoken.toLowerCase().trim();
    if (s.isEmpty) return null;

    // Exact single letter
    if (RegExp(r'^\s*a\s*$').hasMatch(s)) return 'A';
    if (RegExp(r'^\s*b\s*$').hasMatch(s)) return 'B';
    if (RegExp(r'^\s*c\s*$').hasMatch(s)) return 'C';
    if (RegExp(r'^\s*d\s*$').hasMatch(s)) return 'D';

    // Phrase patterns
    final patterns = [
      RegExp(r"\b(option|answer|choice|letter|pick|select|go with|i\s*choose|i\s*think|it'?s?)\s+([abcd])\b"),
      RegExp(r'\b([abcd])\s+(is\s+)?(correct|right|the answer)\b'),
      RegExp(r'the answer is\s+([abcd])\b'),
      RegExp(r'\bmy answer is\s+([abcd])\b'),
      RegExp(r'\bi (pick|choose|select|say)\s+([abcd])\b'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(s);
      if (match != null) {
        // Try last group first (most specific)
        String? letter;
        for (int g = match.groupCount; g >= 1; g--) {
          final grp = match.group(g)?.toUpperCase();
          if (grp != null && ['A','B','C','D'].contains(grp)) {
            letter = grp; break;
          }
        }
        if (letter != null) return letter;
      }
    }

    // Phonetic fallbacks
    if (RegExp(r'\bay\b').hasMatch(s)) return 'A';
    if (RegExp(r'\bbee\b').hasMatch(s)) return 'B';
    if (RegExp(r'\b(see|sea|si)\b').hasMatch(s)) return 'C';
    if (RegExp(r'\b(dee|di)\b').hasMatch(s)) return 'D';

    // Last-resort: first letter in string
    final firstLetter = RegExp(r'\b([abcd])\b').firstMatch(s);
    if (firstLetter != null) {
      return firstLetter.group(1)!.toUpperCase();
    }

    return null;
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
    'M': 'Toggle microphone input',
    'Escape': 'Exit session',
  };
}
