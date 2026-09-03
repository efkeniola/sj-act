import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/questions_data.dart';
import '../models/models.dart';
import '../multiplayer/fake_online_challenge.dart';
import '../services/database_service.dart';
import '../services/leaderboard_service.dart';
import '../services/user_profile_service.dart';
import '../services/voice_service.dart';
import '../utils/constants.dart';
import '../utils/theme.dart';

// ── Setup screen ──────────────────────────────────────────────────────────────
class OnlineChallengeScreen extends StatefulWidget {
  const OnlineChallengeScreen({super.key});

  @override
  State<OnlineChallengeScreen> createState() => _OnlineChallengeScreenState();
}

class _OnlineChallengeScreenState extends State<OnlineChallengeScreen> {
  OnlineChallengeRegion _region = OnlineChallengeRegion.usa;
  ActSection _section = ActSection.math;
  int _questionCount = 30;

  bool _searching = false;
  String _statusMsg = '';
  String? _opponentName;
  ChallengeBetProposal? _pendingBet;
  bool _betAccepted = false;
  bool _betDeclined = false;
  StreamSubscription<String>? _matchSub;

  final List<Map<String, dynamic>> _chatMessages = [];
  final _chatCtrl = TextEditingController();
  final _chatScrollCtrl = ScrollController();
  bool _fakeOpponentReplied = false;

  @override
  void dispose() {
    _matchSub?.cancel();
    _chatCtrl.dispose();
    _chatScrollCtrl.dispose();
    super.dispose();
  }

  void _startSearch() {
    setState(() {
      _searching = true;
      _statusMsg = 'Connecting...';
      _opponentName = null;
      _pendingBet = null;
      _betAccepted = false;
      _betDeclined = false;
      _fakeOpponentReplied = false;
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
      final bet = FakeOnlineChallenge.fakeOpponentBetProposal();
      setState(() {
        _opponentName = name;
        _searching = false;
        _statusMsg = '';
        _pendingBet = bet;
      });
      _addChat(name, FakeOnlineChallenge.opponentOpeningMessage(name));
      if (bet != null) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) _addChat(name, 'Bet proposal: ${bet.description}');
        });
      }
      return;
    }
    setState(() => _statusMsg = status);
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

    // Opponent replies once with a realistic message
    if (!_fakeOpponentReplied && _opponentName != null) {
      _fakeOpponentReplied = true;
      final replies = [
        'Ha! Good luck to you too.',
        'Ready.',
        "Let's see.",
        'Same! Let\'s go.',
        'May the best student win.',
        'Ready when you are.',
        'GG incoming.',
      ];
      final delay = Duration(seconds: 2 + Random().nextInt(4));
      Future.delayed(delay, () {
        if (mounted && _opponentName != null) {
          _addChat(_opponentName!, replies[Random().nextInt(replies.length)]);
        }
      });
    }
  }

  void _acceptBet() {
    setState(() => _betAccepted = true);
    _addChat('You', 'Bet accepted.');
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _opponentName != null) _addChat(_opponentName!, 'Let\'s go then!');
    });
  }

  void _declineBet() {
    setState(() { _pendingBet = null; _betDeclined = true; });
    _addChat('You', 'Bet declined — playing clean.');
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _opponentName != null) _addChat(_opponentName!, 'No problem. Good luck anyway.');
    });
  }

  void _startMatch() {
    if (_opponentName == null) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => OnlineChallengeMatchScreen(
          section: _section,
          questionCount: _questionCount,
          opponentName: _opponentName!,
          bet: _betAccepted ? _pendingBet : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Online Challenge')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Activity status
            _ActivityBanner(isDark: isDark),
            const SizedBox(height: 16),

            // Room selector
            _Label('Select Room'),
            Row(children: [
              _RoomCard(title: 'USA Room', subtitle: 'US-based opponents', code: 'US',
                  isSelected: _region == OnlineChallengeRegion.usa,
                  onTap: () => setState(() => _region = OnlineChallengeRegion.usa), isDark: isDark),
              const SizedBox(width: 12),
              _RoomCard(title: 'Foreign Room', subtitle: 'International opponents', code: 'GL',
                  isSelected: _region == OnlineChallengeRegion.foreign,
                  onTap: () => setState(() => _region = OnlineChallengeRegion.foreign), isDark: isDark),
            ]),
            const SizedBox(height: 16),

            // Section
            _Label('ACT Section'),
            DropdownButtonFormField<ActSection>(
              value: _section,
              decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              items: ActSection.values.map((s) => DropdownMenuItem(value: s, child: Text(actSectionDisplayName(s)))).toList(),
              onChanged: (s) { if (s != null) setState(() => _section = s); },
            ),
            const SizedBox(height: 14),
            _Label('Questions'),
            Wrap(spacing: 8, children: [10, 20, 30, 40].map((n) => ChoiceChip(
              label: Text('$n'),
              selected: _questionCount == n,
              selectedColor: ActColors.primary,
              labelStyle: TextStyle(color: _questionCount == n ? Colors.white : null, fontWeight: FontWeight.w600),
              onSelected: (_) => setState(() => _questionCount = n),
            )).toList()),
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
                    onPressed: _startSearch,
                  ),
                ),
              ],
            ] else ...[
              // Opponent card
              _MatchedCard(
                opponentName: _opponentName!,
                pendingBet: (_pendingBet != null && !_betAccepted && !_betDeclined) ? _pendingBet : null,
                activeBet: _betAccepted ? _pendingBet : null,
                onAcceptBet: _acceptBet,
                onDeclineBet: _declineBet,
                isDark: isDark,
              ),
              const SizedBox(height: 16),

              // Chat
              _Label('Pre-Match Chat'),
              _ChatBox(
                messages: _chatMessages,
                controller: _chatCtrl,
                scrollCtrl: _chatScrollCtrl,
                onSend: _sendChat,
                isDark: isDark,
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
                  onPressed: _startMatch,
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

// ── Live match screen ─────────────────────────────────────────────────────────
enum _MatchPhase { myTurn, opponentThinking, opponentAfk, finished }

class OnlineChallengeMatchScreen extends StatefulWidget {
  final ActSection section;
  final int questionCount;
  final String opponentName;
  final ChallengeBetProposal? bet;

  const OnlineChallengeMatchScreen({
    super.key,
    required this.section,
    required this.questionCount,
    required this.opponentName,
    this.bet,
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

  // Opponent state
  _MatchPhase _phase = _MatchPhase.opponentThinking;
  int _opponentAnswered = 0;
  int _opponentAfkSec = 0;
  bool _myTurnDone = false;
  bool _opponentDone = false;
  StreamSubscription<OpponentEvent>? _opponentSub;
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

  @override
  void initState() {
    super.initState();
    _buildQuestions();
    _startMatchTimer();
    _startConnectivityMonitor();
    _loadVoice();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
    _beginRound();
  }

  void _buildQuestions() {
    final pool = questionsForSection(widget.section);
    final shuffled = List.from(pool)..shuffle(Random());
    _questions = shuffled.take(widget.questionCount).cast<ActQuestion>().toList();
    _matchSecondsLeft = _questions.length * 90;
  }

  Future<void> _loadVoice() async {
    await VoiceService.instance.init();
    final enabled = await VoiceService.instance.isTtsEnabled();
    if (mounted) setState(() => _voiceEnabled = enabled);
  }

  void _startMatchTimer() {
    _matchTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _finished) return;
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
    _questionSecondsLeft = 90;

    // Start per-question timer
    _questionTimer?.cancel();
    _questionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _roundAdvancing) return;
      setState(() => _questionSecondsLeft--);
      if (_questionSecondsLeft <= 0) {
        // Player timed out — auto-skip their answer and advance
        _roundAdvancing = true;
        _questionTimer?.cancel();
        if (!_myTurnDone) {
          _myAnswers[_qIndex] = ''; // skipped
          _myTurnDone = true;
        }
        _maybeAdvance();
      }
    });

    // Start opponent for this question
    _startOpponentForQuestion(_qIndex);
  }

  void _startOpponentForQuestion(int qIdx) {
    _opponentSub?.cancel();
    final stream = FakeOnlineChallenge.opponentEventStream(
      totalQuestions: widget.questionCount,
      userAccuracy: _myAnswers.isEmpty ? 0.70 : (_myAnswers.values.where((v) => v.isNotEmpty).length / _myAnswers.length),
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
          _opponentAnswered = (event.answeredSoFar ?? _opponentAnswered + 1).clamp(0, _questions.length);
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
    if (_showFeedback || _phase != _MatchPhase.myTurn) return;
    HapticFeedback.lightImpact();
    setState(() => _selected = letter);
  }

  void _confirmAnswer() {
    if (_selected == null || _showFeedback) return;
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
    if (_roundAdvancing) return;
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

  void _finishMatch() {
    if (_finished) return;
    _finished = true;
    _matchTimer?.cancel();
    _questionTimer?.cancel();
    _opponentSub?.cancel();
    _connectivityTimer?.cancel();
    _disconnectTimer?.cancel();
    _afkCountTimer?.cancel();
    VoiceService.instance.stopReading();

    final myCorrect = _myAnswers.entries.where((e) {
      final qi = e.key;
      return qi < _questions.length && e.value == _questions[qi].correctAnswer;
    }).length;
    final myAcc = _questions.isEmpty ? 0.0 : myCorrect / _questions.length;
    final myScore = (1 + myAcc * 35).clamp(1.0, 36.0);
    final opScore = FakeOnlineChallenge.simulateOpponentScore(_questions.length, myAcc);

    _saveAndNavigate(myScore, opScore, myAcc);
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
      section: widget.section,
      results: results,
    );
    await DatabaseService.instance.saveAttempt(attempt);
    final name = await UserProfileService.getDisplayName() ?? 'You';
    await DatabaseService.instance.upsertLeaderboardEntry(name, myScore, acc);

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => _OnlineResultScreen(
          myName: name,
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
      }
    });
  }

  void _beginDisconnectCountdown() {
    if (_disconnectWarning) return;
    setState(() { _disconnectWarning = true; _disconnectSec = 25; });
    _disconnectTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _disconnectSec--);
      if (_disconnectSec <= 0) { t.cancel(); _finishMatch(); }
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

  void _confirmExit() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Exit Match?'),
        content: Text('${widget.opponentName} will be notified that you left. Your progress up to this question will be saved.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Stay')),
          TextButton(
            onPressed: () { Navigator.pop(context); _finishMatch(); },
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_questions.isEmpty) return const Scaffold(body: Center(child: Text('No questions available.')));
    final q = _questions[_qIndex];
    final myTurn = _phase == _MatchPhase.myTurn && !_showFeedback;

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKey,
      child: PopScope(
        canPop: false,
        onPopInvoked: (didPop) { if (!didPop) _confirmExit(); },
        child: Scaffold(
          appBar: AppBar(
            title: Text('${actSectionDisplayName(widget.section)} — Q${_qIndex + 1}/${_questions.length}'),
            leading: IconButton(icon: const Icon(Icons.close), onPressed: _confirmExit),
            actions: [
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
          body: Column(
            children: [
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
                onNext: _nextQuestion,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Result screen ─────────────────────────────────────────────────────────────
class _OnlineResultScreen extends StatelessWidget {
  final String myName, opponentName;
  final double myScore, opponentScore;
  final int totalQuestions, myCorrect;
  final ChallengeBetProposal? bet;

  const _OnlineResultScreen({
    required this.myName, required this.opponentName,
    required this.myScore, required this.opponentScore,
    required this.totalQuestions, required this.myCorrect,
    this.bet,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iWon = myScore > opponentScore;
    final tie  = (myScore - opponentScore).abs() < 0.1;
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
            _ResultPlayerCard(name: myName, score: myScore, isMe: true, color: myColor, correct: myCorrect, total: totalQuestions),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('VS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: ActColors.primary)),
            ),
            _ResultPlayerCard(name: opponentName, score: opponentScore, isMe: false, color: opColor, correct: null, total: totalQuestions),
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
  final bool isDark;
  const _TurnBanner({required this.myTurn, required this.showFeedback, required this.opponentName, required this.questionSecondsLeft, required this.isDark});

  @override
  Widget build(BuildContext context) {
    if (showFeedback) return const SizedBox.shrink();
    final color = myTurn ? ActColors.primary : ActColors.midGray;
    final urgent = myTurn && questionSecondsLeft <= 15;
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
          myTurn ? 'Your turn — answer now!' : 'Waiting for $opponentName...',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
              color: urgent ? ActColors.danger : color),
        )),
        if (myTurn)
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
  final VoidCallback onConfirm, onNext;
  const _MatchBottomBar({required this.myTurn, required this.showFeedback, required this.selected, required this.isLast, required this.onConfirm, required this.onNext});

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
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: ActColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: onNext,
          icon: Icon(isLast ? Icons.done_all : Icons.arrow_forward, size: 18),
          label: Text(isLast ? 'Finish' : 'Next', style: const TextStyle(fontWeight: FontWeight.w700)),
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
  final VoidCallback onAcceptBet, onDeclineBet;
  final bool isDark;
  const _MatchedCard({required this.opponentName, this.pendingBet, this.activeBet, required this.onAcceptBet, required this.onDeclineBet, required this.isDark});

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
      if (pendingBet != null) ...[
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
      ] else if (activeBet != null) ...[
        const SizedBox(height: 8),
        Text('Active bet: ${activeBet!.description}', style: TextStyle(fontSize: 11, color: ActColors.warning, fontWeight: FontWeight.w600)),
      ],
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
  const _ChatBox({required this.messages, required this.controller, required this.scrollCtrl, required this.onSend, required this.isDark});

  @override
  Widget build(BuildContext context) => Container(
    height: 150,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: isDark ? ActColors.darkCard : const Color(0xFFF5F5F5),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: isDark ? ActColors.darkBorder : ActColors.lightBorder),
    ),
    child: Column(children: [
      Expanded(child: ListView.builder(
        controller: scrollCtrl,
        itemCount: messages.length,
        itemBuilder: (_, i) {
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
                  style: TextStyle(fontSize: 11, color: isMe ? Colors.white : null)),
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
          Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: isSelected ? ActColors.primary : null)),
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
