import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:nsd/nsd.dart';

import '../models/models.dart';
import '../services/user_profile_service.dart';
import '../utils/theme.dart';
import 'section_screen.dart';

// ── Simple local WiFi messaging over TCP ─────────────────────────────────────
class _WifiMsg {
  final String type; // chat | bet_propose | bet_respond | ready | start | result
  final Map<String, dynamic> data;
  _WifiMsg(this.type, this.data);
  String toJson() => jsonEncode({'type': type, 'data': data});
  static _WifiMsg fromJson(String raw) {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return _WifiMsg(m['type'] as String, m['data'] as Map<String, dynamic>);
  }
}

class WifiChallengeScreen extends StatefulWidget {
  final bool fullAccess;
  const WifiChallengeScreen({super.key, this.fullAccess = true});

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
  List<Service> _foundRooms = [];
  bool _scanning = false;
  Socket? _hostSocket;
  bool _joined = false;

  // Shared
  String _myName = 'Me';
  String _opponentName = '';
  bool _opponentReady = false;
  bool _imReady = false;
  ActSection _section = ActSection.math;
  int _questionCount = 30;

  // Bet
  Map<String, dynamic>? _proposedBet;
  bool _betAccepted = false;
  bool _waitingBetResponse = false;
  String? _betProposedBy; // 'me' | 'opponent'

  // Chat
  final List<Map<String, dynamic>> _chatMessages = [];
  final _chatCtrl = TextEditingController();
  final ScrollController _chatScroll = ScrollController();

  static const _serviceType = '_sjact._tcp';
  static const _servicePort = 49201;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadName();
  }

  Future<void> _loadName() async {
    final n = await UserProfileService.getDisplayName();
    if (mounted) setState(() => _myName = n ?? 'Me');
  }

  // ── Host ──────────────────────────────────────────────────────────────────
  Future<void> _startHosting() async {
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, _servicePort);
      _registration = await register(Service(
        name: 'SJACT-$_myName',
        type: _serviceType,
        port: _servicePort,
        txt: {'host': Uint8List.fromList(utf8.encode(_myName))},
      ));
      setState(() => _hosting = true);
      _server!.listen((socket) {
        _guestSocket = socket;
        setState(() => _guestConnected = true);
        _addChat(_opponentName.isEmpty ? 'Opponent' : _opponentName, 'Connected!');
        _listenToSocket(socket, isHost: true);
      });
    } catch (e) {
      _showSnack('Could not start hosting: $e');
    }
  }

  Future<void> _stopHosting() async {
    if (_registration != null) await unregister(_registration!);
    await _server?.close();
    _guestSocket?.destroy();
    setState(() {
      _hosting = false;
      _guestConnected = false;
      _registration = null;
      _server = null;
      _guestSocket = null;
    });
  }

  // ── Guest ─────────────────────────────────────────────────────────────────
  Future<void> _scanRooms() async {
    setState(() { _scanning = true; _foundRooms = []; });
    _discovery = await startDiscovery(_serviceType);
    _discovery!.addServiceListener((service, status) {
      if (status == ServiceStatus.found && mounted) {
        setState(() => _foundRooms.add(service));
      }
    });
    await Future.delayed(const Duration(seconds: 4));
    await stopDiscovery(_discovery!);
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _joinRoom(Service service) async {
    try {
      final resolved = await resolve(service);
      final addr = resolved.addresses?.first.address ?? 'localhost';
      final socket = await Socket.connect(addr, _servicePort, timeout: const Duration(seconds: 6));
      _hostSocket = socket;
      final host = (resolved.txt?['host'] as String?) ?? service.name ?? 'Host';
      setState(() { _joined = true; _opponentName = host; });
      _addChat(host, 'You joined the room!');
      _listenToSocket(socket, isHost: false);
    } catch (e) {
      _showSnack('Could not join room: $e');
    }
  }

  // ── Socket comms ──────────────────────────────────────────────────────────
  void _listenToSocket(Socket socket, {required bool isHost}) {
    socket.transform(StreamTransformer<Uint8List, String>.fromHandlers(
      handleData: (data, sink) {
        final raw = utf8.decode(data).trim();
        for (final line in raw.split('\n')) {
          if (line.isNotEmpty) sink.add(line);
        }
      },
    )).listen((line) {
      try {
        final msg = _WifiMsg.fromJson(line);
        _handleMsg(msg, isHost: isHost);
      } catch (_) {}
    }, onDone: () {
      if (mounted) _showSnack('Connection closed.');
    });
  }

  void _send(_WifiMsg msg) {
    final json = '${msg.toJson()}\n';
    final bytes = utf8.encode(json);
    _guestSocket?.add(bytes);
    _hostSocket?.add(bytes);
  }

  void _handleMsg(_WifiMsg msg, {required bool isHost}) {
    if (!mounted) return;
    switch (msg.type) {
      case 'chat':
        _addChat(_opponentName.isNotEmpty ? _opponentName : 'Opponent', msg.data['text'] as String? ?? '');
        break;
      case 'bet_propose':
        setState(() {
          _proposedBet = msg.data;
          _betProposedBy = 'opponent';
          _waitingBetResponse = true;
        });
        _addChat(_opponentName, 'Proposed a bet: ${msg.data['description']}');
        break;
      case 'bet_respond':
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
        break;
      case 'start':
        _launchMatch();
        break;
    }
  }

  // ── Bet system ────────────────────────────────────────────────────────────
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
    _send(_WifiMsg('ready', {'name': _myName, 'section': actSectionToString(_section), 'count': _questionCount}));
    _addChat('You', 'Ready!');
    if (_opponentReady) _launchMatch();
  }

  void _launchMatch() {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => SectionScreen(section: _section, questionCount: _questionCount, isChallengeMode: true),
    ));
  }

  // ── Chat ──────────────────────────────────────────────────────────────────
  void _sendChat() {
    final text = _chatCtrl.text.trim();
    if (text.isEmpty) return;
    _addChat('You', text);
    _send(_WifiMsg('chat', {'text': text}));
    _chatCtrl.clear();
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_chatScroll.hasClients) {
        _chatScroll.animateTo(_chatScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  void _addChat(String sender, String text) {
    if (!mounted) return;
    setState(() => _chatMessages.add({'sender': sender, 'text': text, 'ts': DateTime.now()}));
  }

  void _showSnack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _tab.dispose();
    _stopHosting();
    if (_discovery != null) stopDiscovery(_discovery!);
    _hostSocket?.destroy();
    _chatCtrl.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isConnected = _guestConnected || _joined;

    return Scaffold(
      appBar: AppBar(
        title: const Text('WiFi Challenge'),
        bottom: isConnected ? null : TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          tabs: const [Tab(text: 'HOST'), Tab(text: 'JOIN')],
        ),
      ),
      body: isConnected
          ? _buildRoom(isDark)
          : TabBarView(
              controller: _tab,
              children: [_buildHostTab(isDark), _buildJoinTab(isDark)],
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
            onChanged: (s) { if (s != null) setState(() => _section = s); },
          ),
          const SizedBox(height: 14),
          _Label('Questions'),
          Wrap(
            spacing: 8,
            children: [10, 20, 30, 40].map((n) => ChoiceChip(
              label: Text('$n'),
              selected: _questionCount == n,
              selectedColor: ActColors.primary,
              labelStyle: TextStyle(color: _questionCount == n ? Colors.white : null, fontWeight: FontWeight.w600),
              onSelected: (_) => setState(() => _questionCount = n),
            )).toList(),
          ),
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
                          title: Text(room.name ?? 'Unnamed Room'),
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

  // ── Connected room ────────────────────────────────────────────────────────
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
