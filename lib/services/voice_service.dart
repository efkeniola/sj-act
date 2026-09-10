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
  String? _lastSttError;

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
        onError: (e) { _isListening = false; _lastSttError = e.errorMsg; },
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

  // ── STT ───────────────────────────────────────────────────────────────────
  /// Listens for a spoken "A"/"B"/"C"/"D" answer.
  ///
  /// [onUnrecognised] receives a human-readable reason so the UI can tell the
  /// user *why* it failed (permission blocked, no speech engine on the
  /// device, nothing understood, etc.) instead of always showing the same
  /// generic "couldn't detect an answer" message.
  Future<void> listenForAnswer({
    required void Function(String letter) onResult,
    void Function(String reason)? onUnrecognised,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    // STT not available on web (flutlab.io)
    if (kIsWeb) {
      onUnrecognised?.call(sttUnavailableReason);
      return;
    }
    if (_isListening) return;

    // Request mic permission (this also correctly re-prompts the very first
    // time, even if _initStt() skipped initialisation earlier because
    // permission wasn't granted yet at app start).
    final status = await Permission.microphone.request();
    if (status == PermissionStatus.permanentlyDenied) {
      onUnrecognised?.call(
        'Microphone permission is blocked for this app. Please enable it in '
        'your device Settings → Apps → SJ ACT → Permissions → Microphone.',
      );
      return;
    }
    if (status != PermissionStatus.granted) {
      onUnrecognised?.call('Microphone permission is required to answer by voice.');
      return;
    }

    // Initialise (or re-initialise) the recognizer now that we know we have
    // permission. onError always writes into _lastSttError so any failure —
    // whether during this initialize() call or during the listen() session
    // right after — is available to explain a failed attempt.
    _lastSttError = null;
    if (!_sttReady) {
      _sttReady = await _stt.initialize(
        onError: (e) { _isListening = false; _lastSttError = e.errorMsg; },
        onStatus: (s) { if (s == 'done' || s == 'notListening') _isListening = false; },
      );
    }
    if (!_sttReady) {
      onUnrecognised?.call(
        'Speech recognition is not available on this device'
        '${_lastSttError != null ? ' ($_lastSttError)' : ''}. '
        'Make sure a speech-recognition service (e.g. Google app) is installed and up to date.',
      );
      return;
    }

    _isListening = true;

    // Set a hard timeout in case the STT callback never fires
    final hardTimeout = Timer(timeout + const Duration(seconds: 2), () {
      if (_isListening) {
        _isListening = false;
        _stt.stop();
        onUnrecognised?.call(_lastSttError ?? 'Didn\'t catch that — no speech was detected. Try again.');
      }
    });

    try {
      bool resultFired = false;
      await _stt.listen(
        onResult: (result) {
          if (!result.finalResult || resultFired) return;
          resultFired = true;
          hardTimeout.cancel();
          _isListening = false;
          final spoken = result.recognizedWords.toLowerCase().trim();
          final detected = _detectOptionFromSpeech(spoken);
          if (detected != null) {
            onResult(detected);
          } else if (spoken.isEmpty) {
            onUnrecognised?.call('Didn\'t catch that — no speech was detected. Try again.');
          } else {
            onUnrecognised?.call('Heard "$spoken" — please say just "A", "B", "C", or "D".');
          }
        },
        listenFor: timeout,
        pauseFor: const Duration(seconds: 3),
        localeId: 'en_US',
        cancelOnError: true,
        listenMode: stt.ListenMode.confirmation,
        // Prefer the device's on-device/offline recognizer so answering by
        // voice keeps working without an internet connection. On devices
        // where on-device recognition isn't available, the platform
        // transparently falls back to the online recognizer.
        onDevice: true,
      );
    } catch (e) {
      hardTimeout.cancel();
      _isListening = false;
      onUnrecognised?.call('Voice recognition failed to start. Please try again.');
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
