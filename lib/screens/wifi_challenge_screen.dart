import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nsd/nsd.dart';

import '../data/questions_data.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/free_trial_service.dart';
import '../services/user_profile_service.dart';
import '../services/voice_service.dart';
import '../utils/theme.dart';
import '../widgets/mini_calculator.dart';

String _formatWifiTimerLabel(int seconds) =>
    seconds < 60 ? '${seconds}s' : (seconds % 60 == 0 ? '${seconds ~/ 60}m' : '${seconds ~/ 60}m ${seconds % 60}s');

String _formatWifiClock(int sec) {
  final m = (sec ~/ 60).toString().padLeft(2, '0');
  final s = (sec % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

// How long we'll wait for the platform's NSD (mDNS) service to actually
// register/discover before giving up and showing a clear error — instead of
// spinning forever. WiFi/Hotspot being off is the single biggest cause of a
// silent hang here: ServerSocket.bind usually still succeeds even with no
// real network (it can bind to a loopback-only interface), so onStarted
// would never fire AND no error would ever show either — the UI just sits
// there. This timeout turns that into an actionable message.
const Duration _kNetworkOpTimeout = Duration(seconds: 10);

/// A room found during discovery, with its address and port already
/// resolved from the discovery event itself (see `_scanRooms`) rather than
/// needing a separate `resolve()` round-trip later when the person taps it.
class _DiscoveredRoom {
  final String id;
  final String name;
  final String host;
  final int port;
  const _DiscoveredRoom({required this.id, required this.name, required this.host, required this.port});
}

// ── Simple local WiFi messaging over TCP ─────────────────────────────────────
class _WifiMsg {
  // chat | bet_propose | bet_respond | ready | start | answer | quit | ping | pong
  final String type;
  final Map<String, dynamic> data;
  _WifiMsg(this.type, this.data);
  String toJson() => jsonEncode({'type': type, 'data': data});
  static _WifiMsg fromJson(String raw) {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return _WifiMsg(m['type'] as String, (m['data'] as Map<String, dynamic>? ?? {}));
  }
}

// The lobby (host/join, chat, bet negotiation), the live synced match, and
// the result screen are all phases of ONE widget/state, instead of separate
// screens reached via Navigator.push. That matters here specifically because
// the TCP socket connection has to stay alive and keep being listened to for
// the whole session — if the match were a separate pushed screen, the lobby
// screen underneath would keep "owning" the socket while paused, and the new
// screen would have no way to receive opponent messages. Keeping everything
// in one state means the same `_handleMsg` keeps routing messages correctly
// no matter which phase is on screen.
enum _WifiPhase { lobby, inMatch, result }

class WifiChallengeScreen extends StatefulWidget {
  final bool fullAccess;
  // Free-trial add-on: one HOST attempt and one JOIN attempt, each capped
  // at 20 questions. Defaults to false so Standard/WiFi-activated callers
  // are unaffected.
  final bool trialMode;
  const WifiChallengeScreen({super.key, this.fullAccess = true, this.trialMode = false});

  @override
  State<WifiChallengeScreen> createState() => _WifiChallengeScreenState();
}

class _WifiChallengeScreenState extends State<WifiChallengeScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;

  // Host state
  Registration? _registration;
  ServerSocket? _server;
  Socket? _guestSocket;
  bool _hosting = false;
  bool _guestConnected = false;

  // Guest state
  Discovery? _discovery;
  List<_DiscoveredRoom> _foundRooms = [];
  bool _scanning = false;
  Socket? _hostSocket;
  bool _joined = false;

  // Shared
  String _myName = 'Me';
  String _opponentName = '';
  bool _opponentReady = false;
  bool _imReady = false;
  ActSection _section = ActSection.math;
  bool _randomMixSubject = false;
  int? _questionTimerSeconds = 60;
  bool get _wifiNoTimer => _questionTimerSeconds == null;
  int _questionCount = 30;

  // Bet (lobby negotiation)
  Map<String, dynamic>? _proposedBet;
  bool _betAccepted = false;
  bool _waitingBetResponse = false;
  String? _betProposedBy; // 'me' | 'opponent'

  // Chat
  final List<Map<String, dynamic>> _chatMessages = [];
  final _chatCtrl = TextEditingController();
  final ScrollController _chatScroll = ScrollController();

  static const _serviceType = '_sjact._tcp';

  // Buffers to correctly frame newline-delimited JSON messages arriving
  // over a raw TCP stream. TCP has no message boundaries of its own — a
  // single `data` event can contain a partial message (if it got split
  // across two reads), several messages at once, or a mix of both. The
  // previous version split each `data` event on '\n' in isolation, so any
  // message that happened to arrive split across two reads would have its
  // second half silently fail to parse and get dropped — which on a real
  // WiFi connection under any load is a real (not theoretical) way to lose
  // an 'answer' or 'start' message and desync or freeze a match. These
  // buffers carry a possibly-incomplete trailing line over to the next
  // `data` event instead of processing it prematurely.
  final StringBuffer _hostSideBuffer = StringBuffer();
  final StringBuffer _guestSideBuffer = StringBuffer();

  // Match launch guard — only ever fires the transition into the match once.
  bool _matchLaunched = false;
  _WifiPhase _phase = _WifiPhase.lobby;

  // Bet-loss access pause (WiFi Challenge only — kept separate from Online
  // Challenge's own pause so the two never interfere with each other).
  DateTime? _accessPauseUntil;
  bool _practiceRequired = false;

  // Free trial (see FreeTrialService): once host or join has been used
  // during the trial, that specific tab's action is disabled — but the
  // other one may still be available, since the trial grants one of each.
  bool _trialHostUsed = false;
  bool _trialJoinUsed = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    if (widget.trialMode) {
      _questionCount = FreeTrialService.trialChallengeQuestionCount;
      _loadTrialFlags();
    }
    _loadName();
    _checkAccessPause();
  }

  Future<void> _loadTrialFlags() async {
    final host = await FreeTrialService.hasUsedWifiHostTrial();
    final join = await FreeTrialService.hasUsedWifiJoinTrial();
    if (mounted) setState(() { _trialHostUsed = host; _trialJoinUsed = join; });
  }

  Future<void> _checkAccessPause() async {
    final until = await UserProfileService.getWifiAccessPauseUntil();
    final practiceRequired = await UserProfileService.getRequiresPracticeBeforeWifiChallenge();
    if (mounted) setState(() { _accessPauseUntil = until; _practiceRequired = practiceRequired; });
  }

  Future<void> _loadName() async {
    final n = await UserProfileService.getDisplayName();
    if (mounted) setState(() => _myName = n ?? 'Me');
  }

  // Checks for an actual usable network interface (WiFi or Hotspot) before
  // attempting anything. Without this, WiFi/Hotspot being off is the #1
  // cause of a silent hang: ServerSocket.bind can still succeed even with
  // no real network (it'll bind to a loopback-only interface), so the
  // "Room is live" state could show even though no other device could
  // ever actually reach it, and NSD's register()/startDiscovery() calls
  // can just hang waiting on a radio that isn't on. This turns that into
  // an immediate, actionable message instead.
  Future<bool> _isNetworkReady() async {
    try {
      final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
      return ifaces.any((i) => i.addresses.isNotEmpty);
    } catch (_) {
      return false;
    }
  }

  // ── Host ──────────────────────────────────────────────────────────────────
  Future<void> _startHosting() async {
    if (widget.trialMode && _trialHostUsed) {
      _showSnack('Your free trial host match has already been used.');
      return;
    }
    if (_accessPauseUntil != null && _accessPauseUntil!.isAfter(DateTime.now())) return;
    if (_practiceRequired) {
      _showSnack('You lost a bet that requires finishing one practice set before your next WiFi Challenge.');
      return;
    }
    // Guard against starting a host session while already scanning for or
    // connected to someone else's room as a guest.
    if (_scanning || _joined || _hostSocket != null) {
      _showSnack('You\'re already joining a room. Leave it first.');
      return;
    }
    if (!await _isNetworkReady()) {
      _showSnack('WiFi or Hotspot is off. Turn it on and make sure it\'s connected, then try again.');
      return;
    }
    if (widget.trialMode) {
      await FreeTrialService.markWifiHostTrialUsed();
      if (mounted) setState(() => _trialHostUsed = true);
    }
    try {
      // Bind to an OS-assigned free port (0) rather than a fixed hardcoded
      // one — a fixed port can fail to bind if anything else is using it
      // (including a leftover socket from this app's own previous session
      // that hasn't fully released it yet). The real port gets published
      // in the NSD registration below, so joining devices always read the
      // actual port instead of assuming a constant.
      final server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      _server = server;
      _registration = await register(Service(
        name: 'SJACT-$_myName',
        type: _serviceType,
        port: server.port,
        txt: {'host': Uint8List.fromList(utf8.encode(_myName))},
      )).timeout(_kNetworkOpTimeout);
      setState(() => _hosting = true);
      _server!.listen((socket) {
        socket.setOption(SocketOption.tcpNoDelay, true);
        _guestSocket = socket;
        setState(() => _guestConnected = true);
        _addChat(_opponentName.isEmpty ? 'Opponent' : _opponentName, 'Connected!');
        _listenToSocket(socket, isHost: true);
      });
    } on TimeoutException {
      try { await _server?.close(); } catch (_) {}
      _server = null;
      _showSnack('Could not start hosting — the network didn\'t respond in time. Make sure WiFi/Hotspot is on.');
    } catch (e) {
      try { await _server?.close(); } catch (_) {}
      _server = null;
      _showSnack('Could not start hosting: $e');
    }
  }

  Future<void> _stopHosting() async {
    if (_registration != null) {
      try { await unregister(_registration!); } catch (_) {}
      _registration = null;
    }
    try { await _server?.close(); } catch (_) {}
    _guestSocket?.destroy();
    setState(() {
      _hosting = false;
      _guestConnected = false;
      _server = null;
      _guestSocket = null;
    });
  }

  // ── Guest ─────────────────────────────────────────────────────────────────
  Future<void> _scanRooms() async {
    if (_accessPauseUntil != null && _accessPauseUntil!.isAfter(DateTime.now())) return;
    if (_practiceRequired) {
      _showSnack('You lost a bet that requires finishing one practice set before your next WiFi Challenge.');
      return;
    }
    // Guard against scanning/joining while already hosting a room.
    if (_hosting) {
      _showSnack('You\'re hosting a room. Stop hosting first.');
      return;
    }
    if (!await _isNetworkReady()) {
      _showSnack('WiFi or Hotspot is off. Turn it on (or join the host\'s Hotspot), then try again.');
      return;
    }
    setState(() { _scanning = true; _foundRooms = []; });
    final found = <String>{};
    try {
      _discovery = await startDiscovery(_serviceType, ipLookupType: IpLookupType.any).timeout(_kNetworkOpTimeout);
      _discovery!.addServiceListener((service, status) {
        if (status != ServiceStatus.found || !mounted) return;
        final addresses = service.addresses;
        final port = service.port;
        if (addresses == null || addresses.isEmpty || port == null) return;
        // `service.txt` values from the `nsd` package are raw UTF-8 bytes
        // (Uint8List), never a String directly. Casting straight to
        // `String?` throws a TypeError inside this listener callback for
        // every single discovered service — which silently aborts this
        // callback before `_foundRooms` ever gets updated, so Join always
        // showed "no rooms found" even with a live host nearby. Decode the
        // bytes properly, and fall back to `service.name` (which already
        // carries "SJACT-<hostName>") if TXT data isn't present at all.
        String hostText;
        try {
          final rawTxt = service.txt?['host'];
          hostText = rawTxt != null ? utf8.decode(rawTxt) : (service.name ?? 'Host');
        } catch (_) {
          hostText = service.name ?? 'Host';
        }
        final host = addresses.first.address;
        final id = '$host:$port';
        if (found.contains(id)) return;
        found.add(id);
        setState(() => _foundRooms.add(_DiscoveredRoom(id: id, name: hostText, host: host, port: port)));
      });
    } on TimeoutException {
      if (mounted) setState(() => _scanning = false);
      _showSnack('Search timed out. Make sure WiFi/Hotspot is on for both devices.');
      return;
    } catch (e) {
      if (mounted) setState(() => _scanning = false);
      _showSnack('Search failed: $e');
      return;
    }
    await Future.delayed(const Duration(seconds: 4));
    try { await stopDiscovery(_discovery!); } catch (_) {}
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _joinRoom(_DiscoveredRoom room) async {
    if (widget.trialMode && _trialJoinUsed) {
      _showSnack('Your free trial join match has already been used.');
      return;
    }
    if (widget.trialMode) {
      await FreeTrialService.markWifiJoinTrialUsed();
      if (mounted) setState(() => _trialJoinUsed = true);
    }
    // A WiFi connect attempt can fail transiently even on a perfectly fine
    // network (the host's listen socket not quite ready yet, a brief radio
    // hiccup) — a short retry-with-backoff makes that a non-issue instead
    // of an outright failure on the first try.
    const maxAttempts = 3;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      if (attempt > 0) await Future.delayed(Duration(milliseconds: 500 * attempt));
      try {
        final socket = await Socket.connect(room.host, room.port, timeout: const Duration(seconds: 8));
        socket.setOption(SocketOption.tcpNoDelay, true);
        _hostSocket = socket;
        setState(() { _joined = true; _opponentName = room.name; });
        _addChat(room.name, 'You joined the room!');
        _listenToSocket(socket, isHost: false);
        return;
      } catch (e) {
        if (attempt == maxAttempts - 1) {
          _showSnack('Could not join room: $e. Make sure both devices are on the same WiFi/Hotspot.');
        }
      }
    }
  }

  // ── Socket comms ──────────────────────────────────────────────────────────
  // Reads complete newline-delimited JSON messages out of a TCP byte
  // stream, carrying any trailing partial line over to the next call
  // instead of dropping/mis-parsing it (see the buffer fields above).
  void _onRawData(Uint8List data, StringBuffer buf, void Function(String) onLine) {
    buf.write(utf8.decode(data, allowMalformed: true));
    final text = buf.toString();
    final lines = text.split('\n');
    buf.clear();
    buf.write(lines.removeLast()); // last piece may be incomplete — keep it
    for (final l in lines) {
      final t = l.trim();
      if (t.isNotEmpty) onLine(t);
    }
  }

  void _listenToSocket(Socket socket, {required bool isHost}) {
    final buffer = isHost ? _hostSideBuffer : _guestSideBuffer;
    socket.listen((data) {
      _onRawData(data, buffer, (line) {
        try {
          final msg = _WifiMsg.fromJson(line);
          _handleMsg(msg, isHost: isHost);
        } catch (_) {}
      });
    }, onDone: _onSocketClosed, onError: (_) => _onSocketClosed());
  }

  void _send(_WifiMsg msg) {
    try {
      final bytes = utf8.encode('${msg.toJson()}\n');
      _guestSocket?.add(bytes);
      _hostSocket?.add(bytes);
    } catch (_) {
      // Socket already gone — the onDone/onError handler deals with that.
    }
  }

  void _onSocketClosed() {
    if (!mounted) return;
    if (_phase == _WifiPhase.inMatch && !_finished) {
      // A dropped raw socket can't reconnect itself, so unlike a Wi-Fi blip
      // this is treated as final — but the player still gets the same
      // "grace period" banner as any other disconnect before the match is
      // ended as a quit (never scored, never triggers a bet consequence).
      _beginDisconnectWarning();
    } else if (_phase == _WifiPhase.lobby) {
      _showSnack('Connection closed.');
    }
  }

  void _handleMsg(_WifiMsg msg, {required bool isHost}) {
    if (!mounted) return;
    switch (msg.type) {
      case 'chat':
        if (_phase != _WifiPhase.lobby) return; // in-match has no chat UI
        _addChat(_opponentName.isNotEmpty ? _opponentName : 'Opponent', msg.data['text'] as String? ?? '');
        break;
      case 'bet_propose':
        if (_phase != _WifiPhase.lobby) return;
        setState(() {
          _proposedBet = msg.data;
          _betProposedBy = 'opponent';
          _waitingBetResponse = true;
        });
        _addChat(_opponentName, 'Proposed a bet: ${msg.data['description']}');
        break;
      case 'bet_respond':
        if (_phase != _WifiPhase.lobby) return;
        final accepted = msg.data['accepted'] as bool? ?? false;
        final counter = msg.data['counter'] as bool? ?? false;
        if (counter) {
          setState(() {
            _proposedBet = msg.data['new_bet'] as Map<String, dynamic>?;
            _betProposedBy = 'opponent';
          });
          _addChat(_opponentName, 'Counter-bet: ${msg.data['new_bet']?['description']}');
        } else if (accepted) {
          setState(() { _betAccepted = true; _waitingBetResponse = false; });
          _addChat(_opponentName, 'Bet accepted!');
        } else {
          setState(() { _proposedBet = null; _waitingBetResponse = false; _betAccepted = false; });
          _addChat(_opponentName, 'Bet declined. Playing without stakes.');
        }
        break;
      case 'ready':
        setState(() { _opponentReady = true; _opponentName = msg.data['name'] as String? ?? _opponentName; });
        _addChat(_opponentName, 'Ready!');
        _maybeLaunch();
        break;
      case 'start':
        _applyStartPayload(msg.data);
        break;
      case 'answer':
        _onOpponentAnswer(msg.data);
        break;
      case 'quit':
        if (_phase == _WifiPhase.inMatch && !_finished) _finishMatch(quit: true);
        break;
      case 'ping':
        _send(_WifiMsg('pong', {}));
        break;
      case 'pong':
        _lastPongAt = DateTime.now();
        if (_disconnectWarning) {
          _disconnectTimer?.cancel();
          setState(() => _disconnectWarning = false);
        }
        break;
    }
  }

  // ── Bet system (lobby) ───────────────────────────────────────────────────
  void _proposeBet() {
    showDialog(
      context: context,
      builder: (_) => _BetDialog(
        onPropose: (type, value, description) {
          final bet = {'type': type, 'value': value, 'description': description};
          setState(() {
            _proposedBet = bet;
            _betProposedBy = 'me';
            _waitingBetResponse = true;
          });
          _send(_WifiMsg('bet_propose', bet));
          _addChat('You', 'Proposed bet: $description');
          Navigator.pop(context);
        },
      ),
    );
  }

  void _respondBet(bool accepted, {Map<String, dynamic>? counterBet}) {
    if (accepted) {
      setState(() { _betAccepted = true; _waitingBetResponse = false; });
      _send(_WifiMsg('bet_respond', {'accepted': true}));
      _addChat('You', 'Bet accepted!');
    } else if (counterBet != null) {
      setState(() { _proposedBet = counterBet; _betProposedBy = 'me'; });
      _send(_WifiMsg('bet_respond', {'accepted': false, 'counter': true, 'new_bet': counterBet}));
      _addChat('You', 'Counter-bet: ${counterBet['description']}');
    } else {
      setState(() { _proposedBet = null; _waitingBetResponse = false; _betAccepted = false; });
      _send(_WifiMsg('bet_respond', {'accepted': false}));
      _addChat('You', 'Bet declined.');
    }
  }

  void _markReady() {
    setState(() => _imReady = true);
    _send(_WifiMsg('ready', {'name': _myName, 'section': actSectionToString(_section), 'count': _questionCount, 'mixed': _randomMixSubject, 'timer': _questionTimerSeconds}));
    _addChat('You', 'Ready!');
    _maybeLaunch();
  }

  // Whichever side notices BOTH players are ready builds/sends the shared
  // match; the other side only ever reacts to the incoming 'start' message.
  // This replaces the old flow where each side independently decided when
  // to navigate into its own private quiz — which is exactly what could
  // leave one player stuck on "Waiting for opponent..." forever while the
  // other had already moved on, and meant the two devices were never
  // actually looking at the same questions at the same time.
  void _maybeLaunch() {
    if (_matchLaunched) return;
    if (!(_imReady && _opponentReady)) return;
    _matchLaunched = true;

    final isHost = _guestConnected; // true only for the side that accepted the connection
    if (isHost) {
      final pool = _randomMixSubject ? questionsForRandomMix() : questionsForSection(_section);
      if (pool.isEmpty) {
        _matchLaunched = false;
        _showSnack('No questions available for that section.');
        return;
      }
      final shuffled = List<ActQuestion>.from(pool)..shuffle(Random());
      final count = _questionCount.clamp(1, shuffled.length);
      final chosen = shuffled.take(count).toList();
      final ids = chosen.map((q) => q.id).toList();
      final payload = {
        'ids': ids,
        'section': actSectionToString(_section),
        'mixed': _randomMixSubject,
        'timer': _questionTimerSeconds,
      };
      _send(_WifiMsg('start', payload));
      _applyStartPayload(payload);
    } else {
      // Self-heal: if the host's 'start' message somehow never arrives
      // (should be effectively impossible over an open TCP connection,
      // since it's sent right after the 'ready' we just reacted to), don't
      // stay stuck — let the player try Ready again instead of being stuck
      // forever.
      Future.delayed(const Duration(seconds: 6), () {
        if (mounted && _phase == _WifiPhase.lobby) {
          _matchLaunched = false;
          _showSnack('Still waiting on the host to start — tap Ready again.');
        }
      });
    }
  }

  void _showSnack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _addChat(String sender, String text) {
    if (!mounted) return;
    setState(() => _chatMessages.add({'sender': sender, 'text': text, 'ts': DateTime.now()}));
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_chatScroll.hasClients) {
        _chatScroll.animateTo(_chatScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  void _sendChat() {
    final text = _chatCtrl.text.trim();
    if (text.isEmpty) return;
    _addChat('You', text);
    _send(_WifiMsg('chat', {'text': text}));
    _chatCtrl.clear();
  }

  // ══════════════════════════════════════════════════════════════════════
  // LIVE MATCH — both sides answer the same shared questions independently,
  // and only ever move to the next one once BOTH have answered (or each
  // side's own clock runs out), exactly mirroring the Online Challenge's
  // rules but driven by real messages from a real opponent instead of a
  // simulation.
  // ══════════════════════════════════════════════════════════════════════

  ActSection _matchSection = ActSection.math;
  bool _matchMixed = false;
  int? _matchTimerSeconds;
  List<ActQuestion> _matchQuestions = [];

  int _qIndex = 0;
  String? _selected;
  bool _showFeedback = false;
  final Map<int, String> _myAnswers = {};
  // Question index -> was the opponent's answer for that question correct.
  // Keyed by index (not just a running counter) so an opponent message that
  // arrives early or out of order still lines up with the right question —
  // this is what guarantees both players are always gated on the *same*
  // question rather than drifting out of sync.
  final Map<int, bool> _opponentAnsweredForIndex = {};
  bool _roundAdvancing = false;

  Timer? _qTimer;
  int _qSecondsLeft = 0;
  static const int _kWifiNoTimerSafetyNetSeconds = 150;

  bool _calcVisible = false;
  bool _voiceEnabled = false;
  final FocusNode _matchFocusNode = FocusNode();

  // Heartbeat / disconnect
  Timer? _heartbeatTimer;
  Timer? _disconnectTimer;
  bool _disconnectWarning = false;
  int _disconnectSec = 25;
  DateTime _lastPongAt = DateTime.now();

  bool _finished = false;
  bool _quitEarly = false;

  // Result snapshot
  double _resultMyScore = 1;
  double _resultOppScore = 1;
  int _resultMyCorrect = 0;
  int _resultOppCorrect = 0;
  int _resultMyAnswered = 0;
  int _resultOppAnswered = 0;
  bool _resultQuit = false;

  bool get _myTurnDone => _myAnswers.containsKey(_qIndex);
  bool get _opponentDone => _opponentAnsweredForIndex.containsKey(_qIndex);
  int get _myCorrectCount => _myAnswers.entries
      .where((e) => e.key < _matchQuestions.length && e.value == _matchQuestions[e.key].correctAnswer)
      .length;
  int get _opponentCorrectCount => _opponentAnsweredForIndex.values.where((v) => v).length;

  void _applyStartPayload(Map<String, dynamic> data) {
    if (_phase == _WifiPhase.inMatch) return; // already in, ignore a repeat
    _matchLaunched = true;
    final ids = (data['ids'] as List).cast<String>();
    final mixed = data['mixed'] as bool? ?? false;
    final section = actSectionFromString(data['section'] as String? ?? actSectionToString(_section));
    final timer = data['timer'] as int?;
    final pool = mixed ? questionsForRandomMix() : questionsForSection(section);
    final byId = {for (final q in pool) q.id: q};
    final resolved = ids.map((id) => byId[id]).whereType<ActQuestion>().toList();
    if (resolved.isEmpty) {
      _showSnack('Could not load the shared question set.');
      return;
    }
    setState(() {
      _matchSection = section;
      _matchMixed = mixed;
      _matchTimerSeconds = timer;
      _matchQuestions = resolved;
      _phase = _WifiPhase.inMatch;
    });
    _beginMatch();
  }

  void _beginMatch() {
    _qIndex = 0;
    _myAnswers.clear();
    _opponentAnsweredForIndex.clear();
    _finished = false;
    _quitEarly = false;
    _disconnectWarning = false;
    _loadVoiceForMatch();
    _startHeartbeat();
    WidgetsBinding.instance.addPostFrameCallback((_) => _matchFocusNode.requestFocus());
    _beginRound();
  }

  Future<void> _loadVoiceForMatch() async {
    await VoiceService.instance.init();
    final enabled = await VoiceService.instance.isTtsEnabled();
    if (mounted) setState(() => _voiceEnabled = enabled);
  }

  void _toggleVoice() async {
    final newVal = !_voiceEnabled;
    await VoiceService.instance.setTtsEnabled(newVal);
    if (!newVal) VoiceService.instance.stopReading();
    if (mounted) setState(() => _voiceEnabled = newVal);
  }

  void _beginRound() {
    _selected = _myAnswers[_qIndex];
    _showFeedback = _myAnswers.containsKey(_qIndex);
    _roundAdvancing = false;
    _qTimer?.cancel();
    // Whether or not the host set a visible per-question timer, a round is
    // never allowed to wait forever: with a timer, it's the number the
    // player sees; without one, this is a silent safety net so "no timer"
    // still can't hang the match if something goes wrong.
    _qSecondsLeft = _matchTimerSeconds ?? _kWifiNoTimerSafetyNetSeconds;
    _qTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _roundAdvancing || _disconnectWarning) return;
      setState(() => _qSecondsLeft--);
      if (_qSecondsLeft <= 0) _forceAdvanceOnTimeout();
    });
    if (mounted) setState(() {});
  }

  void _forceAdvanceOnTimeout() {
    // Same fix as Online Challenge: don't set _roundAdvancing = true here.
    // _maybeAdvance() below bails out immediately if _roundAdvancing is
    // already true (that's how it avoids double-scheduling), so setting it
    // true right before calling _maybeAdvance() meant it always returned
    // without ever actually scheduling the move to the next question —
    // and _roundAdvancing only resets in _nextQuestion(), which this was
    // stopping from ever running. _maybeAdvance() sets it itself once it
    // confirms both sides are actually done.
    _qTimer?.cancel();
    if (!_myAnswers.containsKey(_qIndex)) {
      _myAnswers[_qIndex] = ''; // skipped — my own time ran out
      _send(_WifiMsg('answer', {'q': _qIndex, 'letter': '', 'correct': false}));
      if (mounted) setState(() => _showFeedback = true);
    }
    _maybeAdvance();
  }

  void _selectAnswer(String letter) {
    // Exactly like Online Challenge: both players answer independently and
    // simultaneously. Picking an option is never blocked by the opponent —
    // only confirming locks it in (or the timer running out).
    if (_showFeedback || _disconnectWarning) return;
    HapticFeedback.lightImpact();
    setState(() => _selected = letter);
  }

  void _confirmAnswer() {
    if (_selected == null || _showFeedback || _disconnectWarning) return;
    HapticFeedback.mediumImpact();
    final q = _matchQuestions[_qIndex];
    final correct = _selected == q.correctAnswer;
    _myAnswers[_qIndex] = _selected!;
    setState(() => _showFeedback = true);
    _qTimer?.cancel();
    if (_voiceEnabled) {
      VoiceService.instance.readText(correct ? 'Correct.' : 'Incorrect. The answer is ${q.correctAnswer}.');
    }
    _send(_WifiMsg('answer', {'q': _qIndex, 'letter': _selected, 'correct': correct}));
    _maybeAdvance();
  }

  void _onOpponentAnswer(Map<String, dynamic> data) {
    final qi = data['q'] as int?;
    if (qi == null) return;
    final correct = data['correct'] as bool? ?? false;
    setState(() => _opponentAnsweredForIndex[qi] = correct);
    _maybeAdvance();
  }

  void _maybeAdvance() {
    if (_roundAdvancing || _disconnectWarning) return;
    if (_myTurnDone && _opponentDone) {
      _roundAdvancing = true;
      Future.delayed(const Duration(milliseconds: 900), _nextQuestion);
    }
  }

  void _nextQuestion() {
    if (_finished) return;
    if (_qIndex < _matchQuestions.length - 1) {
      setState(() => _qIndex++);
      _beginRound();
    } else {
      _finishMatch();
    }
  }

  void _finishMatch({bool quit = false}) async {
    if (_finished) return;
    _finished = true;
    _quitEarly = quit;
    _qTimer?.cancel();
    _heartbeatTimer?.cancel();
    _disconnectTimer?.cancel();
    VoiceService.instance.stopReading();

    final total = _matchQuestions.length;
    final myCorrect = _myCorrectCount;
    final myAcc = total == 0 ? 0.0 : myCorrect / total;
    final myScore = (1 + myAcc * 35).clamp(1.0, 36.0);
    final oppCorrect = _opponentCorrectCount;
    final oppAcc = total == 0 ? 0.0 : oppCorrect / total;
    final oppScore = (1 + oppAcc * 35).clamp(1.0, 36.0);

    final results = List.generate(total, (i) {
      final given = _myAnswers[i] ?? '';
      return QuestionResult(
        questionId: _matchQuestions[i].id,
        givenAnswer: given,
        isCorrect: given == _matchQuestions[i].correctAnswer,
        timeSpent: Duration.zero,
      );
    });
    final attempt = ExamAttempt(
      id: DateTime.now().toIso8601String(),
      startedAt: DateTime.now(),
      completedAt: DateTime.now(),
      setNumber: 1,
      section: _matchMixed ? null : _matchSection,
      results: results,
    );
    await DatabaseService.instance.saveAttempt(attempt);

    if (!quit) {
      // Ranking and any bet consequence ONLY ever apply here — the one path
      // reached by playing every question through to the end. Leaving early
      // or a disconnect-triggered quit always skips this block entirely, so
      // nothing is ever won, lost, or docked from a match that wasn't
      // actually finished by both players.
      // Only write once a real display name is known — a placeholder
      // fallback (like the transient "Me" used before a name loads)
      // leaves a permanent duplicate "you" row on the leaderboard.
      final name = await UserProfileService.getDisplayName();
      if (name != null) {
        await DatabaseService.instance.upsertLeaderboardEntry(name, myScore, myAcc);
      }
      final tie = (myScore - oppScore).abs() < 0.1;
      final iWon = myScore > oppScore;
      await _applyBetConsequence(iWon, tie);
    }

    if (!mounted) return;
    setState(() {
      _phase = _WifiPhase.result;
      _resultMyScore = myScore;
      _resultOppScore = oppScore;
      _resultMyCorrect = myCorrect;
      _resultOppCorrect = oppCorrect;
      _resultMyAnswered = _myAnswers.length;
      _resultOppAnswered = _opponentAnsweredForIndex.length;
      _resultQuit = quit;
    });
  }

  Future<void> _applyBetConsequence(bool iWon, bool tie) async {
    final bet = _proposedBet;
    if (bet == null || !_betAccepted || tie) return;
    final type = bet['type'];
    final value = (bet['value'] ?? '').toString();
    switch (type) {
      case 'access':
        if (!iWon) {
          final hours = int.tryParse(value) ?? 2;
          await UserProfileService.setWifiAccessPauseUntil(DateTime.now().add(Duration(hours: hours)));
        }
        break;
      case 'ranking':
        {
          // Zero-sum: winner gains the points, loser loses the same amount.
          final pts = int.tryParse(value) ?? 1;
          await UserProfileService.addBetRankingPoints(iWon ? pts : -pts);
        }
        break;
      case 'badge':
        if (!iWon) {
          await UserProfileService.setChallengerBadgeSuspendedFor(const Duration(hours: 24));
        }
        break;
    }
  }

  // ── Heartbeat / disconnect handling ─────────────────────────────────────
  void _startHeartbeat() {
    _lastPongAt = DateTime.now();
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || _finished) return;
      _send(_WifiMsg('ping', {}));
      if (DateTime.now().difference(_lastPongAt) > const Duration(seconds: 12)) {
        _beginDisconnectWarning();
      }
    });
  }

  void _beginDisconnectWarning() {
    if (_disconnectWarning || _finished) return;
    setState(() { _disconnectWarning = true; _disconnectSec = 25; });
    _disconnectTimer?.cancel();
    _disconnectTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _disconnectSec--);
      if (_disconnectSec <= 0) { t.cancel(); _finishMatch(quit: true); }
    });
  }

  // True for the final 3 questions of a match with an accepted bet riding
  // on it — the window where leaving is locked out so a bet can't be
  // dodged by quitting just before losing.
  bool get _exitLockedByBet =>
      _betAccepted && _proposedBet != null && (_matchQuestions.length - _qIndex) <= 3;

  int get _questionsUntilExitUnlocked =>
      (_matchQuestions.length - _qIndex).clamp(0, 3);

  Future<void> _confirmExitMatch() async {
    // Same protection as Online Challenge: once a bet has been accepted
    // and the match is down to its final 3 questions, "Leave Match" is
    // locked out. Leaving cancels the bet outright (see the dialog copy
    // below) which otherwise makes it a free way to dodge a losing bet
    // right before the match actually ends.
    if (_exitLockedByBet) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('You have a bet riding on this match — you can\'t leave in the final $_questionsUntilExitUnlocked question${_questionsUntilExitUnlocked == 1 ? '' : 's'}.'),
      ));
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Leave Match?'),
        content: const Text('Leaving now ends the match for both players right away. Nothing counts toward your ranking, and any bet is cancelled — same as if the connection dropped.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Stay')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ActColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (leave == true) {
      _send(_WifiMsg('quit', {}));
      _finishMatch(quit: true);
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    _qTimer?.cancel();
    _heartbeatTimer?.cancel();
    _disconnectTimer?.cancel();
    VoiceService.instance.stopReading();
    _stopHosting();
    if (_discovery != null) stopDiscovery(_discovery!);
    _hostSocket?.destroy();
    _chatCtrl.dispose();
    _chatScroll.dispose();
    _matchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _WifiPhase.lobby:
        return _buildLobbyScaffold();
      case _WifiPhase.inMatch:
        return _buildMatchScaffold();
      case _WifiPhase.result:
        return _buildResultScaffold();
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // LOBBY UI
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildLobbyScaffold() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isConnected = _guestConnected || _joined;
    final paused = _accessPauseUntil != null && _accessPauseUntil!.isAfter(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('WiFi Challenge'),
        bottom: (isConnected || paused) ? null : TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          tabs: const [Tab(text: 'HOST'), Tab(text: 'JOIN')],
          // Prevent hosting and joining at the same time. Without this, a
          // person who tapped "Start Hosting" (room live, waiting for a
          // guest) could still swipe/tap over to JOIN and connect out to
          // someone else's room while their own was still open — two live
          // sockets fighting over the same _handleMsg routing at once.
          onTap: (index) {
            if (_hosting && index == 1) {
              _tab.index = 0;
              _showSnack('You\'re hosting a room. Stop hosting first if you want to join someone else\'s.');
            } else if ((_scanning || _joined || _hostSocket != null) && index == 0) {
              _tab.index = 1;
              _showSnack('You\'re joining a room. Leave it first if you want to host your own.');
            }
          },
        ),
      ),
      body: paused
          ? _buildPausedNotice()
          : (isConnected
              ? _buildRoom(isDark)
              : TabBarView(
                  controller: _tab,
                  children: [_buildHostTab(isDark), _buildJoinTab(isDark)],
                )),
    );
  }

  Widget _buildPausedNotice() {
    final until = _accessPauseUntil!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lock_clock, size: 42, color: ActColors.warning),
          const SizedBox(height: 14),
          const Text('WiFi Challenge access is paused', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'You lost an "access hours" bet last match. Access returns at '
            '${until.hour.toString().padLeft(2, '0')}:${until.minute.toString().padLeft(2, '0')}.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: ActColors.midGray, height: 1.4),
          ),
        ]),
      ),
    );
  }

  // ── Host tab ──────────────────────────────────────────────────────────────
  Widget _buildHostTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoBanner('Host a room on your local WiFi network. A friend on the same network can find and join your room.', isDark),
          const SizedBox(height: 20),

          _Label('ACT Section'),
          DropdownButtonFormField<ActSection>(
            value: _section,
            decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            items: ActSection.values.map((s) => DropdownMenuItem(value: s, child: Text(actSectionDisplayName(s)))).toList(),
            onChanged: _randomMixSubject ? null : (s) { if (s != null) setState(() => _section = s); },
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _randomMixSubject,
            onChanged: (v) => setState(() => _randomMixSubject = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            title: const Text('Random Mix (all subjects)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: const Text('Pull questions from every subject instead of one', style: TextStyle(fontSize: 11)),
          ),
          const SizedBox(height: 14),
          _Label('Questions'),
          IgnorePointer(
            ignoring: widget.trialMode,
            child: Opacity(
              opacity: widget.trialMode ? 0.5 : 1,
              child: Wrap(
                spacing: 8,
                children: [10, 20, 30, 40].map((n) => ChoiceChip(
                  label: Text('$n'),
                  selected: _questionCount == n,
                  selectedColor: ActColors.primary,
                  labelStyle: TextStyle(color: _questionCount == n ? Colors.white : null, fontWeight: FontWeight.w600),
                  onSelected: (_) => setState(() => _questionCount = n),
                )).toList(),
              ),
            ),
          ),
          if (widget.trialMode)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Free trial matches are fixed at ${FreeTrialService.trialChallengeQuestionCount} questions.',
                  style: TextStyle(fontSize: 11, color: ActColors.midGray)),
            ),
          const SizedBox(height: 14),
          _Label('Time per Question'),
          SwitchListTile(
            value: !_wifiNoTimer,
            onChanged: (v) => setState(() => _questionTimerSeconds = v ? (_questionTimerSeconds ?? 60) : null),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Use a per-question timer', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          if (!_wifiNoTimer) ...[
            Wrap(spacing: 8, children: [30, 60, 90, 120, 180].map((n) => ChoiceChip(
              label: Text(_formatWifiTimerLabel(n)),
              selected: _questionTimerSeconds == n,
              selectedColor: ActColors.primary,
              labelStyle: TextStyle(color: _questionTimerSeconds == n ? Colors.white : null, fontWeight: FontWeight.w600, fontSize: 12),
              onSelected: (_) => setState(() => _questionTimerSeconds = n),
            )).toList()),
            const SizedBox(height: 4),
            Text('Whoever hasn\'t answered when the clock hits 0 is skipped automatically — both of you always move to the next question together.',
                style: TextStyle(fontSize: 10.5, color: ActColors.midGray)),
          ],
          const SizedBox(height: 20),

          if (!_hosting)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: ActColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.wifi_tethering),
                label: const Text('Start Hosting', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                onPressed: _startHosting,
              ),
            )
          else
            Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: ActColors.success.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: ActColors.success.withOpacity(0.25)),
                  ),
                  child: Row(
                    children: [
                      const CircularProgressIndicator(strokeWidth: 2),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Room is live', style: TextStyle(fontWeight: FontWeight.w700)),
                            Text('Waiting for a friend to join...', style: TextStyle(fontSize: 12, color: ActColors.midGray)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _stopHosting,
                  child: Text('Stop Hosting', style: TextStyle(color: ActColors.danger)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ── Join tab ──────────────────────────────────────────────────────────────
  Widget _buildJoinTab(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoBanner('Search for rooms hosted by friends on the same WiFi network.', isDark),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: ActColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: _scanning
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.search),
              label: Text(_scanning ? 'Searching...' : 'Search for Rooms',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              onPressed: _scanning ? null : _scanRooms,
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _foundRooms.isEmpty
                ? Center(
                    child: Text(
                      _scanning ? 'Scanning for rooms...' : 'No rooms found. Make sure your friend is hosting on the same WiFi.',
                      style: TextStyle(color: ActColors.midGray, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    itemCount: _foundRooms.length,
                    itemBuilder: (_, i) {
                      final room = _foundRooms[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.wifi),
                          title: Text(room.name),
                          subtitle: const Text('Tap to join'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _joinRoom(room),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ── Connected room (lobby, post-connection) ─────────────────────────────
  Widget _buildRoom(bool isDark) {
    return Column(
      children: [
        // Players header
        Container(
          padding: const EdgeInsets.all(16),
          color: ActColors.primary.withOpacity(0.07),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _PlayerStatus(name: _myName, isReady: _imReady, isMe: true),
              Text('VS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: ActColors.primary)),
              _PlayerStatus(name: _opponentName.isNotEmpty ? _opponentName : 'Opponent', isReady: _opponentReady, isMe: false),
            ],
          ),
        ),

        // Bet status
        if (_proposedBet != null || _betAccepted)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: ActColors.warning.withOpacity(0.08),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_betAccepted)
                  Row(children: [
                    Icon(Icons.handshake_outlined, size: 16, color: ActColors.warning),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Active bet: ${_proposedBet?['description'] ?? ''}',
                        style: TextStyle(fontSize: 12, color: ActColors.warning, fontWeight: FontWeight.w600))),
                  ])
                else if (_betProposedBy == 'opponent' && !_betAccepted) ...[
                  Text('${_opponentName.isNotEmpty ? _opponentName : "Opponent"} proposes:',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                  Text(_proposedBet?['description'] ?? '', style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: ActColors.danger, side: BorderSide(color: ActColors.danger.withOpacity(0.5))),
                      onPressed: () => _respondBet(false),
                      child: const Text('Decline'),
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: ActColors.warning),
                      onPressed: () => _respondBet(true),
                      child: const Text('Accept', style: TextStyle(color: Colors.white)),
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: OutlinedButton(
                      onPressed: () => showDialog(
                        context: context,
                        builder: (_) => _BetDialog(
                          onPropose: (type, value, desc) {
                            _respondBet(false, counterBet: {'type': type, 'value': value, 'description': desc});
                            Navigator.pop(context);
                          },
                        ),
                      ),
                      child: const Text('Counter'),
                    )),
                  ]),
                ] else if (_betProposedBy == 'me')
                  Text('Waiting for ${_opponentName.isNotEmpty ? _opponentName : "opponent"} to respond to your bet...',
                      style: TextStyle(fontSize: 12, color: ActColors.midGray)),
              ],
            ),
          ),

        // Chat (takes up most of the space)
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _chatScroll,
                  padding: const EdgeInsets.all(12),
                  itemCount: _chatMessages.length,
                  itemBuilder: (_, i) {
                    final m = _chatMessages[i];
                    final isMe = m['sender'] == 'You';
                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isMe ? ActColors.primary : (isDark ? ActColors.darkCard : const Color(0xFFF0F0F0)),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(14),
                            topRight: const Radius.circular(14),
                            bottomLeft: Radius.circular(isMe ? 14 : 4),
                            bottomRight: Radius.circular(isMe ? 4 : 14),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                          children: [
                            Text(m['sender'] as String,
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                                    color: isMe ? Colors.white70 : ActColors.midGray)),
                            const SizedBox(height: 2),
                            Text(m['text'] as String,
                                style: TextStyle(fontSize: 13, color: isMe ? Colors.white : null)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Chat input
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                decoration: BoxDecoration(
                  color: isDark ? ActColors.darkCard : Colors.white,
                  border: Border(top: BorderSide(color: isDark ? ActColors.darkBorder : ActColors.lightBorder)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _chatCtrl,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Message...',
                          hintStyle: const TextStyle(fontSize: 13),
                          filled: true,
                          fillColor: isDark ? ActColors.darkSurface : const Color(0xFFF5F5F5),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onSubmitted: (_) => _sendChat(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.send),
                      color: ActColors.primary,
                      onPressed: _sendChat,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Bottom action bar
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          color: isDark ? ActColors.darkCard : Colors.white,
          child: Row(
            children: [
              if (_proposedBet == null && !_betAccepted)
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.handshake_outlined, size: 16),
                    label: const Text('Propose Bet'),
                    onPressed: _proposeBet,
                  ),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _imReady ? ActColors.success : ActColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _imReady ? null : _markReady,
                  child: Text(
                    _imReady ? 'Waiting for ${_opponentName.isNotEmpty ? _opponentName : "opponent"}...' : 'Ready',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // MATCH UI
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildMatchScaffold() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_matchQuestions.isEmpty) {
      return const Scaffold(body: Center(child: Text('No questions available.')));
    }
    final q = _matchQuestions[_qIndex];
    final myTurn = !_showFeedback && !_disconnectWarning;
    final currentSection = _matchMixed ? q.section : _matchSection;
    final showCalcButton = currentSection == ActSection.math || currentSection == ActSection.science;
    final oppLabel = _opponentName.isEmpty ? 'opponent' : _opponentName;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) { if (!didPop) _confirmExitMatch(); },
      child: Focus(
        focusNode: _matchFocusNode,
        child: Scaffold(
          appBar: AppBar(
            title: Text('${_matchMixed ? "Random Mix" : actSectionDisplayName(_matchSection)} — Q${_qIndex + 1}/${_matchQuestions.length}'),
            leading: _exitLockedByBet
                ? Tooltip(
                    message: 'Leave locked — bet match, $_questionsUntilExitUnlocked question${_questionsUntilExitUnlocked == 1 ? '' : 's'} left',
                    child: IconButton(
                      icon: Badge(
                        label: Text('$_questionsUntilExitUnlocked'),
                        child: const Icon(Icons.lock_outline),
                      ),
                      onPressed: _confirmExitMatch,
                    ),
                  )
                : IconButton(icon: const Icon(Icons.close), onPressed: _confirmExitMatch),
            actions: [
              IconButton(
                icon: Icon(_voiceEnabled ? Icons.volume_up : Icons.volume_off_outlined,
                    color: _voiceEnabled ? Colors.white : Colors.white60),
                tooltip: 'Voice Reading',
                onPressed: _toggleVoice,
              ),
              if (showCalcButton)
                IconButton(
                  icon: Icon(_calcVisible ? Icons.calculate : Icons.calculate_outlined,
                      color: _calcVisible ? ActColors.accent : Colors.white70),
                  tooltip: 'Calculator',
                  onPressed: () => setState(() => _calcVisible = !_calcVisible),
                ),
              if (_matchTimerSeconds != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(
                    child: Text(_formatWifiClock(_qSecondsLeft.clamp(0, 999999)),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white)),
                  ),
                ),
            ],
          ),
          body: Stack(children: [
            Column(children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                color: ActColors.primary.withOpacity(0.06),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _scorePill('You', _myCorrectCount, _myAnswers.length, true),
                    Text('VS', style: TextStyle(fontWeight: FontWeight.w900, color: ActColors.primary)),
                    _scorePill(oppLabel, _opponentCorrectCount, _opponentAnsweredForIndex.length, false),
                  ],
                ),
              ),
              LinearProgressIndicator(
                value: (_qIndex + 1) / _matchQuestions.length,
                color: ActColors.accent,
                backgroundColor: ActColors.accent.withOpacity(0.15),
                minHeight: 3,
              ),
              if (_disconnectWarning) _wifiDisconnectBanner(),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
                color: isDark ? ActColors.darkCard : const Color(0xFFF7F7F7),
                child: Text(
                  myTurn
                      ? (_opponentDone
                          ? '$oppLabel already answered — your turn'
                          : 'Answer now — no need to wait on $oppLabel')
                      : 'Waiting for $oppLabel...',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : ActColors.midGray),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (q.passageText != null)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? ActColors.darkSurface : const Color(0xFFF5F5F5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(q.passageText!, style: const TextStyle(fontSize: 13, height: 1.5)),
                        ),
                      Text(q.questionText, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.5)),
                      const SizedBox(height: 16),
                      ...List.generate(q.options.length, (i) {
                        final letter = q.optionLetters[i];
                        final isSelected = _selected == letter;
                        final isCorrect = letter == q.correctAnswer;
                        Color border = isDark ? ActColors.darkBorder : ActColors.lightBorder;
                        Color bg = isDark ? ActColors.darkCard : Colors.white;
                        Color? fg;
                        if (_showFeedback) {
                          if (isCorrect) { border = ActColors.success; bg = ActColors.success.withOpacity(0.08); fg = ActColors.success; }
                          else if (isSelected) { border = ActColors.danger; bg = ActColors.danger.withOpacity(0.08); fg = ActColors.danger; }
                        } else if (isSelected) {
                          border = ActColors.primary; bg = ActColors.primary.withOpacity(0.07);
                        }
                        return GestureDetector(
                          onTap: () => _selectAnswer(letter),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: bg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: border, width: (isSelected || (_showFeedback && isCorrect)) ? 2 : 1),
                            ),
                            child: Row(children: [
                              Container(
                                width: 26,
                                height: 26,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(shape: BoxShape.circle, color: border.withOpacity(0.15)),
                                child: Text(letter, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: fg ?? border)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Text(q.options[i], style: TextStyle(fontSize: 13.5, color: fg))),
                            ]),
                          ),
                        );
                      }),
                      if (_showFeedback)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(q.explanation,
                              style: TextStyle(fontSize: 12.5, color: isDark ? Colors.white70 : ActColors.midGray, height: 1.5)),
                        ),
                    ],
                  ),
                ),
              ),
              if (!_showFeedback)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: ActColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: (_selected == null || _disconnectWarning) ? null : _confirmAnswer,
                      child: const Text('Confirm Answer', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
            ]),
            if (_calcVisible)
              Positioned(right: 12, bottom: 90, child: MiniCalculatorOverlay(onClose: () => setState(() => _calcVisible = false))),
          ]),
        ),
      ),
    );
  }

  Widget _scorePill(String name, int correct, int answered, bool isMe) => Column(
        children: [
          Text(name,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: isMe ? ActColors.primary : ActColors.info),
              overflow: TextOverflow.ellipsis),
          Text('$correct/$answered correct', style: TextStyle(fontSize: 10.5, color: ActColors.midGray)),
        ],
      );

  Widget _wifiDisconnectBanner() => Container(
        width: double.infinity,
        color: ActColors.danger.withOpacity(0.12),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
        child: Row(children: [
          Icon(Icons.wifi_off, size: 16, color: ActColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Connection lost — ending the match in ${_disconnectSec}s if it doesn\'t come back...',
              style: TextStyle(fontSize: 11.5, color: ActColors.danger, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      );

  // ══════════════════════════════════════════════════════════════════════
  // RESULT UI
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildResultScaffold() {
    final total = _matchQuestions.length;
    final tie = !_resultQuit && (_resultMyScore - _resultOppScore).abs() < 0.1;
    final myWon = !_resultQuit && !tie && _resultMyScore > _resultOppScore;

    return Scaffold(
      appBar: AppBar(title: const Text('Match Result'), automaticallyImplyLeading: false),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              if (_resultQuit)
                Text('Match ended early', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: ActColors.midGray))
              else
                Text(
                  tie ? "It's a tie!" : (myWon ? 'You won! 🎉' : 'Good game.'),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    color: tie ? ActColors.warning : (myWon ? ActColors.success : ActColors.danger),
                  ),
                ),
              if (_resultQuit)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Nothing counted toward your ranking, and any bet was cancelled.',
                      style: TextStyle(fontSize: 12, color: ActColors.midGray), textAlign: TextAlign.center),
                ),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _resultCard('You', _resultMyScore, _resultMyCorrect, _resultMyAnswered, total, !_resultQuit),
                _resultCard(_opponentName.isEmpty ? 'Opponent' : _opponentName, _resultOppScore, _resultOppCorrect, _resultOppAnswered, total, !_resultQuit),
              ]),
              const SizedBox(height: 24),
              if (_proposedBet != null && _betAccepted && !_resultQuit && !tie)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: ActColors.warning.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Bet Result', style: TextStyle(fontWeight: FontWeight.w700, color: ActColors.warning)),
                      const SizedBox(height: 4),
                      Text(_proposedBet!['description'] as String? ?? '', style: const TextStyle(fontSize: 12.5)),
                    ],
                  ),
                ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: ActColors.primary, padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultCard(String name, double score, int correct, int answered, int total, bool showScore) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(border: Border.all(color: ActColors.lightBorder), borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13), overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            if (showScore) Text(score.toStringAsFixed(1), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 26, color: ActColors.primary)),
            Text('$correct/$total correct', style: TextStyle(fontSize: 11, color: ActColors.midGray)),
            Text('$answered answered', style: TextStyle(fontSize: 10.5, color: ActColors.midGray)),
          ]),
        ),
      );
}

class _PlayerStatus extends StatelessWidget {
  final String name;
  final bool isReady, isMe;
  const _PlayerStatus({required this.name, required this.isReady, required this.isMe});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      CircleAvatar(
        radius: 22,
        backgroundColor: isMe ? ActColors.primary : ActColors.info,
        child: Text(name.substring(0, 1).toUpperCase(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
      ),
      const SizedBox(height: 6),
      Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12), overflow: TextOverflow.ellipsis),
      const SizedBox(height: 3),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: isReady ? ActColors.success.withOpacity(0.12) : ActColors.midGray.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          isReady ? 'Ready' : 'Not Ready',
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: isReady ? ActColors.success : ActColors.midGray),
        ),
      ),
    ],
  );
}

class _BetDialog extends StatefulWidget {
  final void Function(String type, String value, String description) onPropose;
  const _BetDialog({required this.onPropose});

  @override
  State<_BetDialog> createState() => _BetDialogState();
}

class _BetDialogState extends State<_BetDialog> {
  String _type = 'ranking';
  final _valueCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Propose a Bet'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            value: _type,
            decoration: const InputDecoration(labelText: 'Bet Type', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'ranking', child: Text('Ranking Points')),
              DropdownMenuItem(value: 'badge', child: Text('Badge Stake')),
              DropdownMenuItem(value: 'access', child: Text('Access Hours')),
            ],
            onChanged: (v) { if (v != null) setState(() => _type = v); },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _valueCtrl,
            decoration: InputDecoration(
              labelText: _type == 'ranking' ? 'Points (e.g. 5)' : _type == 'badge' ? 'Badge name' : 'Hours (e.g. 3)',
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: ActColors.primary),
          onPressed: () {
            final v = _valueCtrl.text.trim();
            if (v.isEmpty) return;
            final desc = _type == 'ranking'
                ? 'Winner gains $v ranking points; loser loses the same.'
                : _type == 'badge'
                    ? 'Loser forfeits the $v badge for 24 hours.'
                    : 'Loser\'s access is paused for $v hours.';
            widget.onPropose(_type, v, desc);
          },
          child: const Text('Propose'),
        ),
      ],
    );
  }

  @override
  void dispose() { _valueCtrl.dispose(); super.dispose(); }
}

class _InfoBanner extends StatelessWidget {
  final String text;
  final bool isDark;
  const _InfoBanner(this.text, this.isDark);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: ActColors.info.withOpacity(0.07),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: ActColors.info.withOpacity(0.20)),
    ),
    child: Row(
      children: [
        Icon(Icons.info_outline, size: 16, color: ActColors.info),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87, height: 1.4))),
      ],
    ),
  );
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
  );
}
