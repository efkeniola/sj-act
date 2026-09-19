import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/questions_data.dart';
import '../models/models.dart';
import '../multiplayer/fake_online_challenge.dart';
import '../services/database_service.dart';
import '../services/daily_usage_service.dart';
import '../services/free_trial_service.dart';
import '../services/leaderboard_service.dart';
import '../services/user_profile_service.dart';
import '../services/voice_service.dart';
import '../utils/constants.dart';
import '../utils/theme.dart';
import '../widgets/mini_calculator.dart';

String _formatOnlineTimerLabel(int seconds) =>
    seconds < 60 ? '${seconds}s' : (seconds % 60 == 0 ? '${seconds ~/ 60}m' : '${seconds ~/ 60}m ${seconds % 60}s');


// ── Setup screen ──────────────────────────────────────────────────────────────
class OnlineChallengeScreen extends StatefulWidget {
  // Free-trial add-on: host-only, capped at 20 questions, usable once.
  // Defaults to false so every other caller (Standard/Online activation)
  // is unaffected.
  final bool trialMode;
  // True only for a Standard-activation user spending their one free
  // daily match. When true, the day's free-match counter is decremented
  // at the moment the match actually STARTS (_startMatch()) — not when
  // this screen is merely opened — so backing out of setup/search before
  // an opponent is even found never costs the day's free match. Callers
  // that already have full Online Challenge activation (unlimited) or are
  // using the free trial (tracked separately by FreeTrialService) should
  // leave this false.
  final bool countsAgainstDailyFree;
  const OnlineChallengeScreen({super.key, this.trialMode = false, this.countsAgainstDailyFree = false});

  @override
  State<OnlineChallengeScreen> createState() => _OnlineChallengeScreenState();
}

class _OnlineChallengeScreenState extends State<OnlineChallengeScreen> {
  OnlineChallengeRegion _region = OnlineChallengeRegion.usa;
  ActSection _section = ActSection.math;
  bool _randomMixSubject = false;
  late int _questionCount;
  // null = no per-question timer (unlimited thinking time). Host can set
  // anywhere from 15s up to a 3-minute (180s) cap — English/Reading passages
  // need more room than a quick Math question.
  int? _questionTimerSeconds = 60;
  bool get _noTimer => _questionTimerSeconds == null;

  bool _searching = false;
  String _statusMsg = '';
  String? _opponentName;
  bool _joinedExistingRoom = false; // true when user joined someone else's room (roles reversed)
  ChallengeBetProposal? _pendingBet;
  String _betProposedBy = 'opponent'; // 'opponent' or 'me'
  bool _betAccepted = false;
  bool _betDeclined = false;
  StreamSubscription<String>? _matchSub;

  // Host auto-start (2 minutes) once matched
  Timer? _hostStartTimer;
  int _hostStartSecondsLeft = 120;
  bool _dailyUsageRecorded = false; // guards against double-counting a single match start
  bool _trialUsageRecorded = false; // guards against double-counting the free-trial match

  final List<Map<String, dynamic>> _chatMessages = [];
  final _chatCtrl = TextEditingController();
  final _chatScrollCtrl = ScrollController();
  bool _opponentTyping = false;

  // Bet consequence: block starting a new search while paused
  DateTime? _accessPauseUntil;
  bool _practiceRequired = false;

  // Real-internet monitoring for the matched lobby (chat/bet/ready) phase —
  // the match screen already checks this continuously once gameplay
  // starts; this covers the gap before that, since chatting and agreeing to
  // a bet is just as much "online" activity as answering questions is.
  Timer? _netMonitorTimer;
  bool _netOk = true;

  void _startNetMonitor() {
    _netMonitorTimer?.cancel();
    _netOk = true;
    // Lobby chat/bet negotiation checks much more often than a live
    // question does (every 2s here vs every 8s mid-match) and never runs a
    // countdown-then-forfeit on your own end — nothing's at stake yet, so
    // there's nothing for the app itself to force-end. But a real opponent
    // isn't obligated to sit there either: the auto-start countdown above
    // keeps ticking the whole time you're disconnected, and the longer the
    // outage drags on, the more likely they just give up on you and leave,
    // same as the "rare human behaviour" leave-chance already built into
    // that timer — just weighted much higher while you're unreachable.
    final rng = Random();
    int lostStreak = 0;
    _netMonitorTimer = Timer.periodic(const Duration(seconds: 2), (t) async {
      if (!mounted || _opponentName == null) { t.cancel(); return; }
      final ok = await FakeOnlineChallenge.hasRealInternet(timeout: const Duration(seconds: 4));
      if (!mounted) return;
      if (!ok) {
        lostStreak++;
        if (!_netOk) {
          // already showing the banner — nothing new to render
        } else {
          setState(() => _netOk = false);
        }
        // First ~6s (3 checks) is given as normal WiFi flakiness. After
        // that, escalating odds per check that they lose patience.
        if (lostStreak > 3) {
          final leaveChance = (0.12 + (lostStreak - 3) * 0.08).clamp(0.0, 0.7);
          if (rng.nextDouble() < leaveChance) {
            t.cancel();
            _removeOpponentAndResearch(disconnected: true);
            return;
          }
        }
      } else {
        if (_netOk == false) setState(() => _netOk = true);
        lostStreak = 0;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _questionCount = widget.trialMode ? FreeTrialService.trialChallengeQuestionCount : 30;
    _checkAccessPause();
  }

  Future<void> _checkAccessPause() async {
    final until = await UserProfileService.getOnlineAccessPauseUntil();
    final practiceRequired = await UserProfileService.getRequiresPracticeBeforeOnlineChallenge();
    if (mounted) setState(() { _accessPauseUntil = until; _practiceRequired = practiceRequired; });
  }

  @override
  void dispose() {
    _matchSub?.cancel();
    _hostStartTimer?.cancel();
    _netMonitorTimer?.cancel();
    _chatCtrl.dispose();
    _chatScrollCtrl.dispose();
    super.dispose();
  }

  bool get _setupLocked => _searching || _opponentName != null;

  void _startSearch() {
    if (_accessPauseUntil != null && _accessPauseUntil!.isAfter(DateTime.now())) return;
    if (_practiceRequired) return;
    // Trial usage is now recorded in _startMatch(), the moment the match
    // actually begins — not here, when the user has merely tapped
    // Start/Search. See the doc comment on _startMatch() for why: tapping
    // Start doesn't guarantee an opponent is ever found or a match ever
    // starts, so burning the trial here could cost the user their one
    // free match for nothing.
    setState(() {
      _searching = true;
      _statusMsg = 'Connecting...';
      _opponentName = null;
      _joinedExistingRoom = false;
      _pendingBet = null;
      _betAccepted = false;
      _betDeclined = false;
      _opponentTyping = false;
      _chatMessages.clear();
    });
    _matchSub?.cancel();
    _matchSub = FakeOnlineChallenge.hostWait(_region).listen(_onStatus);
  }

  void _onStatus(String status) {
    if (!mounted) return;
    if (status == 'no_internet') {
      setState(() { _searching = false; _statusMsg = 'No internet connection detected. Please check your connection.'; });
      return;
    }
    if (status == 'timeout') {
      setState(() { _searching = false; _statusMsg = 'No opponent found at this hour. Try again in a few minutes.'; });
      return;
    }
    if (status == 'no_open_match') {
      setState(() { _searching = false; _statusMsg = 'No open matches right now. Tap Host to create one.'; });
      return;
    }
    if (status.startsWith('joined:')) {
      final name = status.substring(7);
      setState(() {
        _opponentName = name;
        _searching = false;
        _statusMsg = '';
        _joinedExistingRoom = false; // this screen is always "host" flow
      });
      _addChat(name, FakeOnlineChallenge.opponentOpeningMessage(name));
      _startHostStartTimer();
      _startNetMonitor();
      return;
    }
    setState(() => _statusMsg = status);
  }

  // ── Host 2-minute auto-start ────────────────────────────────────────────
  // Once an opponent is found, the host has 2 minutes to hit "Start
  // Challenge". If they don't, the match proceeds automatically — just like
  // a real opponent wouldn't wait around forever.
  void _startHostStartTimer() {
    _hostStartTimer?.cancel();
    _hostStartSecondsLeft = 120;
    _hostStartTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _opponentName == null) { t.cancel(); return; }
      setState(() => _hostStartSecondsLeft--);
      if (_hostStartSecondsLeft <= 0) {
        t.cancel();
        _startMatch();
      }
    });
  }

  /// Host removes the currently matched opponent (not satisfied / opponent
  /// delaying, or gave up during a connection outage) and goes back to
  /// searching.
  void _removeOpponentAndResearch({bool disconnected = false}) {
    _hostStartTimer?.cancel();
    _netMonitorTimer?.cancel();
    final name = _opponentName;
    setState(() {
      _opponentName = null;
      _pendingBet = null;
      _betAccepted = false;
      _betDeclined = false;
      _chatMessages.clear();
      _netOk = true;
    });
    if (name != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(disconnected
            ? '$name left — your connection dropped for too long.'
            : 'Removed $name from the match. Searching again...')),
      );
    }
    _startSearch();
  }

  void _addChat(String sender, String text) {
    if (!mounted) return;
    setState(() => _chatMessages.add({'sender': sender, 'text': text, 'ts': DateTime.now()}));
    Future.delayed(const Duration(milliseconds: 80), () {
      if (_chatScrollCtrl.hasClients) {
        _chatScrollCtrl.animateTo(_chatScrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  void _sendChat() {
    final text = _chatCtrl.text.trim();
    if (text.isEmpty) return;
    _addChat('You', text);
    _chatCtrl.clear();
    _maybeOpponentReply();
  }

  /// Simulates a human opponent replying to chat: most of the time they
  /// reply after a realistic "typing" delay drawn from a large phrase bank,
  /// but sometimes — just like a real person — they don't reply at all.
  void _maybeOpponentReply() {
    if (_opponentName == null) return;
    final rng = Random();
    // ~22% chance the opponent just doesn't respond to this particular message.
    if (rng.nextDouble() < 0.22) return;

    final typingDelay = Duration(milliseconds: 500 + rng.nextInt(900));
    Future.delayed(typingDelay, () {
      if (!mounted || _opponentName == null) return;
      setState(() => _opponentTyping = true);
      final replyDelay = Duration(seconds: 2 + rng.nextInt(5));
      Future.delayed(replyDelay, () {
        if (!mounted || _opponentName == null) return;
        setState(() => _opponentTyping = false);
        _addChat(_opponentName!, FakeOnlineChallenge.randomChatReply());
      });
    });
  }

  // ── Betting (host flow: the host decides whether to bring in a bet) ───────
  void _hostProposeRandomBet() {
    final bet = FakeOnlineChallenge.fakeOpponentBetProposal(guaranteed: true);
    if (bet == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No bet generated — try again.')),
      );
      return;
    }
    setState(() { _pendingBet = bet; _betProposedBy = 'me'; _betAccepted = false; _betDeclined = false; });
    _addChat('You', 'Bet proposal: ${bet.description}');
    _simulateOpponentBetResponse(bet);
  }

  // A bet decision isn't instant for a real person — they read it, think it
  // over, then type a reply. This shows the same "typing..." indicator used
  // for regular chat while that thinking happens, so accept/decline/counter
  // never just pop in silently.
  void _showOpponentThinkingThenReply(VoidCallback onReply) {
    final rng = Random();
    final thinkDelay = Duration(seconds: 1 + rng.nextInt(3));
    Future.delayed(thinkDelay, () {
      if (!mounted || _opponentName == null) return;
      setState(() => _opponentTyping = true);
      final typeDelay = Duration(milliseconds: 700 + rng.nextInt(1800));
      Future.delayed(typeDelay, () {
        if (!mounted) return;
        setState(() => _opponentTyping = false);
        onReply();
      });
    });
  }

  void _simulateOpponentBetResponse(ChallengeBetProposal bet) {
    final rng = Random();
    _showOpponentThinkingThenReply(() {
      if (_opponentName == null || _pendingBet != bet) return;
      final roll = rng.nextDouble();
      if (roll < 0.55) {
        // Accepts
        setState(() => _betAccepted = true);
        _addChat(_opponentName!, 'Deal. Let\'s go.');
      } else if (roll < 0.80) {
        // Counter-proposes a different bet
        final counter = FakeOnlineChallenge.fakeOpponentBetProposal();
        if (counter != null) {
          setState(() { _pendingBet = counter; _betProposedBy = 'opponent'; });
          _addChat(_opponentName!, 'Counter: ${counter.description}');
        } else {
          setState(() { _pendingBet = null; _betDeclined = true; });
          _addChat(_opponentName!, 'Let\'s just play clean, no bet.');
        }
      } else {
        // Declines outright
        setState(() { _pendingBet = null; _betDeclined = true; });
        _addChat(_opponentName!, 'Nah, I\'ll pass on that one.');
      }
    });
  }

  void _acceptBet() {
    setState(() => _betAccepted = true);
    _addChat('You', 'Bet accepted.');
    _showOpponentThinkingThenReply(() {
      if (_opponentName != null) _addChat(_opponentName!, 'Let\'s go then!');
    });
  }

  void _declineBet() {
    setState(() { _pendingBet = null; _betDeclined = true; });
    _addChat('You', 'Bet declined — playing clean.');
    final rng = Random();
    _showOpponentThinkingThenReply(() {
      if (_opponentName == null) return;
      final roll = rng.nextDouble();
      if (roll < 0.15) {
        // Rarely, the opponent gets annoyed and leaves entirely.
        final name = _opponentName!;
        _hostStartTimer?.cancel();
        setState(() { _opponentName = null; _pendingBet = null; _betDeclined = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name left the room. Searching for a new opponent...')),
        );
        _startSearch();
      } else if (roll < 0.40) {
        // Sometimes they try a different bet instead.
        final counter = FakeOnlineChallenge.fakeOpponentBetProposal();
        if (counter != null) {
          setState(() { _pendingBet = counter; _betProposedBy = 'opponent'; _betDeclined = false; });
          _addChat(_opponentName!, 'Fair. How about this instead: ${counter.description}');
        } else {
          _addChat(_opponentName!, 'No problem. Good luck anyway.');
        }
      } else {
        _addChat(_opponentName!, 'No problem. Good luck anyway.');
      }
    });
  }

  void _startMatch() {
    if (_opponentName == null) return;
    _hostStartTimer?.cancel();
    _netMonitorTimer?.cancel();
    // Record the free-daily-match usage HERE — the moment the match
    // actually begins — never when the screen was merely opened. Guarded
    // so a rare race between the manual button and the auto-start timer
    // can't burn two matches for one game.
    if (widget.countsAgainstDailyFree && !_dailyUsageRecorded) {
      _dailyUsageRecorded = true;
      DailyUsageService.recordOnlineUsage();
    }
    // Same reasoning for the free-trial match: only burn it once the user
    // is actually about to play (an opponent is confirmed and we're about
    // to open the match screen), never at the earlier "Start/Search" tap —
    // that tap doesn't guarantee an opponent is found.
    if (widget.trialMode && !_trialUsageRecorded) {
      _trialUsageRecorded = true;
      FreeTrialService.markOnlineTrialUsed();
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => OnlineChallengeMatchScreen(
          section: _section,
          randomMixSubject: _randomMixSubject,
          questionCount: _questionCount,
          questionTimeLimitSeconds: _questionTimerSeconds,
          opponentName: _opponentName!,
          bet: _betAccepted ? _pendingBet : null,
          opponentStartsFirst: _joinedExistingRoom,
        ),
      ),
    );
  }

  void _openActiveRooms() async {
    final joined = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const _ActiveRoomsScreen()),
    );
    if (joined == null || !mounted) return;
    // Joining someone else's room takes you to that host's lobby first —
    // same as hosting yourself, just from the other side. The host decides
    // whether to bring a bet, and can back out or remove you, before the
    // match actually begins.
    final started = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => _JoinRoomLobbyScreen(room: joined)),
    );
    if (started == null || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OnlineChallengeMatchScreen(
          section: joined['section'] as ActSection,
          randomMixSubject: joined['randomMix'] as bool? ?? false,
          questionCount: joined['questionCount'] as int,
          questionTimeLimitSeconds: joined['timerSeconds'] as int?,
          opponentName: joined['name'] as String,
          bet: started['bet'] as ChallengeBetProposal?,
          opponentStartsFirst: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final paused = _accessPauseUntil != null && _accessPauseUntil!.isAfter(DateTime.now());
    // A lost "study_task" bet blocks starting/joining another Online
    // Challenge match, same as an access-pause bet, until a practice
    // section is completed (see section_screen.dart's _finishSection).
    final blocked = paused || _practiceRequired;
    return Scaffold(
      appBar: AppBar(title: const Text('Online Challenge')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Activity status
            _ActivityBanner(isDark: isDark),
            const SizedBox(height: 12),

            // Browse active rooms — host-only during the free trial, so
            // joining someone else's room isn't available here.
            if (!widget.trialMode)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: (_setupLocked || blocked) ? null : _openActiveRooms,
                  icon: const Icon(Icons.groups_outlined, size: 18),
                  label: const Text('Browse Active Rooms', style: TextStyle(fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 13)),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: ActColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline, size: 16, color: ActColors.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    'Free trial: host a match of ${FreeTrialService.trialChallengeQuestionCount} questions. Joining is available with Online Challenge activation.',
                    style: TextStyle(fontSize: 11.5, color: ActColors.primary),
                  )),
                ]),
              ),
            const SizedBox(height: 16),

            if (paused) ...[
              _ErrorBanner(msg: 'Online Challenge access is paused until ${_accessPauseUntil!.hour.toString().padLeft(2, '0')}:${_accessPauseUntil!.minute.toString().padLeft(2, '0')} (bet outcome).'),
              const SizedBox(height: 16),
            ] else if (_practiceRequired) ...[
              _ErrorBanner(msg: 'You lost a bet that requires finishing one practice set before your next Online Challenge. Complete a practice section to unlock this.'),
              const SizedBox(height: 16),
            ],

            // Room selector
            _Label('Select Room'),
            IgnorePointer(
              ignoring: _setupLocked,
              child: Opacity(
                opacity: _setupLocked ? 0.5 : 1,
                child: Row(children: [
                  _RoomCard(title: 'USA Room', subtitle: 'US-based opponents', code: 'US',
                      isSelected: _region == OnlineChallengeRegion.usa,
                      onTap: () => setState(() => _region = OnlineChallengeRegion.usa), isDark: isDark),
                  const SizedBox(width: 12),
                  _RoomCard(title: 'Foreign Room', subtitle: 'International opponents', code: 'GL',
                      isSelected: _region == OnlineChallengeRegion.foreign,
                      onTap: () => setState(() => _region = OnlineChallengeRegion.foreign), isDark: isDark),
                ]),
              ),
            ),
            const SizedBox(height: 16),

            // Section
            _Label('ACT Section'),
            IgnorePointer(
              ignoring: _setupLocked,
              child: Opacity(
                opacity: _setupLocked ? 0.5 : 1,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                ]),
              ),
            ),
            const SizedBox(height: 6),
            _Label('Questions'),
            IgnorePointer(
              ignoring: _setupLocked || widget.trialMode,
              child: Opacity(
                opacity: (_setupLocked || widget.trialMode) ? 0.5 : 1,
                child: Wrap(spacing: 8, children: [10, 20, 30, 40].map((n) => ChoiceChip(
                  label: Text('$n'),
                  selected: _questionCount == n,
                  selectedColor: ActColors.primary,
                  labelStyle: TextStyle(color: _questionCount == n ? Colors.white : (context.isDark ? Colors.white : ActColors.charcoal), fontWeight: FontWeight.w600),
                  onSelected: (_) => setState(() => _questionCount = n),
                )).toList()),
              ),
            ),
            if (widget.trialMode)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Free trial matches are fixed at ${FreeTrialService.trialChallengeQuestionCount} questions.',
                    style: TextStyle(fontSize: 11, color: ActColors.midGray)),
              ),
            const SizedBox(height: 6),
            _Label('Time per Question (host sets this)'),
            IgnorePointer(
              ignoring: _setupLocked,
              child: Opacity(
                opacity: _setupLocked ? 0.5 : 1,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SwitchListTile(
                    value: !_noTimer,
                    onChanged: (v) => setState(() => _questionTimerSeconds = v ? (_questionTimerSeconds ?? 60) : null),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Use a per-question timer', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  if (!_noTimer) ...[
                    Row(children: [
                      Expanded(
                        child: Slider(
                          value: _questionTimerSeconds!.toDouble(),
                          min: 15,
                          max: 180, // 3 minutes — English/Reading passages need the room
                          divisions: 11, // 15s steps
                          activeColor: ActColors.primary,
                          label: _formatOnlineTimerLabel(_questionTimerSeconds!),
                          onChanged: (v) => setState(() => _questionTimerSeconds = v.round()),
                        ),
                      ),
                      SizedBox(
                        width: 52,
                        child: Text(_formatOnlineTimerLabel(_questionTimerSeconds!),
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: ActColors.primary)),
                      ),
                    ]),
                    Wrap(spacing: 8, children: [30, 60, 90, 120, 180].map((n) => ChoiceChip(
                      label: Text(_formatOnlineTimerLabel(n)),
                      selected: _questionTimerSeconds == n,
                      selectedColor: ActColors.primary,
                      labelStyle: TextStyle(color: _questionTimerSeconds == n ? Colors.white : (context.isDark ? Colors.white : ActColors.charcoal), fontWeight: FontWeight.w600, fontSize: 12),
                      onSelected: (_) => setState(() => _questionTimerSeconds = n),
                    )).toList()),
                  ],
                ]),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _questionTimerSeconds == null
                  ? 'No time limit — you and your opponent can take as long as you want on each question.'
                  : 'Whoever hasn\'t answered when the clock hits 0 is skipped and the match moves on immediately.',
              style: TextStyle(fontSize: 10.5, color: ActColors.midGray),
            ),
            const SizedBox(height: 24),

            // Match state
            if (_opponentName == null) ...[
              if (_searching)
                _SearchingWidget(status: _statusMsg, onCancel: () {
                  _matchSub?.cancel();
                  setState(() { _searching = false; _statusMsg = ''; });
                })
              else ...[
                if (_statusMsg.isNotEmpty) _ErrorBanner(msg: _statusMsg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: ActColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.public),
                    label: const Text('Find Opponent', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    onPressed: blocked ? null : _startSearch,
                  ),
                ),
              ],
            ] else ...[
              // Opponent card
              if (!_netOk) ...[
                _ErrorBanner(msg: 'No internet connection. Everything here is paused until it comes back.'),
                const SizedBox(height: 10),
              ],
              _MatchedCard(
                opponentName: _opponentName!,
                pendingBet: (_pendingBet != null && !_betAccepted && !_betDeclined) ? _pendingBet : null,
                proposedByMe: _betProposedBy == 'me',
                activeBet: _betAccepted ? _pendingBet : null,
                onAcceptBet: _netOk ? _acceptBet : () {},
                onDeclineBet: _netOk ? _declineBet : () {},
                onRemoveOpponent: _removeOpponentAndResearch,
                isDark: isDark,
              ),
              const SizedBox(height: 10),

              // Host auto-start countdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: ActColors.warning.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Icon(Icons.timer_outlined, size: 14, color: ActColors.warning),
                  const SizedBox(width: 6),
                  Expanded(child: Text(
                    'Auto-starts in ${_hostStartSecondsLeft ~/ 60}:${(_hostStartSecondsLeft % 60).toString().padLeft(2, '0')} if you don\'t begin',
                    style: TextStyle(fontSize: 11, color: ActColors.warning, fontWeight: FontWeight.w600),
                  )),
                ]),
              ),
              const SizedBox(height: 12),

              // Host may propose a bet (only when they haven't already)
              if (_pendingBet == null && !_betAccepted)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _hostProposeRandomBet,
                    icon: const Icon(Icons.casino_outlined, size: 16),
                    label: const Text('Propose a Random Bet'),
                  ),
                ),
              const SizedBox(height: 10),

              // Chat
              _Label('Pre-Match Chat'),
              _ChatBox(
                messages: _chatMessages,
                controller: _chatCtrl,
                scrollCtrl: _chatScrollCtrl,
                onSend: _sendChat,
                isDark: isDark,
                opponentTyping: _opponentTyping,
                opponentName: _opponentName!,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: ActColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _netOk ? _startMatch : null,
                  child: const Text('Start Challenge', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ── Active Rooms directory ─────────────────────────────────────────────────────
// A browsable list of other "in-progress" rooms, simulated client-side (there
// is no live backend here — see fake_online_challenge.dart). Rooms that are
// actually joinable ("waiting for opponent") are sorted to the top; rooms
// that are mid-match or waiting on a disconnected player are shown below,
// for flavor, but can't be joined.
enum _RoomState { waiting, playing, rejoinWait }

class _RoomInfo {
  final String name;
  final ActSection section;
  final bool randomMix;
  final int questionCount;
  final OnlineChallengeRegion region;
  final int? timerSeconds; // null = no per-question timer in this room
  _RoomState state;
  _RoomInfo({
    required this.name,
    required this.section,
    required this.randomMix,
    required this.questionCount,
    required this.region,
    required this.timerSeconds,
    required this.state,
  });
}

class _ActiveRoomsScreen extends StatefulWidget {
  const _ActiveRoomsScreen();
  @override
  State<_ActiveRoomsScreen> createState() => _ActiveRoomsScreenState();
}

class _ActiveRoomsScreenState extends State<_ActiveRoomsScreen> {
  final _rng = Random();
  List<_RoomInfo> _rooms = [];
  bool _joining = false;
  // Room browsing is still "online" — it shouldn't show a list of rooms
  // (fake or not) or let anyone tap Join if there's no real internet.
  bool _checkingNet = true;
  bool _netOk = true;

  @override
  void initState() {
    super.initState();
    _checkNetThenLoad();
  }

  Future<void> _checkNetThenLoad() async {
    final ok = await FakeOnlineChallenge.hasRealInternet(timeout: const Duration(seconds: 4));
    if (!mounted) return;
    setState(() {
      _checkingNet = false;
      _netOk = ok;
      if (ok) _rooms = _generateRooms();
    });
  }

  List<_RoomInfo> _generateRooms() {
    final count = 8 + _rng.nextInt(8); // 8-15 rooms
    final names = FakeOnlineChallenge.sampleRoomNames(count);
    final states = [
      ..._RoomState.values, // ensure at least one of each appears
    ];
    return List.generate(count, (i) {
      final state = i < states.length
          ? states[i]
          : _RoomState.values[_rng.nextInt(_RoomState.values.length)];
      return _RoomInfo(
        name: names[i],
        section: ActSection.values[_rng.nextInt(ActSection.values.length)],
        randomMix: _rng.nextDouble() < 0.25,
        questionCount: [10, 20, 30, 40][_rng.nextInt(4)],
        region: _rng.nextBool() ? OnlineChallengeRegion.usa : OnlineChallengeRegion.foreign,
        timerSeconds: [null, 30, 45, 60, 90, 120, 180][_rng.nextInt(7)],
        state: state,
      );
    })..sort((a, b) {
        int rank(_RoomState s) => s == _RoomState.waiting ? 0 : (s == _RoomState.playing ? 1 : 2);
        return rank(a.state).compareTo(rank(b.state));
      });
  }

  Future<void> _tryJoin(_RoomInfo room) async {
    if (_joining || room.state != _RoomState.waiting) return;
    // Re-check right before joining too — internet could have dropped
    // while the person was just browsing the list.
    final stillOk = await FakeOnlineChallenge.hasRealInternet(timeout: const Duration(seconds: 4));
    if (!mounted) return;
    if (!stillOk) {
      setState(() => _netOk = false);
      return;
    }
    setState(() => _joining = true);

    // Simulate realistic network/matchmaking delay
    await Future.delayed(Duration(milliseconds: 500 + _rng.nextInt(900)));
    if (!mounted) return;

    // Human behaviour: sometimes another player beats you to this room.
    if (_rng.nextDouble() < 0.25) {
      setState(() {
        room.state = _RoomState.playing;
        _rooms.sort((a, b) {
          int rank(_RoomState s) => s == _RoomState.waiting ? 0 : (s == _RoomState.playing ? 1 : 2);
          return rank(a.state).compareTo(rank(b.state));
        });
        _joining = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Someone else just joined ${room.name}\'s room. Try another.')),
      );
      return;
    }

    if (!mounted) return;
    Navigator.pop(context, {
      'name': room.name,
      'section': room.section,
      'randomMix': room.randomMix,
      'questionCount': room.questionCount,
      'timerSeconds': room.timerSeconds,
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Active Rooms')),
      body: _checkingNet
          ? const Center(child: CircularProgressIndicator())
          : !_netOk
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.wifi_off, size: 40, color: ActColors.danger),
                      const SizedBox(height: 14),
                      const Text('No internet connection detected',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15), textAlign: TextAlign.center),
                      const SizedBox(height: 6),
                      Text('Online Challenge needs a real internet connection — rooms can\'t load without one.',
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: ActColors.midGray)),
                      const SizedBox(height: 16),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: ActColors.primary),
                        onPressed: () => setState(() { _checkingNet = true; _checkNetThenLoad(); }),
                        child: const Text('Try Again'),
                      ),
                    ]),
                  ),
                )
              : ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _rooms.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final r = _rooms[i];
          final joinable = r.state == _RoomState.waiting;
          String stateLabel;
          Color stateColor;
          switch (r.state) {
            case _RoomState.waiting:
              stateLabel = 'Waiting for opponent';
              stateColor = ActColors.success;
              break;
            case _RoomState.playing:
              stateLabel = 'Match in progress';
              stateColor = ActColors.info;
              break;
            case _RoomState.rejoinWait:
              stateLabel = 'Waiting for player to rejoin';
              stateColor = ActColors.warning;
              break;
          }
          return Opacity(
            opacity: joinable ? 1 : 0.55,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? ActColors.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: stateColor.withOpacity(0.25)),
              ),
              child: Row(children: [
                CircleAvatar(radius: 18, backgroundColor: ActColors.primary,
                    child: Text(r.name.substring(0, 1).toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(
                      '${r.randomMix ? "Random Mix" : actSectionDisplayName(r.section)} · ${r.questionCount}Q · ${r.region == OnlineChallengeRegion.usa ? "USA" : "Foreign"} · ${r.timerSeconds == null ? "No timer" : "${_formatOnlineTimerLabel(r.timerSeconds!)}/question"}',
                      style: TextStyle(fontSize: 11, color: ActColors.midGray),
                    ),
                    const SizedBox(height: 4),
                    Row(children: [
                      Icon(Icons.circle, size: 8, color: stateColor),
                      const SizedBox(width: 4),
                      Text(stateLabel, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: stateColor)),
                    ]),
                  ]),
                ),
                if (joinable)
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: ActColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                    onPressed: _joining ? null : () => _tryJoin(r),
                    child: const Text('Join', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

// ── Join Room lobby ─────────────────────────────────────────────────────────
// When you join someone else's room, you land here first — same idea as the
// host's matched-card screen, just from the other side. The host (bot)
// decides whether to bring a bet, can back out entirely, and controls when
// the match actually begins (capped at 2 minutes, same as hosting).
class _JoinRoomLobbyScreen extends StatefulWidget {
  final Map<String, dynamic> room;
  const _JoinRoomLobbyScreen({required this.room});
  @override
  State<_JoinRoomLobbyScreen> createState() => _JoinRoomLobbyScreenState();
}

class _JoinRoomLobbyScreenState extends State<_JoinRoomLobbyScreen> {
  final List<Map<String, dynamic>> _chatMessages = [];
  final _chatCtrl = TextEditingController();
  final _chatScrollCtrl = ScrollController();
  bool _opponentTyping = false;

  ChallengeBetProposal? _pendingBet;
  bool _betResolvedByHost = false; // host proposed & joiner responded (or no bet at all)
  bool _betAccepted = false;

  Timer? _startTimer;
  int _secondsUntilStart = 0;
  bool _removed = false; // host kicked the joiner

  // Same real-internet monitoring as the host-side lobby — chatting and
  // negotiating a bet here is just as much "online" activity as answering
  // questions later is, so it shouldn't be exempt from the check either.
  Timer? _netMonitorTimer;
  bool _netOk = true;

  String get _hostName => widget.room['name'] as String;

  @override
  void initState() {
    super.initState();
    final rng = Random();
    _addChat(_hostName, FakeOnlineChallenge.opponentOpeningMessage(_hostName));
    _startNetMonitor();

    // Host decides whether to bring a bet into their room. This relies on
    // fakeOpponentBetProposal()'s own probability (55-90% depending on
    // activity) rather than an extra coin-flip here — two stacked "maybe
    // not" checks were making bets show up far too rarely to ever notice.
    Future.delayed(Duration(seconds: 2 + rng.nextInt(4)), () {
      if (!mounted) return;
      final bet = FakeOnlineChallenge.fakeOpponentBetProposal();
      if (bet != null) {
        setState(() => _pendingBet = bet);
        _addChat(_hostName, 'Bet proposal: ${bet.description}');
      } else {
        setState(() => _betResolvedByHost = true);
      }
    });

    // Host starts the match somewhere between 20s and 2 minutes from now —
    // if they never actively start it, it proceeds automatically at the cap.
    _secondsUntilStart = 20 + rng.nextInt(101); // 20–120s
    _startTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _secondsUntilStart--);

      // Rare human behaviour: host loses interest and removes you before
      // the match even starts. This runs the same whether or not you're
      // currently connected — a real host doesn't know or care why you've
      // gone quiet, they just see no response and eventually give up (see
      // _startNetMonitor below for the disconnect-specific version of this).
      if (_secondsUntilStart > 5 && !_removed && rng.nextDouble() < 0.008) {
        t.cancel();
        _hostRemovesJoiner();
        return;
      }

      if (_secondsUntilStart <= 0) {
        t.cancel();
        _resolveAndStart();
      }
    });
  }

  void _startNetMonitor() {
    _netMonitorTimer?.cancel();
    _netOk = true;
    // Same 2s cadence as the host-side lobby, and the same idea: the
    // auto-start countdown above keeps running the whole time (a real
    // host doesn't pause their clock just because you went quiet), and
    // the longer you stay disconnected, the more likely the host gives up
    // and leaves before you ever reconnect — same escalating odds as the
    // host lobby's version of this.
    final rng = Random();
    int lostStreak = 0;
    _netMonitorTimer = Timer.periodic(const Duration(seconds: 2), (t) async {
      if (!mounted || _removed) { t.cancel(); return; }
      final ok = await FakeOnlineChallenge.hasRealInternet(timeout: const Duration(seconds: 4));
      if (!mounted) return;
      if (!ok) {
        lostStreak++;
        if (!_netOk) {
          // already showing the banner
        } else {
          setState(() => _netOk = false);
        }
        if (lostStreak > 3) {
          final leaveChance = (0.12 + (lostStreak - 3) * 0.08).clamp(0.0, 0.7);
          if (rng.nextDouble() < leaveChance) {
            t.cancel();
            _hostRemovesJoiner(disconnected: true);
            return;
          }
        }
      } else {
        if (_netOk == false) setState(() => _netOk = true);
        lostStreak = 0;
      }
    });
  }

  @override
  void dispose() {
    _startTimer?.cancel();
    _netMonitorTimer?.cancel();
    _chatCtrl.dispose();
    _chatScrollCtrl.dispose();
    super.dispose();
  }

  void _hostRemovesJoiner({bool disconnected = false}) {
    if (!mounted || _removed) return;
    _startTimer?.cancel();
    _netMonitorTimer?.cancel();
    setState(() => _removed = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(disconnected
          ? '$_hostName left — your connection dropped for too long.'
          : '$_hostName removed you from the room.')),
    );
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) Navigator.pop(context); // back to Active Rooms, no match
    });
  }

  void _addChat(String sender, String text) {
    if (!mounted) return;
    setState(() => _chatMessages.add({'sender': sender, 'text': text}));
    Future.delayed(const Duration(milliseconds: 80), () {
      if (_chatScrollCtrl.hasClients) {
        _chatScrollCtrl.animateTo(_chatScrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  void _sendChat() {
    final text = _chatCtrl.text.trim();
    if (text.isEmpty) return;
    _addChat('You', text);
    _chatCtrl.clear();
    final rng = Random();
    if (rng.nextDouble() < 0.22) return; // sometimes no reply at all
    Future.delayed(Duration(milliseconds: 500 + rng.nextInt(900)), () {
      if (!mounted) return;
      setState(() => _opponentTyping = true);
      Future.delayed(Duration(seconds: 2 + rng.nextInt(5)), () {
        if (!mounted) return;
        setState(() => _opponentTyping = false);
        _addChat(_hostName, FakeOnlineChallenge.randomChatReply());
      });
    });
  }

  // Same "thinking, then typing" pause used for regular chat, applied to
  // bet decisions too — a real host doesn't reply to Accept/Decline instantly.
  void _showOpponentThinkingThenReply(VoidCallback onReply) {
    final rng = Random();
    Future.delayed(Duration(seconds: 1 + rng.nextInt(3)), () {
      if (!mounted) return;
      setState(() => _opponentTyping = true);
      Future.delayed(Duration(milliseconds: 700 + rng.nextInt(1800)), () {
        if (!mounted) return;
        setState(() => _opponentTyping = false);
        onReply();
      });
    });
  }

  void _acceptBet() {
    setState(() { _betAccepted = true; _betResolvedByHost = true; });
    _addChat('You', 'Bet accepted.');
    _showOpponentThinkingThenReply(() => _addChat(_hostName, "Let's go then!"));
  }

  void _declineBet() {
    setState(() { _pendingBet = null; _betResolvedByHost = true; });
    _addChat('You', 'Bet declined — playing clean.');
    final rng = Random();
    _showOpponentThinkingThenReply(() {
      final roll = rng.nextDouble();
      if (roll < 0.12) {
        _hostRemovesJoiner();
      } else if (roll < 0.35) {
        final counter = FakeOnlineChallenge.fakeOpponentBetProposal();
        if (counter != null) {
          setState(() { _pendingBet = counter; _betResolvedByHost = false; });
          _addChat(_hostName, 'Fair. How about this instead: ${counter.description}');
        } else {
          _addChat(_hostName, 'No worries, good luck.');
        }
      } else {
        _addChat(_hostName, 'No worries, good luck.');
      }
    });
  }

  void _resolveAndStart() {
    if (!mounted || _removed) return;
    // If a bet is still hanging when time's up, treat it as declined —
    // real matches don't wait forever on a bet negotiation.
    Navigator.pop(context, {'bet': _betAccepted ? _pendingBet : null});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final waitingOnBet = _pendingBet != null && !_betResolvedByHost;
    return Scaffold(
      appBar: AppBar(title: Text('$_hostName\'s Room')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          if (!_netOk) ...[
            _ErrorBanner(msg: 'No internet connection. Everything here is paused until it comes back.'),
            const SizedBox(height: 12),
          ],
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: ActColors.info.withOpacity(0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ActColors.info.withOpacity(0.22)),
            ),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _PlayerPill(name: 'You', isUser: true),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('VS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: ActColors.primary))),
                _PlayerPill(name: _hostName, isUser: false),
              ]),
              const SizedBox(height: 10),
              Text(
                '${(widget.room['randomMix'] as bool? ?? false) ? "Random Mix" : actSectionDisplayName(widget.room['section'] as ActSection)} · ${widget.room['questionCount']}Q · ${widget.room['timerSeconds'] == null ? "No timer" : "${_formatOnlineTimerLabel(widget.room['timerSeconds'] as int)}/question"}',
                style: TextStyle(fontSize: 11.5, color: ActColors.midGray, fontWeight: FontWeight.w600),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          if (_pendingBet != null && !_betAccepted) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: ActColors.warning.withOpacity(0.10), borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: ActColors.warning.withOpacity(0.28))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$_hostName proposes a bet:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: ActColors.warning)),
                const SizedBox(height: 5),
                Text(_pendingBet!.description, style: const TextStyle(fontSize: 13, height: 1.4)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: ActColors.danger, side: BorderSide(color: ActColors.danger.withOpacity(0.5))),
                    onPressed: _netOk ? _declineBet : null, child: const Text('Decline'))),
                  const SizedBox(width: 10),
                  Expanded(child: FilledButton(style: FilledButton.styleFrom(backgroundColor: ActColors.warning),
                      onPressed: _netOk ? _acceptBet : null, child: const Text('Accept', style: TextStyle(color: Colors.white)))),
                ]),
              ]),
            ),
            const SizedBox(height: 14),
          ] else if (_betAccepted) ...[
            Text('Active bet: ${_pendingBet?.description ?? ""}', style: TextStyle(fontSize: 11, color: ActColors.warning, fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
          ],

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: ActColors.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Icon(Icons.timer_outlined, size: 14, color: ActColors.primary),
              const SizedBox(width: 6),
              Expanded(child: Text(
                waitingOnBet
                    ? 'Waiting on the bet before $_hostName starts...'
                    : '$_hostName starts the match in ${_secondsUntilStart}s (or sooner)',
                style: TextStyle(fontSize: 11, color: ActColors.primary, fontWeight: FontWeight.w600),
              )),
            ]),
          ),
          const SizedBox(height: 14),

          _Label('Pre-Match Chat'),
          _ChatBox(
            messages: _chatMessages,
            controller: _chatCtrl,
            scrollCtrl: _chatScrollCtrl,
            onSend: _sendChat,
            isDark: isDark,
            opponentTyping: _opponentTyping,
            opponentName: _hostName,
          ),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.exit_to_app, size: 16, color: ActColors.danger),
            label: Text('Leave Room', style: TextStyle(fontSize: 12, color: ActColors.danger)),
          ),
        ]),
      ),
    );
  }
}

// ── Live match screen ─────────────────────────────────────────────────────────
enum _MatchPhase { myTurn, opponentThinking, opponentAfk, finished }

class OnlineChallengeMatchScreen extends StatefulWidget {
  final ActSection section;
  final bool randomMixSubject;
  final int questionCount;
  // null = no per-question timer (unlimited thinking time per question)
  final int? questionTimeLimitSeconds;
  final String opponentName;
  final ChallengeBetProposal? bet;
  // True when the user joined someone else's already-running room instead
  // of hosting their own — in that case the opponent (host) is treated as
  // already under way, the opposite of the normal "you set up, opponent
  // joins you" flow.
  final bool opponentStartsFirst;

  const OnlineChallengeMatchScreen({
    super.key,
    required this.section,
    this.randomMixSubject = false,
    required this.questionCount,
    this.questionTimeLimitSeconds,
    required this.opponentName,
    this.bet,
    this.opponentStartsFirst = false,
  });

  @override
  State<OnlineChallengeMatchScreen> createState() => _OnlineChallengeMatchScreenState();
}

class _OnlineChallengeMatchScreenState extends State<OnlineChallengeMatchScreen> {
  late List<ActQuestion> _questions;
  int _qIndex = 0;
  final Map<int, String> _myAnswers = {};
  String? _selected;
  bool _showFeedback = false;
  bool _finished = false;
  bool _quitEarly = false;
  bool _calcVisible = false;

  // Opponent state
  _MatchPhase _phase = _MatchPhase.opponentThinking;
  int _opponentAnswered = 0;
  int _opponentCorrect = 0;
  int _opponentAfkSec = 0;
  bool _myTurnDone = false;
  bool _opponentDone = false;
  StreamSubscription<OpponentEvent>? _opponentSub;
  late final int _opponentSessionId;
  String _opponentStatus = 'Thinking...';

  // Per-question timer (player's own)
  Timer? _questionTimer;
  int _questionSecondsLeft = 90;
  bool _roundAdvancing = false;

  // Overall match timer (safety net)
  Timer? _matchTimer;
  int _matchSecondsLeft = 0;

  // Disconnect
  Timer? _connectivityTimer;
  Timer? _disconnectTimer;
  bool _disconnectWarning = false;
  int _disconnectSec = 25;

  // Voice
  bool _voiceEnabled = false;
  final FocusNode _focusNode = FocusNode();

  int get _myCorrectSoFar => _myAnswers.entries.where((e) {
        final qi = e.key;
        return qi < _questions.length && e.value == _questions[qi].correctAnswer;
      }).length;

  @override
  void initState() {
    super.initState();
    _opponentSessionId = FakeOnlineChallenge.startOpponentSession();
    _buildQuestions();
    // When joining someone else's room, the host has already been playing.
    // This used to also fake-seed _opponentAnswered/_opponentCorrect ahead
    // by 1-2, which meant that counter stayed permanently 1-2 higher than
    // your own current question for the rest of the match — e.g. showing
    // "opponent: 4/20" while you're still on Q2. That's exactly the mismatch
    // that made the numbers look broken/inconsistent, so it's gone now —
    // only the flavor text stays, and the counters start in sync at zero
    // like everything else.
    if (widget.opponentStartsFirst) {
      _opponentStatus = '${widget.opponentName} already started — catching up...';
    }
    _startMatchTimer();
    _startConnectivityMonitor();
    _loadVoice();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
    _beginRound();
  }

  void _buildQuestions() {
    final pool = widget.randomMixSubject ? questionsForRandomMix() : questionsForSection(widget.section);
    final shuffled = List.from(pool)..shuffle(Random());
    _questions = shuffled.take(widget.questionCount).cast<ActQuestion>().toList();
    _matchSecondsLeft = _questions.length * (widget.questionTimeLimitSeconds ?? 90);
  }

  Future<void> _loadVoice() async {
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

  void _startMatchTimer() {
    _matchTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _finished || _disconnectWarning) return; // frozen while offline
      setState(() => _matchSecondsLeft--);
      if (_matchSecondsLeft <= 0) _finishMatch();
    });
  }

  void _beginRound() {
    _selected = _myAnswers[_qIndex];
    _showFeedback = _myAnswers.containsKey(_qIndex);
    _myTurnDone = _myAnswers.containsKey(_qIndex);
    _opponentDone = false;
    _roundAdvancing = false;
    _phase = _MatchPhase.myTurn;
    _questionSecondsLeft = widget.questionTimeLimitSeconds ?? 0;

    // Start per-question timer (only if the host configured one for this
    // room). If it runs out, whichever side hasn't answered yet — me,
    // the opponent, or both — is skipped immediately and the match moves
    // straight on to the next question. No waiting, no manual button.
    _questionTimer?.cancel();
    if (widget.questionTimeLimitSeconds != null) {
      _questionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _roundAdvancing || _disconnectWarning) return; // frozen while offline
        setState(() => _questionSecondsLeft--);
        if (_questionSecondsLeft <= 0) {
          _forceAdvanceOnTimeout();
        }
      });
    } else {
      // Host chose "No timer" — unlimited thinking time for the player, but
      // the round still can't wait forever: if the opponent simulation ever
      // stalls beyond a generous ceiling, this hard safety net force-skips
      // whichever side hasn't answered so the match always keeps moving.
      _questionSecondsLeft = _kNoTimerSafetyNetSeconds;
      _questionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _roundAdvancing || _disconnectWarning) return;
        _questionSecondsLeft--;
        if (_questionSecondsLeft <= 0) _forceAdvanceOnTimeout();
      });
    }

    // Start opponent for this question
    _startOpponentForQuestion(_qIndex);
  }

  // Even with "No timer" selected, a round is never allowed to sit and wait
  // forever — this is the outer ceiling that guarantees the match keeps
  // moving no matter what.
  static const int _kNoTimerSafetyNetSeconds = 150;

  void _forceAdvanceOnTimeout() {
    // NOTE: this used to set _roundAdvancing = true here before calling
    // _maybeAdvance() below. That was the actual bug behind matches getting
    // permanently stuck: _maybeAdvance()'s very first check is "if
    // _roundAdvancing is already true, do nothing" — so setting it true
    // right before calling _maybeAdvance() made it bail out immediately,
    // every time, without ever scheduling the move to the next question.
    // _roundAdvancing only ever gets reset in _nextQuestion(), which this
    // was preventing from ever running — so the question (and everything
    // after it) froze for good. _maybeAdvance() already sets _roundAdvancing
    // itself right before it schedules _nextQuestion, so it doesn't need to
    // be set here too.
    _questionTimer?.cancel();
    if (!_myTurnDone) {
      _myAnswers[_qIndex] = ''; // skipped — time's up
      _myTurnDone = true;
    }
    if (!_opponentDone) {
      _opponentSub?.cancel();
      _opponentDone = true;
      // This used to just flip _opponentDone to true without ever counting
      // the round for the opponent — meaning every time the clock forced a
      // question through, the opponent's own "answered" tally silently fell
      // one behind the question you were both actually on. Over a match
      // with several timeouts that's exactly how you'd end up seeing e.g.
      // "opponent: 3/20" while you're already on question 6 — their number
      // gets stuck while yours keeps climbing. Counting it here (as a miss,
      // most of the time — but see below) keeps both tallies matched to
      // the question index at all times, the same way yours already is.
      _opponentAnswered = (_opponentAnswered + 1).clamp(0, _questions.length);
      final rng = Random();
      // Real opponents don't always miss a deadline cleanly either —
      // sometimes they were mid-answer and technically got it in right at
      // the buzzer. Small chance of that instead of a flat miss every time.
      final squeakedIn = rng.nextDouble() < 0.30;
      if (squeakedIn && rng.nextDouble() < 0.55) {
        _opponentCorrect = (_opponentCorrect + 1).clamp(0, _opponentAnswered);
      }
      if (mounted) {
        setState(() => _opponentStatus = squeakedIn
            ? '${widget.opponentName} just got it in at the last second'
            : '${widget.opponentName} ran out of time');
      }
    }
    _maybeAdvance();
  }

  void _startOpponentForQuestion(int qIdx) {
    _opponentSub?.cancel();
    final stream = FakeOnlineChallenge.opponentAnswerForQuestion(
      sessionId: _opponentSessionId,
      qIndex: qIdx,
      totalQuestions: widget.questionCount,
    );

    _opponentSub = stream.listen((event) {
      if (!mounted || _finished) return;
      if (event.questionIndex != null && event.questionIndex != qIdx) return;

      if (event.isThinking) {
        if (mounted) setState(() {
          _phase = _MatchPhase.opponentThinking;
          _opponentStatus = '${widget.opponentName} is thinking...';
        });
      } else if (event.isAfk) {
        if (mounted) setState(() {
          _phase = _MatchPhase.opponentAfk;
          _opponentAfkSec = event.afkSeconds!;
          _opponentStatus = '${widget.opponentName} stepped away briefly...';
        });
        _countAfk();
      } else if (event.isAnswered || event.isSkipped) {
        if (mounted) setState(() {
          // Each question is simulated fresh now, so we track progress
          // ourselves rather than trusting a counter from the stream.
          _opponentAnswered = (_opponentAnswered + 1).clamp(0, _questions.length);
          if (event.isAnswered && event.isCorrect == true) _opponentCorrect++;
          _opponentDone = true;
          _opponentStatus = event.isSkipped
              ? '${widget.opponentName} skipped this one'
              : '${widget.opponentName} answered';
          _phase = _MatchPhase.myTurn;
        });
        _opponentSub?.cancel();
        _maybeAdvance();
      } else if (event.isFinished) {
        _opponentSub?.cancel();
      }
    });
  }

  Timer? _afkCountTimer;
  void _countAfk() {
    _afkCountTimer?.cancel();
    _afkCountTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _opponentAfkSec = (_opponentAfkSec - 1).clamp(0, 999));
      if (_opponentAfkSec <= 0) {
        _afkCountTimer?.cancel();
        if (mounted) setState(() {
          _phase = _MatchPhase.opponentThinking;
          _opponentStatus = '${widget.opponentName} is back — thinking...';
        });
      }
    });
  }

  void _selectAnswer(String letter) {
    // Both players answer independently and simultaneously — selecting an
    // answer is never blocked by what the opponent is doing. The only thing
    // that locks your answer in is confirming it (or the timer running out).
    // While offline, everything freezes so a disconnect never costs you time.
    if (_showFeedback || _disconnectWarning) return;
    HapticFeedback.lightImpact();
    setState(() => _selected = letter);
  }

  void _confirmAnswer() {
    if (_selected == null || _showFeedback || _disconnectWarning) return;
    HapticFeedback.mediumImpact();
    _myAnswers[_qIndex] = _selected!;
    _myTurnDone = true;
    setState(() => _showFeedback = true);
    _questionTimer?.cancel();
    if (_voiceEnabled) {
      final q = _questions[_qIndex];
      VoiceService.instance.readText(
        _selected == q.correctAnswer ? 'Correct.' : 'Incorrect. The answer is ${q.correctAnswer}.',
      );
    }
    _maybeAdvance();
  }

  void _maybeAdvance() {
    if (_roundAdvancing || _disconnectWarning) return; // don't advance mid-outage
    if (_myTurnDone && _opponentDone) {
      _roundAdvancing = true;
      Future.delayed(const Duration(milliseconds: 900), _nextQuestion);
    }
  }

  void _nextQuestion() {
    if (_finished) return;
    if (_qIndex < _questions.length - 1) {
      setState(() {
        _qIndex++;
        _selected = null;
        _showFeedback = false;
        _myTurnDone = false;
        _opponentDone = false;
        _roundAdvancing = false;
      });
      _beginRound();
    } else {
      _finishMatch();
    }
  }

  void _finishMatch({bool quit = false}) {
    if (_finished) return;
    _finished = true;
    _quitEarly = quit;
    _matchTimer?.cancel();
    _questionTimer?.cancel();
    _opponentSub?.cancel();
    _connectivityTimer?.cancel();
    _disconnectTimer?.cancel();
    _afkCountTimer?.cancel();
    VoiceService.instance.stopReading();

    if (quit) {
      // Leaving early: never project a final score for either player — only
      // show what was actually completed up to the point of leaving.
      _saveAndNavigateQuitEarly();
      return;
    }

    final myCorrect = _myCorrectSoFar;
    final myAcc = _questions.isEmpty ? 0.0 : myCorrect / _questions.length;
    final myScore = (1 + myAcc * 35).clamp(1.0, 36.0);
    final opScore = FakeOnlineChallenge.simulateOpponentScore(_questions.length, myAcc);

    _saveAndNavigate(myScore, opScore, myAcc);
  }

  Future<void> _saveAndNavigateQuitEarly() async {
    final attemptedCount = _myAnswers.length;
    final myCorrect = _myCorrectSoFar;
    final oppAttempted = _opponentAnswered.clamp(0, _questions.length);

    final results = List.generate(_questions.length, (i) {
      final given = _myAnswers[i] ?? '';
      return QuestionResult(
        questionId: _questions[i].id,
        givenAnswer: given,
        isCorrect: given == _questions[i].correctAnswer,
        timeSpent: Duration.zero,
      );
    });
    final attempt = ExamAttempt(
      id: DateTime.now().toIso8601String(),
      startedAt: DateTime.now(),
      completedAt: DateTime.now(),
      setNumber: 1,
      section: widget.randomMixSubject ? null : widget.section,
      results: results,
    );
    // Save the partial attempt for the player's own history, but skip the
    // leaderboard — an incomplete match shouldn't count as a ranked score.
    await DatabaseService.instance.saveAttempt(attempt);
    final name = await UserProfileService.getDisplayName() ?? 'You';

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => _OnlineResultScreen(
          myName: name,
          opponentName: widget.opponentName,
          totalQuestions: _questions.length,
          myCorrect: myCorrect,
          quitEarly: true,
          myAnsweredCount: attemptedCount,
          opponentAnsweredCount: oppAttempted,
          opponentCorrect: _opponentCorrect,
        ),
      ),
    );
  }

  Future<void> _applyBetConsequence(bool iWon, bool tie) async {
    final bet = widget.bet;
    if (bet == null || tie) return;
    switch (bet.type) {
      case 'access':
        if (!iWon) {
          final match = RegExp(r'(\d+)_hours').firstMatch(bet.value);
          final hours = match != null ? int.tryParse(match.group(1)!) ?? 2 : 2;
          await UserProfileService.setOnlineAccessPauseUntil(DateTime.now().add(Duration(hours: hours)));
        }
        break;
      case 'study_task':
        if (!iWon) {
          await UserProfileService.setRequiresPracticeBeforeOnlineChallenge(true);
        }
        break;
      case 'ranking':
        {
          // Zero-sum: winner gains the points, loser loses the same amount.
          final match = RegExp(r'(\d+)_points').firstMatch(bet.value);
          final pts = match != null ? int.tryParse(match.group(1)!) ?? 1 : 1;
          await UserProfileService.addBetRankingPoints(iWon ? pts : -pts);
        }
        break;
      case 'badge':
        if (!iWon) {
          await UserProfileService.setChallengerBadgeSuspendedFor(const Duration(hours: 24));
        }
        break;
      case 'ranking_reset':
        if (!iWon) {
          ActLeaderboardService.activateTierDropForSession();
        }
        break;
      case 'bragging_rights':
        {
          final name = iWon
              ? (await UserProfileService.getDisplayName() ?? 'You')
              : widget.opponentName;
          await UserProfileService.setTopChallengerToday(name);
        }
        break;
    }
  }

  Future<void> _saveAndNavigate(double myScore, double opScore, double acc) async {
    final results = List.generate(_questions.length, (i) {
      final given = _myAnswers[i] ?? '';
      return QuestionResult(
        questionId: _questions[i].id,
        givenAnswer: given,
        isCorrect: given == _questions[i].correctAnswer,
        timeSpent: Duration.zero,
      );
    });
    final attempt = ExamAttempt(
      id: DateTime.now().toIso8601String(),
      startedAt: DateTime.now(),
      completedAt: DateTime.now(),
      setNumber: 1,
      section: widget.randomMixSubject ? null : widget.section,
      results: results,
    );
    await DatabaseService.instance.saveAttempt(attempt);
    // Only write once a real display name is known — a placeholder
    // fallback leaves a permanent duplicate "you" row on the leaderboard.
    final name = await UserProfileService.getDisplayName();
    if (name != null) {
      await DatabaseService.instance.upsertLeaderboardEntry(name, myScore, acc);
    }
    // Separate from the guarded write above: the result screen always
    // needs something non-null to display, even before a real name exists.
    final displayName = name ?? 'You';

    final tie = (myScore - opScore).abs() < 0.1;
    final iWon = myScore > opScore;
    await _applyBetConsequence(iWon, tie);

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => _OnlineResultScreen(
          myName: displayName,
          myScore: myScore,
          opponentName: widget.opponentName,
          opponentScore: opScore,
          totalQuestions: _questions.length,
          myCorrect: results.where((r) => r.isCorrect).length,
          bet: widget.bet,
        ),
      ),
    );
  }

  void _startConnectivityMonitor() {
    _connectivityTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
      if (!mounted || _finished) return;
      final ok = await FakeOnlineChallenge.hasRealInternet(timeout: const Duration(seconds: 4));
      if (!mounted) return;
      if (!ok) {
        _beginDisconnectCountdown();
      } else if (_disconnectWarning) {
        _disconnectTimer?.cancel();
        setState(() => _disconnectWarning = false);
        // Resume cleanly: if the opponent hadn't finished this question
        // before the outage, give them a fresh attempt at it now rather
        // than trying to resurrect a stream that was frozen mid-delay.
        if (!_opponentDone && !_finished) _startOpponentForQuestion(_qIndex);
      }
    });
  }

  void _beginDisconnectCountdown() {
    if (_disconnectWarning) return;
    setState(() { _disconnectWarning = true; _disconnectSec = 25; });
    // Freeze the opponent exactly where they are — no more "thinking" time
    // ticks by, and no answer can land, while you're offline. This is
    // resumed (or the round is re-simulated fresh) once you reconnect.
    _opponentSub?.cancel();
    _afkCountTimer?.cancel();
    _disconnectTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _disconnectSec--);
      if (_disconnectSec <= 0) { t.cancel(); _finishMatch(quit: true); }
    });
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.keyA || key == LogicalKeyboardKey.digit1) { _selectAnswer('A'); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.keyB || key == LogicalKeyboardKey.digit2) { _selectAnswer('B'); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.keyC || key == LogicalKeyboardKey.digit3) { _selectAnswer('C'); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.keyD || key == LogicalKeyboardKey.digit4) { _selectAnswer('D'); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) { _confirmAnswer(); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.escape) { _confirmExit(); return KeyEventResult.handled; }
    return KeyEventResult.ignored;
  }

  // True for the final 3 questions of a match that has an accepted bet
  // riding on it — this is the window where exiting is locked out so the
  // bet consequence can't be dodged by quitting just before losing.
  bool get _exitLockedByBet =>
      widget.bet != null && (_questions.length - _qIndex) <= 3;

  int get _questionsUntilExitUnlocked =>
      (_questions.length - _qIndex).clamp(0, 3);

  void _confirmExit() {
    // Once an accepted bet is on the line and the match is down to its
    // final 3 questions, quitting is locked out — it used to let a player
    // who was about to lose dodge the bet consequence entirely by exiting
    // right before the match ended (bet consequences were only ever
    // applied on a normal finish, never on a quit). Forcing the match out
    // this close to the end is what actually makes the bet consequence
    // enforceable.
    if (_exitLockedByBet) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('You have a bet riding on this match — you can\'t exit in the final $_questionsUntilExitUnlocked question${_questionsUntilExitUnlocked == 1 ? '' : 's'}.'),
      ));
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Exit Match?'),
        content: Text('${widget.opponentName} will be notified that you left. You\'ll only see your progress up to this question — not a final score.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Stay')),
          TextButton(
            onPressed: () { Navigator.pop(context); _finishMatch(quit: true); },
            child: Text('Exit', style: TextStyle(color: ActColors.danger)),
          ),
        ],
      ),
    );
  }

  String _formatTime(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _matchTimer?.cancel();
    _questionTimer?.cancel();
    _opponentSub?.cancel();
    _connectivityTimer?.cancel();
    _disconnectTimer?.cancel();
    _afkCountTimer?.cancel();
    _focusNode.dispose();
    VoiceService.instance.stopReading();
    FakeOnlineChallenge.endOpponentSession(_opponentSessionId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_questions.isEmpty) return const Scaffold(body: Center(child: Text('No questions available.')));
    final q = _questions[_qIndex];
    // Answering is never gated on the opponent's status — both of you are
    // working the same question at the same time, independently. This is
    // just "have I already locked in my answer for this question", and
    // freezes entirely while you're offline so a disconnect can't cost you.
    final myTurn = !_showFeedback && !_disconnectWarning;
    final currentSection = widget.randomMixSubject ? q.section : widget.section;
    final showCalcButton = currentSection == ActSection.math || currentSection == ActSection.science;

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKey,
      child: PopScope(
        canPop: false,
        onPopInvoked: (didPop) { if (!didPop) _confirmExit(); },
        child: Scaffold(
          appBar: AppBar(
            title: Text('${widget.randomMixSubject ? "Random Mix" : actSectionDisplayName(widget.section)} — Q${_qIndex + 1}/${_questions.length}'),
            leading: _exitLockedByBet
                ? Tooltip(
                    message: 'Exit locked — bet match, $_questionsUntilExitUnlocked question${_questionsUntilExitUnlocked == 1 ? '' : 's'} left',
                    child: IconButton(
                      icon: Badge(
                        label: Text('$_questionsUntilExitUnlocked'),
                        child: const Icon(Icons.lock_outline),
                      ),
                      onPressed: _confirmExit,
                    ),
                  )
                : IconButton(icon: const Icon(Icons.close), onPressed: _confirmExit),
            actions: [
              // Voice on/off — same toggle as Practice/Full Exam, in case the
              // user doesn't want questions/feedback read aloud during a match.
              IconButton(
                icon: Icon(_voiceEnabled ? Icons.volume_up : Icons.volume_off_outlined,
                    color: _voiceEnabled ? Colors.white : Colors.white60),
                tooltip: 'Voice Reading',
                onPressed: _toggleVoice,
              ),
              // Calculator (Math & Science only)
              if (showCalcButton)
                IconButton(
                  icon: Icon(_calcVisible ? Icons.calculate : Icons.calculate_outlined,
                      color: _calcVisible ? ActColors.accent : Colors.white70),
                  tooltip: 'Calculator',
                  onPressed: () => setState(() => _calcVisible = !_calcVisible),
                ),
              // Match timer
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: Text(
                    _formatTime(_matchSecondsLeft.clamp(0, 999999)),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          body: Stack(children: [
            Column(
            children: [
              // Live scoreboard — always visible at the top of the match
              _LiveScoreboard(
                myName: 'You',
                opponentName: widget.opponentName,
                myCorrect: _myCorrectSoFar,
                myAnswered: _myAnswers.length,
                opponentCorrect: _opponentCorrect,
                opponentAnswered: _opponentAnswered,
                isDark: isDark,
              ),

              // Progress bar
              LinearProgressIndicator(
                value: (_qIndex + 1) / _questions.length,
                color: ActColors.accent,
                backgroundColor: ActColors.accent.withOpacity(0.15),
                minHeight: 3,
              ),

              // Disconnect warning
              if (_disconnectWarning)
                _DisconnectBanner(secondsLeft: _disconnectSec),

              // Opponent status bar
              _OpponentStatusBar(
                name: widget.opponentName,
                status: _opponentStatus,
                answered: _opponentAnswered,
                total: _questions.length,
                phase: _phase,
                afkSec: _opponentAfkSec,
                isDark: isDark,
              ),

              // Turn / per-question timer banner
              _TurnBanner(
                myTurn: myTurn,
                showFeedback: _showFeedback,
                opponentName: widget.opponentName,
                questionSecondsLeft: _questionSecondsLeft,
                hasTimer: widget.questionTimeLimitSeconds != null,
                isDark: isDark,
              ),

              // Question
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (q.passageText != null) _PassageBox(text: q.passageText!, isDark: isDark),
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
                          onTap: myTurn ? () => _selectAnswer(letter) : null,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: bg,
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(color: border, width: (isSelected || (_showFeedback && isCorrect)) ? 1.8 : 1),
                            ),
                            child: Row(children: [
                              _OptionCircle(letter: letter, isSelected: isSelected, showFeedback: _showFeedback, isCorrect: isCorrect),
                              const SizedBox(width: 12),
                              Expanded(child: Text(q.options[i],
                                  style: TextStyle(fontSize: 13.5, height: 1.4, color: fg,
                                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal))),
                              if (!myTurn && !_showFeedback)
                                Icon(Icons.lock_outline, size: 14, color: ActColors.midGray),
                            ]),
                          ),
                        );
                      }),

                      if (_showFeedback) ...[
                        const SizedBox(height: 10),
                        _ExplanationBox(question: q, isDark: isDark),
                      ],
                    ],
                  ),
                ),
              ),

              // Bottom bar
              _MatchBottomBar(
                myTurn: myTurn,
                showFeedback: _showFeedback,
                selected: _selected,
                isLast: _qIndex == _questions.length - 1,
                onConfirm: _confirmAnswer,
              ),
            ],
            ),

            // Floating calculator overlay
            if (_calcVisible && showCalcButton)
              Positioned(
                right: 12,
                bottom: 80,
                child: MiniCalculatorOverlay(onClose: () => setState(() => _calcVisible = false)),
              ),
          ]),
        ),
      ),
    );
  }
}

// ── Result screen ─────────────────────────────────────────────────────────────
class _OnlineResultScreen extends StatelessWidget {
  final String myName, opponentName;
  final double? myScore, opponentScore;
  final int totalQuestions, myCorrect;
  final ChallengeBetProposal? bet;
  // Quit-early / disconnected path: no final score is ever shown, only
  // how far each player actually got before the match ended.
  final bool quitEarly;
  final int? myAnsweredCount;
  final int? opponentAnsweredCount;
  final int? opponentCorrect;

  const _OnlineResultScreen({
    required this.myName, required this.opponentName,
    this.myScore, this.opponentScore,
    required this.totalQuestions, required this.myCorrect,
    this.bet,
    this.quitEarly = false,
    this.myAnsweredCount,
    this.opponentAnsweredCount,
    this.opponentCorrect,
  });

  @override
  Widget build(BuildContext context) {
    if (quitEarly) return _buildQuitEarly(context);
    return _buildCompleted(context);
  }

  // ── Match ended early (you left, or disconnected) ─────────────────────────
  Widget _buildQuitEarly(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final myAnswered = myAnsweredCount ?? 0;
    final oppAnswered = opponentAnsweredCount ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Match Ended')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [ActColors.midGray, ActColors.primaryDark],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(children: [
              const Text('Match Ended Early', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(
                'No final score is shown for a match that wasn\'t completed — just how far each of you got.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.4),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: _ProgressPlayerCard(name: myName, isMe: true, answered: myAnswered, correct: myCorrect, total: totalQuestions)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('VS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: ActColors.primary)),
            ),
            Expanded(child: _ProgressPlayerCard(name: opponentName, isMe: false, answered: oppAnswered, correct: opponentCorrect, total: totalQuestions)),
          ]),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: ActColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
              child: const Text('Back to Home', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Match completed normally ──────────────────────────────────────────────
  Widget _buildCompleted(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final myScoreVal = myScore ?? 1.0;
    final opScoreVal = opponentScore ?? 1.0;
    final iWon = myScoreVal > opScoreVal;
    final tie  = (myScoreVal - opScoreVal).abs() < 0.1;
    final myColor = iWon ? ActColors.success : (tie ? ActColors.warning : ActColors.danger);
    final opColor = !iWon ? ActColors.success : (tie ? ActColors.warning : ActColors.danger);

    return Scaffold(
      appBar: AppBar(title: const Text('Match Result')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          // Outcome banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                iWon ? ActColors.success : (tie ? ActColors.warning : ActColors.danger),
                iWon ? const Color(0xFF1B7D4B) : (tie ? const Color(0xFFB8860B) : ActColors.primaryDark),
              ], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(children: [
              Text(
                tie ? 'It\'s a Tie' : (iWon ? 'You Won' : 'You Lost'),
                style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                FakeOnlineChallenge.opponentEndMessage(opponentWon: !iWon && !tie),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ]),
          ),
          const SizedBox(height: 24),

          // Score comparison
          Row(children: [
            _ResultPlayerCard(name: myName, score: myScoreVal, isMe: true, color: myColor, correct: myCorrect, total: totalQuestions),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('VS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: ActColors.primary)),
            ),
            _ResultPlayerCard(name: opponentName, score: opScoreVal, isMe: false, color: opColor, correct: null, total: totalQuestions),
          ]),

          // Bet outcome
          if (bet != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: ActColors.warning.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: ActColors.warning.withOpacity(0.25)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Bet Result', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: ActColors.warning)),
                const SizedBox(height: 6),
                Text(bet!.description, style: const TextStyle(fontSize: 12, height: 1.4)),
                const SizedBox(height: 8),
                Text(
                  iWon ? 'You win the bet.' : (tie ? 'Tie — no bet applied.' : '$opponentName wins the bet.'),
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13,
                    color: iWon ? ActColors.success : (tie ? ActColors.warning : ActColors.danger)),
                ),
                if (bet!.type == 'access' && !iWon && !tie) ...[
                  const SizedBox(height: 6),
                  Text('Your Online Challenge access is now paused for the agreed time.',
                      style: TextStyle(fontSize: 11, color: ActColors.danger)),
                ],
              ]),
            ),
          ],

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: ActColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
              child: const Text('Back to Home', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }
}

class _ProgressPlayerCard extends StatelessWidget {
  final String name;
  final bool isMe;
  final int answered;
  final int? correct;
  final int total;
  const _ProgressPlayerCard({required this.name, required this.isMe, required this.answered, this.correct, required this.total});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? ActColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ActColors.midGray.withOpacity(0.25)),
      ),
      child: Column(children: [
        CircleAvatar(radius: 20, backgroundColor: isMe ? ActColors.primary : ActColors.info,
            child: Text(name.substring(0, 1).toUpperCase(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16))),
        const SizedBox(height: 8),
        Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11), overflow: TextOverflow.ellipsis),
        const SizedBox(height: 6),
        Text('$answered', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: ActColors.midGray)),
        Text('of $total answered', style: TextStyle(fontSize: 10, color: ActColors.midGray)),
        if (correct != null) ...[
          const SizedBox(height: 4),
          Text('$correct correct', style: TextStyle(fontSize: 10, color: ActColors.midGray)),
        ],
      ]),
    );
  }
}

class _ResultPlayerCard extends StatelessWidget {
  final String name;
  final double score;
  final bool isMe;
  final Color color;
  final int? correct;
  final int total;
  const _ResultPlayerCard({required this.name, required this.score, required this.isMe, required this.color, this.correct, required this.total});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? ActColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(children: [
        CircleAvatar(radius: 20, backgroundColor: isMe ? ActColors.primary : ActColors.info,
            child: Text(name.substring(0, 1).toUpperCase(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16))),
        const SizedBox(height: 8),
        Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11), overflow: TextOverflow.ellipsis),
        const SizedBox(height: 6),
        Text(score.toStringAsFixed(1), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 26, color: color)),
        Text('/ 36', style: TextStyle(fontSize: 11, color: ActColors.midGray)),
        if (correct != null) Text('$correct/$total', style: TextStyle(fontSize: 10, color: ActColors.midGray)),
      ]),
    ));
  }
}

// ── Small helper widgets ──────────────────────────────────────────────────────
class _ActivityBanner extends StatelessWidget {
  final bool isDark;
  const _ActivityBanner({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final label = FakeOnlineChallenge.activityLabel();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: ActColors.info.withOpacity(0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ActColors.info.withOpacity(0.20)),
      ),
      child: Row(children: [
        Icon(Icons.circle, size: 9, color: ActColors.success),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87))),
      ]),
    );
  }
}

class _LiveScoreboard extends StatelessWidget {
  final String myName, opponentName;
  final int myCorrect, myAnswered, opponentCorrect, opponentAnswered;
  final bool isDark;
  const _LiveScoreboard({
    required this.myName, required this.opponentName,
    required this.myCorrect, required this.myAnswered,
    required this.opponentCorrect, required this.opponentAnswered,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: isDark ? ActColors.darkSurface : const Color(0xFFF3F3F3),
      child: Row(children: [
        Expanded(
          child: Row(children: [
            CircleAvatar(radius: 11, backgroundColor: ActColors.primary,
                child: Text(myName.substring(0, 1).toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800))),
            const SizedBox(width: 6),
            Flexible(child: Text(myName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 6),
            Text('$myCorrect/$myAnswered', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ActColors.primary)),
          ]),
        ),
        Text('VS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: ActColors.midGray)),
        Expanded(
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            Text('$opponentCorrect/$opponentAnswered', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ActColors.info)),
            const SizedBox(width: 6),
            Flexible(child: Text(opponentName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis, textAlign: TextAlign.right)),
            const SizedBox(width: 6),
            CircleAvatar(radius: 11, backgroundColor: ActColors.info,
                child: Text(opponentName.substring(0, 1).toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800))),
          ]),
        ),
      ]),
    );
  }
}

class _OpponentStatusBar extends StatelessWidget {
  final String name, status;
  final int answered, total, afkSec;
  final _MatchPhase phase;
  final bool isDark;
  const _OpponentStatusBar({required this.name, required this.status, required this.answered, required this.total, required this.phase, required this.afkSec, required this.isDark});

  @override
  Widget build(BuildContext context) {
    Color barColor;
    IconData icon;
    switch (phase) {
      case _MatchPhase.opponentAfk:
        barColor = ActColors.warning;
        icon = Icons.hourglass_empty_outlined;
        break;
      case _MatchPhase.myTurn:
        barColor = ActColors.success;
        icon = Icons.check_circle_outline;
        break;
      default:
        barColor = ActColors.info;
        icon = Icons.more_horiz;
    }
    final displayStatus = phase == _MatchPhase.opponentAfk
        ? '$name stepped away... back in ${afkSec}s'
        : status;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: barColor.withOpacity(0.07),
      child: Row(children: [
        Icon(icon, size: 15, color: barColor),
        const SizedBox(width: 8),
        Expanded(child: Text(displayStatus, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: barColor))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: barColor.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
          child: Text('$answered/$total', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: barColor)),
        ),
      ]),
    );
  }
}

class _TurnBanner extends StatelessWidget {
  final bool myTurn, showFeedback;
  final String opponentName;
  final int questionSecondsLeft;
  final bool hasTimer;
  final bool isDark;
  const _TurnBanner({required this.myTurn, required this.showFeedback, required this.opponentName, required this.questionSecondsLeft, this.hasTimer = true, required this.isDark});

  @override
  Widget build(BuildContext context) {
    if (showFeedback) return const SizedBox.shrink();
    final color = myTurn ? ActColors.primary : ActColors.midGray;
    final urgent = hasTimer && myTurn && questionSecondsLeft <= 15;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: (urgent ? ActColors.danger : color).withOpacity(0.07),
        border: Border(bottom: BorderSide(color: (urgent ? ActColors.danger : color).withOpacity(0.15))),
      ),
      child: Row(children: [
        Icon(myTurn ? Icons.bolt : Icons.hourglass_top_rounded,
            size: 15, color: urgent ? ActColors.danger : color),
        const SizedBox(width: 8),
        Expanded(child: Text(
          myTurn ? 'Answer now — no need to wait on $opponentName' : 'Waiting for $opponentName...',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
              color: urgent ? ActColors.danger : color),
        )),
        if (myTurn && hasTimer)
          Text('${questionSecondsLeft}s',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                  color: urgent ? ActColors.danger : color)),
      ]),
    );
  }
}

class _DisconnectBanner extends StatelessWidget {
  final int secondsLeft;
  const _DisconnectBanner({required this.secondsLeft});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    color: ActColors.danger.withOpacity(0.12),
    child: Row(children: [
      Icon(Icons.wifi_off, size: 16, color: ActColors.danger),
      const SizedBox(width: 8),
      Expanded(child: Text(
        'Connection lost — disconnecting in ${secondsLeft}s if not restored.',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ActColors.danger),
      )),
    ]),
  );
}

class _MatchBottomBar extends StatelessWidget {
  final bool myTurn, showFeedback, isLast;
  final String? selected;
  final VoidCallback onConfirm;
  const _MatchBottomBar({required this.myTurn, required this.showFeedback, required this.selected, required this.isLast, required this.onConfirm});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
    decoration: BoxDecoration(
      color: Theme.of(context).scaffoldBackgroundColor,
      border: Border(top: BorderSide(color: ActColors.lightBorder)),
    ),
    child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
      if (!showFeedback)
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: ActColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: (myTurn && selected != null) ? onConfirm : null,
          child: const Text('Confirm', style: TextStyle(fontWeight: FontWeight.w700)),
        )
      else
        // No manual "Next" button — this is a live match, so as soon as both
        // sides are done (or time runs out) it moves on by itself.
        Expanded(
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: ActColors.primary)),
            const SizedBox(width: 10),
            Text(
              isLast ? 'Finishing up...' : 'Moving to the next question...',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: ActColors.midGray),
            ),
          ]),
        ),
    ]),
  );
}

class _OptionCircle extends StatelessWidget {
  final String letter;
  final bool isSelected, showFeedback, isCorrect;
  const _OptionCircle({required this.letter, required this.isSelected, required this.showFeedback, required this.isCorrect});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Color bg = isDark ? ActColors.darkSurface : const Color(0xFFF0F0F0);
    Color fg = isDark ? Colors.white70 : Colors.black87;
    if (isSelected && !showFeedback) { bg = ActColors.primary; fg = Colors.white; }
    if (showFeedback && isCorrect) { bg = ActColors.success; fg = Colors.white; }
    if (showFeedback && isSelected && !isCorrect) { bg = ActColors.danger; fg = Colors.white; }
    return Container(
      width: 28, height: 28,
      decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
      child: Center(child: Text(letter, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: fg))),
    );
  }
}

class _PassageBox extends StatelessWidget {
  final String text;
  final bool isDark;
  const _PassageBox({required this.text, required this.isDark});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(13),
    margin: const EdgeInsets.only(bottom: 14),
    decoration: BoxDecoration(
      color: isDark ? ActColors.darkSurface : const Color(0xFFF9F9F9),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: isDark ? ActColors.darkBorder : ActColors.lightBorder),
    ),
    child: Text(text, style: TextStyle(fontSize: 13, height: 1.55, color: isDark ? Colors.white70 : Colors.black87)),
  );
}

class _ExplanationBox extends StatelessWidget {
  final ActQuestion question;
  final bool isDark;
  const _ExplanationBox({required this.question, required this.isDark});

  @override
  Widget build(BuildContext context) => Column(children: [
    Container(
      width: double.infinity, padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: ActColors.info.withOpacity(0.07), borderRadius: BorderRadius.circular(9),
          border: Border.all(color: ActColors.info.withOpacity(0.20))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(Icons.info_outline, size: 14, color: ActColors.info), const SizedBox(width: 6),
          const Text('Explanation', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))]),
        const SizedBox(height: 7),
        Text(question.explanation, style: const TextStyle(fontSize: 12.5, height: 1.5)),
      ]),
    ),
    if (question.topicTip != null) ...[
      const SizedBox(height: 8),
      Container(
        width: double.infinity, padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: ActColors.accent.withOpacity(0.07), borderRadius: BorderRadius.circular(9),
            border: Border.all(color: ActColors.accent.withOpacity(0.22))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.lightbulb_outline, size: 14, color: ActColors.accent), const SizedBox(width: 6),
            const Text('Topic Tip', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))]),
          const SizedBox(height: 7),
          Text(question.topicTip!, style: const TextStyle(fontSize: 12.5, height: 1.5)),
        ]),
      ),
    ],
  ]);
}

class _SearchingWidget extends StatelessWidget {
  final String status;
  final VoidCallback onCancel;
  const _SearchingWidget({required this.status, required this.onCancel});

  @override
  Widget build(BuildContext context) => Column(children: [
    const CircularProgressIndicator(),
    const SizedBox(height: 16),
    Text(status, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), textAlign: TextAlign.center),
    const SizedBox(height: 12),
    TextButton(onPressed: onCancel, child: const Text('Cancel')),
  ]);
}

class _ErrorBanner extends StatelessWidget {
  final String msg;
  const _ErrorBanner({required this.msg});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: ActColors.danger.withOpacity(0.07), borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ActColors.danger.withOpacity(0.20))),
    child: Text(msg, style: TextStyle(color: ActColors.danger, fontSize: 13)),
  );
}

class _MatchedCard extends StatelessWidget {
  final String opponentName;
  final ChallengeBetProposal? pendingBet, activeBet;
  final bool proposedByMe;
  final VoidCallback onAcceptBet, onDeclineBet, onRemoveOpponent;
  final bool isDark;
  const _MatchedCard({
    required this.opponentName, this.pendingBet, this.activeBet,
    this.proposedByMe = false,
    required this.onAcceptBet, required this.onDeclineBet, required this.onRemoveOpponent,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: ActColors.success.withOpacity(0.07),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: ActColors.success.withOpacity(0.22)),
    ),
    child: Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _PlayerPill(name: 'You', isUser: true),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('VS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: ActColors.primary))),
        _PlayerPill(name: opponentName, isUser: false),
      ]),
      if (pendingBet != null && !proposedByMe) ...[
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: ActColors.warning.withOpacity(0.10), borderRadius: BorderRadius.circular(8),
              border: Border.all(color: ActColors.warning.withOpacity(0.28))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$opponentName proposes a bet:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: ActColors.warning)),
            const SizedBox(height: 5),
            Text(pendingBet!.description, style: const TextStyle(fontSize: 13, height: 1.4)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: ActColors.danger, side: BorderSide(color: ActColors.danger.withOpacity(0.5))),
                onPressed: onDeclineBet, child: const Text('Decline'))),
              const SizedBox(width: 10),
              Expanded(child: FilledButton(style: FilledButton.styleFrom(backgroundColor: ActColors.warning),
                  onPressed: onAcceptBet, child: const Text('Accept', style: TextStyle(color: Colors.white)))),
            ]),
          ]),
        ),
      ] else if (pendingBet != null && proposedByMe) ...[
        const SizedBox(height: 10),
        Text('Waiting for $opponentName to respond to your bet...', style: TextStyle(fontSize: 11.5, color: ActColors.warning, fontWeight: FontWeight.w600)),
      ] else if (activeBet != null) ...[
        const SizedBox(height: 8),
        Text('Active bet: ${activeBet!.description}', style: TextStyle(fontSize: 11, color: ActColors.warning, fontWeight: FontWeight.w600)),
      ],
      const SizedBox(height: 10),
      TextButton.icon(
        onPressed: onRemoveOpponent,
        icon: Icon(Icons.person_remove_outlined, size: 15, color: ActColors.danger),
        label: Text('Not satisfied? Remove & search again', style: TextStyle(fontSize: 11, color: ActColors.danger)),
      ),
    ]),
  );
}

class _PlayerPill extends StatelessWidget {
  final String name;
  final bool isUser;
  const _PlayerPill({required this.name, required this.isUser});

  @override
  Widget build(BuildContext context) => Column(children: [
    CircleAvatar(radius: 22, backgroundColor: isUser ? ActColors.primary : ActColors.info,
        child: Text(name.substring(0, 1).toUpperCase(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17))),
    const SizedBox(height: 5),
    Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11), overflow: TextOverflow.ellipsis),
  ]);
}

class _ChatBox extends StatelessWidget {
  final List<Map<String, dynamic>> messages;
  final TextEditingController controller;
  final ScrollController scrollCtrl;
  final VoidCallback onSend;
  final bool isDark;
  final bool opponentTyping;
  final String opponentName;
  const _ChatBox({
    required this.messages, required this.controller, required this.scrollCtrl,
    required this.onSend, required this.isDark,
    this.opponentTyping = false, this.opponentName = '',
  });

  @override
  Widget build(BuildContext context) => Container(
    height: 170,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: isDark ? ActColors.darkCard : const Color(0xFFF5F5F5),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: isDark ? ActColors.darkBorder : ActColors.lightBorder),
    ),
    child: Column(children: [
      Expanded(child: ListView.builder(
        controller: scrollCtrl,
        itemCount: messages.length + (opponentTyping ? 1 : 0),
        itemBuilder: (_, i) {
          if (opponentTyping && i == messages.length) {
            return Align(
              alignment: Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? ActColors.darkSurface : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? ActColors.darkBorder : ActColors.lightBorder),
                ),
                child: Text('$opponentName is typing...',
                    style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: ActColors.midGray)),
              ),
            );
          }
          final m = messages[i];
          final isMe = m['sender'] == 'You';
          return Align(
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isMe ? ActColors.primary : (isDark ? ActColors.darkSurface : Colors.white),
                borderRadius: BorderRadius.circular(12),
                border: isMe ? null : Border.all(color: isDark ? ActColors.darkBorder : ActColors.lightBorder),
              ),
              child: Text('${m['sender']}: ${m['text']}',
                  style: TextStyle(fontSize: 11, color: isMe ? Colors.white : (isDark ? Colors.white : ActColors.charcoal))),
            ),
          );
        },
      )),
      const Divider(height: 8),
      Row(children: [
        Expanded(child: TextField(
          controller: controller,
          style: const TextStyle(fontSize: 12),
          decoration: const InputDecoration(hintText: 'Message...', hintStyle: TextStyle(fontSize: 12), isDense: true, border: InputBorder.none),
          onSubmitted: (_) => onSend(),
        )),
        IconButton(icon: const Icon(Icons.send, size: 16), padding: EdgeInsets.zero, onPressed: onSend),
      ]),
    ]),
  );
}

class _RoomCard extends StatelessWidget {
  final String title, subtitle, code;
  final bool isSelected, isDark;
  final VoidCallback onTap;
  const _RoomCard({required this.title, required this.subtitle, required this.code, required this.isSelected, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? ActColors.primary.withOpacity(0.09) : (isDark ? ActColors.darkCard : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? ActColors.primary : (isDark ? ActColors.darkBorder : ActColors.lightBorder), width: isSelected ? 2 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: isSelected ? ActColors.primary : ActColors.midGray.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
            child: Text(code, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: isSelected ? Colors.white : ActColors.midGray)),
          ),
          const SizedBox(height: 10),
          Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: isSelected ? ActColors.primary : (isDark ? Colors.white : ActColors.charcoal))),
          Text(subtitle, style: TextStyle(fontSize: 10, color: ActColors.midGray)),
        ]),
      ),
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
