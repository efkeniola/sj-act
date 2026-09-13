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
    await _initStt();
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
      // permission_handler (used for the native mic-permission check below)
      // doesn't have real web support — calling it on web can throw or
      // return a meaningless status. On web, the browser handles its own
      // microphone permission prompt internally the moment the Web Speech
      // API is started, so there's nothing to pre-check here at all.
      if (!kIsWeb) {
        final granted = await Permission.microphone.isGranted;
        if (!granted) return;
      }
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
    final p = await SharedPreferences.getInstance();
    return p.getBool(_sttPrefKey) ?? false;
  }
  Future<void> setSttEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_sttPrefKey, v);
    if (!v) stopListening();
  }

  bool get ttsReady => _ttsReady;
  bool get sttReady => _sttReady;
  bool get isListening => _isListening;

  /// Returns a user-facing message explaining why STT is unavailable.
  /// Only shown when _stt.initialize() genuinely fails — e.g. a browser
  /// that doesn't implement the Web Speech API at all (Firefox, Safari),
  /// or a device with no speech-recognition service installed.
  String get sttUnavailableReason {
    if (kIsWeb) return 'Voice answer input needs a browser that supports the Web Speech API '
        '(Chrome or Edge). It isn\'t supported in this browser.';
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
  ///
  /// [onPartial] fires on every partial (in-progress) transcript, purely so
  /// the UI can show live "heard so far: ..." feedback — this is what makes
  /// it possible to actually tell whether the mic is picking up audio at
  /// all versus picking it up but failing to parse it as a letter, instead
  /// of both cases looking identical ("nothing happened").
  Future<void> listenForAnswer({
    required void Function(String letter) onResult,
    void Function(String reason)? onUnrecognised,
    void Function(String partialText)? onPartial,
    Duration timeout = const Duration(seconds: 10),
  }) => _listenAttempt(
        onResult: onResult,
        onUnrecognised: onUnrecognised,
        onPartial: onPartial,
        timeout: timeout,
        modeAttempt: 0,
      );

  // error_no_match means Android's recognizer captured audio fine but
  // couldn't match it to ANY vocabulary entry at all — this is a real,
  // well-known limitation of phone speech engines with very short,
  // single-syllable isolated utterances like a bare "A"; it's not
  // something app-level text parsing can work around, since no text is
  // ever produced to parse. Different ListenModes use different Android
  // language models under the hood with different tolerances for this, so
  // on a no-match we automatically retry once with a different mode
  // before bothering the person with an error — most of the time this
  // alone recovers it with no extra tap needed.
  static const List<stt.ListenMode> _modeAttempts = [
    stt.ListenMode.dictation,
    stt.ListenMode.confirmation,
    stt.ListenMode.search,
  ];

  Future<void> _listenAttempt({
    required void Function(String letter) onResult,
    void Function(String reason)? onUnrecognised,
    void Function(String partialText)? onPartial,
    required Duration timeout,
    required int modeAttempt,
  }) async {
    if (_isListening) return;

    if (kIsWeb) {
      // On web there's no permission_handler support and no separate
      // "request permission" step to call ahead of time — starting the Web
      // Speech API via _stt.listen() below triggers the browser's own
      // native mic-permission prompt itself. If the browser doesn't
      // support the Web Speech API at all (Firefox, Safari), initialize()
      // just below will return false and that's reported clearly.
    } else {
      // Request mic permission (this also correctly re-prompts the very
      // first time, even if _initStt() skipped initialisation earlier
      // because permission wasn't granted yet at app start).
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
    }

    // Initialise (or re-initialise) the recognizer now that we know we have
    // permission. onError always writes into _lastSttError so any failure —
    // whether during this initialize() call or during the listen() session
    // right after — is available to explain a failed attempt.
    //
    // Re-initialising on every single call (not just when !_sttReady) used
    // to leave a stale/wedged recognizer session in place on some devices
    // after a prior failed attempt — that's what could make it look like
    // "the mic lights up but literally nothing happens" on a retry. Forcing
    // a full stop + fresh initialize before every listen makes each attempt
    // independent of whatever state the previous one left behind.
    _lastSttError = null;
    try { await _stt.stop(); } catch (_) {}
    _sttReady = await _stt.initialize(
      onError: (e) { _isListening = false; _lastSttError = e.errorMsg; },
      onStatus: (s) { if (s == 'done' || s == 'notListening') _isListening = false; },
    );
    if (!_sttReady) {
      onUnrecognised?.call(
        'Speech recognition is not available on this device'
        '${_lastSttError != null ? ' ($_lastSttError)' : ''}. '
        'Make sure a speech-recognition service (e.g. Google app) is installed and up to date.',
      );
      return;
    }

    _isListening = true;
    bool resultFired = false;
    final isLastAttempt = modeAttempt >= _modeAttempts.length - 1;

    void finish(String? letter, String? reason, String heardRaw) {
      if (resultFired) return;
      resultFired = true;
      _isListening = false;
      _stt.stop();

      if (letter != null) {
        onResult(letter);
        return;
      }

      // On a no-match (recognizer heard SOMETHING but matched it to
      // nothing), silently retry with a different ListenMode before
      // bothering the person with an error — different modes use
      // different underlying Android language models, and one that
      // rejects a bare "A" outright often accepts it fine.
      final wasNoMatch = (reason ?? '').contains('no_match') || heardRaw.isEmpty;
      if (wasNoMatch && !isLastAttempt) {
        _listenAttempt(
          onResult: onResult,
          onUnrecognised: onUnrecognised,
          onPartial: onPartial,
          timeout: timeout,
          modeAttempt: modeAttempt + 1,
        );
        return;
      }

      if (reason != null) {
        onUnrecognised?.call(reason);
      } else if (heardRaw.isEmpty) {
        onUnrecognised?.call(
          'Didn\'t catch that after a few tries. Instead of just the letter, '
          'try saying "Option A" (or B/C/D) — that\'s usually picked up more reliably than a bare letter.',
        );
      } else {
        onUnrecognised?.call('Heard "$heardRaw" — please say "A", "B", "C", "D", or "Option A".');
      }
    }

    // Set a hard timeout in case the STT callback never fires at all —
    // this is the difference between "the mic icon stays yellow forever
    // with no feedback" and actually telling the person something failed.
    final hardTimeout = Timer(timeout + const Duration(seconds: 3), () {
      finish(null, _lastSttError, '');
    });

    try {
      await _stt.listen(
        onResult: (result) {
          final spoken = result.recognizedWords.toLowerCase().trim();
          onPartial?.call(result.recognizedWords);

          // Accept a confident match on a PARTIAL result immediately,
          // rather than only ever acting on result.finalResult. Several
          // Android speech-recognition services reliably deliver a clean
          // partial transcript within a second or two but then either
          // delay the "final" flag well past what feels responsive, or —
          // on some devices/firmware — never mark a result final at all
          // for a single-word utterance, relying entirely on the pauseFor
          // silence timeout to end the session. Waiting only for
          // finalResult made those sessions look completely dead even
          // though the word "A" had already been heard and understood.
          final detected = _detectOptionFromSpeech(spoken);
          if (detected != null) {
            hardTimeout.cancel();
            finish(detected, null, spoken);
            return;
          }

          if (result.finalResult) {
            hardTimeout.cancel();
            finish(null, null, spoken);
          }
        },
        listenFor: timeout,
        pauseFor: const Duration(seconds: 3),
        // Deliberately NOT forcing localeId: 'en_US' — that locks
        // recognition to US English pronunciation/vocabulary regardless
        // of what the device is actually configured for, which makes a
        // no-match MORE likely for anyone using a different English
        // locale (en_GB, en_NG, en_IN, etc.). Omitting it lets the
        // recognizer use the device's own configured language, which is
        // a better match for the person's actual accent.
        cancelOnError: true,
        partialResults: true,
        listenMode: _modeAttempts[modeAttempt],
        // Cycling ListenModes (dictation -> confirmation -> search) on
        // repeated no-match — see _modeAttempts above for why. This used
        // to be hardcoded to ListenMode.search, which is tuned for
        // multi-word search-style queries and is often exactly the mode
        // that rejects an isolated single letter as noise.
        // NOTE: this used to force onDevice: true ("prefer the on-device
        // recognizer so voice answers keep working offline"). In practice
        // that's not a safe assumption — plenty of Android phones (older
        // devices, and many outside the US) don't have an offline speech
        // model downloaded at all, and forcing on-device recognition on
        // those devices doesn't reliably fall back online the way the
        // plugin's docs imply. Instead it just fails to produce any
        // result — which looks exactly like "the mic lights up but saying
        // 'A' never selects anything." Letting the platform pick
        // (online-preferred, falling back to on-device where available)
        // is far more reliable across real devices.
      );
    } catch (e) {
      hardTimeout.cancel();
      finish(null, 'Voice recognition failed to start. Please try again.', '');
    }
  }

  void stopListening() {
    _stt.stop();
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
