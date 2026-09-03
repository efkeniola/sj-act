import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/questions_data.dart';
import '../data/syllabus_data.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/leaderboard_service.dart';
import '../services/user_profile_service.dart';
import '../services/voice_service.dart';
import '../utils/constants.dart';
import '../utils/theme.dart';
import 'result_screen.dart';

class SectionScreen extends StatefulWidget {
  final ActSection section;
  final int? questionCount; // null = full count per section
  final bool isChallengeMode;

  const SectionScreen({
    super.key,
    required this.section,
    this.questionCount,
    this.isChallengeMode = false,
  });

  @override
  State<SectionScreen> createState() => _SectionScreenState();
}

class _SectionScreenState extends State<SectionScreen> {
  late List<ActQuestion> _questions;
  int _current = 0;
  final Map<int, String> _answers = {};
  String? _selectedAnswer;
  bool _showFeedback = false;
  bool _voiceEnabled = false;
  bool _micEnabled = false;
  bool _listening = false;
  bool _paused = false;
  bool _calcVisible = false;

  // Mini calculator state
  String _calcDisplay = '0';
  String _calcOp = '';
  double _calcVal = 0;
  bool _calcNewNum = true;

  late int _totalSeconds;
  late Timer _timer;
  int _secondsLeft = 0;

  final PageController _pageCtrl = PageController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _questions = _buildQuestionList();
    _totalSeconds = _timeLimitFor(widget.section);
    _secondsLeft = _totalSeconds;
    _startTimer();
    _loadVoicePrefs();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  List<ActQuestion> _buildQuestionList() {
    final pool = questionsForSection(widget.section);
    if (pool.isEmpty) return [];
    final count = widget.questionCount ?? pool.length;
    if (count >= pool.length) return List.from(pool);
    final shuffled = List.from(pool)..shuffle(Random());
    return shuffled.take(count).cast<ActQuestion>().toList();
  }

  int _timeLimitFor(ActSection section) {
    switch (section) {
      case ActSection.math:    return AppConstants.mathMinutes * 60;
      case ActSection.reading: return AppConstants.readingMinutes * 60;
      case ActSection.science: return AppConstants.scienceMinutes * 60;
      default:                 return AppConstants.englishMinutes * 60;
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_paused) return;
      if (_secondsLeft <= 0) {
        _timer.cancel();
        _finishExam();
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  Future<void> _loadVoicePrefs() async {
    await VoiceService.instance.init();
    final tts = await VoiceService.instance.isTtsEnabled();
    final mic = await VoiceService.instance.isSttEnabled();
    if (mounted) setState(() { _voiceEnabled = tts; _micEnabled = mic; });
    if (tts) _readCurrentQuestion();
  }

  void _readCurrentQuestion() {
    if (!_voiceEnabled || _questions.isEmpty) return;
    final q = _questions[_current];
    VoiceService.instance.readQuestion(
      questionText: q.questionText,
      options: q.options,
    );
  }

  void _startListening() async {
    if (!_micEnabled || _listening) return;
    setState(() => _listening = true);
    await VoiceService.instance.listenForAnswer(
      onResult: (letter) {
        if (mounted) setState(() { _listening = false; _selectAnswer(letter); });
      },
      onUnrecognised: () {
        if (mounted) setState(() => _listening = false);
        _showSnack('Could not detect a valid answer. Please say A, B, C, or D clearly.');
      },
    );
  }

  void _selectAnswer(String letter) {
    if (_showFeedback) return;
    setState(() => _selectedAnswer = letter);
  }

  void _confirmAnswer() {
    if (_selectedAnswer == null || _showFeedback) return;
    setState(() {
      _answers[_current] = _selectedAnswer!;
      _showFeedback = true;
    });
    final q = _questions[_current];
    final isCorrect = _selectedAnswer == q.correctAnswer;
    if (_voiceEnabled) {
      VoiceService.instance.readText(
        isCorrect ? 'Correct.' : 'Incorrect. The answer is ${q.correctAnswer}.',
      );
    }
  }

  void _nextQuestion() {
    if (_current < _questions.length - 1) {
      setState(() {
        _current++;
        _selectedAnswer = _answers[_current];
        _showFeedback = _answers.containsKey(_current);
      });
      _pageCtrl.nextPage(duration: const Duration(milliseconds: 220), curve: Curves.easeInOut);
      if (_voiceEnabled) _readCurrentQuestion();
    } else {
      _finishExam();
    }
  }

  void _prevQuestion() {
    if (_current > 0) {
      setState(() {
        _current--;
        _selectedAnswer = _answers[_current];
        _showFeedback = _answers.containsKey(_current);
      });
      _pageCtrl.previousPage(duration: const Duration(milliseconds: 220), curve: Curves.easeInOut);
    }
  }

  void _finishExam() {
    _timer.cancel();
    VoiceService.instance.stopReading();
    _saveAttempt();
  }

  Future<void> _saveAttempt() async {
    final results = <QuestionResult>[];
    for (var i = 0; i < _questions.length; i++) {
      final given = _answers[i] ?? '';
      results.add(QuestionResult(
        questionId: _questions[i].id,
        givenAnswer: given,
        isCorrect: given == _questions[i].correctAnswer,
        timeSpent: Duration(seconds: _totalSeconds - _secondsLeft),
      ));
    }
    final attempt = ExamAttempt(
      id: DateTime.now().toIso8601String(),
      startedAt: DateTime.now().subtract(Duration(seconds: _totalSeconds - _secondsLeft)),
      completedAt: DateTime.now(),
      setNumber: 1,
      section: widget.section,
      results: results,
    );
    await DatabaseService.instance.saveAttempt(attempt);
    // Update leaderboard
    final name = await UserProfileService.getDisplayName() ?? 'Student';
    final score = attempt.actScaledScore;
    await DatabaseService.instance.upsertLeaderboardEntry(name, score, attempt.accuracy);

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ResultScreen(attempt: attempt, questions: _questions),
      ),
    );
  }

  // ── Keyboard shortcuts ────────────────────────────────────────────────────
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.keyA || key == LogicalKeyboardKey.digit1) { _selectAnswer('A'); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.keyB || key == LogicalKeyboardKey.digit2) { _selectAnswer('B'); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.keyC || key == LogicalKeyboardKey.digit3) { _selectAnswer('C'); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.keyD || key == LogicalKeyboardKey.digit4) { _selectAnswer('D'); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.keyN) { _showFeedback ? _nextQuestion() : _confirmAnswer(); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyP) { _prevQuestion(); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.backspace) { setState(() { _selectedAnswer = null; _showFeedback = false; }); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.keyV) { _toggleVoice(); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.keyM) { _toggleMic(); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.escape) { _confirmExit(); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) { _showFeedback ? _nextQuestion() : _confirmAnswer(); return KeyEventResult.handled; }
    return KeyEventResult.ignored;
  }

  void _toggleVoice() async {
    final newVal = !_voiceEnabled;
    await VoiceService.instance.setTtsEnabled(newVal);
    setState(() => _voiceEnabled = newVal);
    if (newVal) _readCurrentQuestion();
  }

  void _toggleMic() async {
    final newVal = !_micEnabled;
    await VoiceService.instance.setSttEnabled(newVal);
    setState(() => _micEnabled = newVal);
  }

  void _confirmExit() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Exit Session?'),
        content: const Text('Your progress will be saved up to the last answered question. Are you sure you want to exit?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Stay')),
          TextButton(
            onPressed: () { Navigator.pop(context); _finishExam(); },
            child: Text('Exit', style: TextStyle(color: ActColors.danger)),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Color get _timerColor {
    final pct = _secondsLeft / _totalSeconds;
    if (pct > 0.4) return ActColors.success;
    if (pct > 0.15) return ActColors.warning;
    return ActColors.danger;
  }

  @override
  void dispose() {
    _timer.cancel();
    _pageCtrl.dispose();
    _focusNode.dispose();
    VoiceService.instance.stopReading();
    VoiceService.instance.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final q = _questions.isNotEmpty ? _questions[_current] : null;

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKey,
      child: Scaffold(
        appBar: AppBar(
          title: Text(actSectionDisplayName(widget.section)),
          actions: [
            // Timer
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _timerColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _timerColor.withOpacity(0.4)),
                  ),
                  child: Row(children: [
                    Icon(Icons.timer_outlined, size: 14, color: _timerColor),
                    const SizedBox(width: 4),
                    Text(_formatTime(_secondsLeft), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: _timerColor)),
                  ]),
                ),
              ),
            ),
            // Voice toggle
            IconButton(
              icon: Icon(_voiceEnabled ? Icons.volume_up : Icons.volume_off_outlined,
                  color: _voiceEnabled ? Colors.white : Colors.white60),
              tooltip: 'Voice Reading (V)',
              onPressed: _toggleVoice,
            ),
            // Mic toggle
            IconButton(
              icon: Icon(_listening ? Icons.mic : (_micEnabled ? Icons.mic_outlined : Icons.mic_off_outlined),
                  color: _listening ? ActColors.accent : (_micEnabled ? Colors.white : Colors.white60)),
              tooltip: 'Voice Answer (M)',
              onPressed: _micEnabled ? _startListening : _toggleMic,
            ),
            // Calculator (Math & Science only)
            if (widget.section == ActSection.math || widget.section == ActSection.science)
              IconButton(
                icon: Icon(_calcVisible ? Icons.calculate : Icons.calculate_outlined,
                    color: _calcVisible ? ActColors.accent : Colors.white70),
                tooltip: 'Calculator',
                onPressed: () => setState(() => _calcVisible = !_calcVisible),
              ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _confirmExit,
            ),
          ],
        ),
        body: _questions.isEmpty
            ? const Center(child: Text('No questions available for this section yet.'))
            : Stack(
                children: [
                  Column(
                    children: [
                  // Progress bar
                  LinearProgressIndicator(
                    value: (_current + 1) / _questions.length,
                    color: ActColors.primary,
                    backgroundColor: ActColors.primary.withOpacity(0.12),
                    minHeight: 3,
                  ),

                  // Question counter
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        Text(
                          'Question ${_current + 1} of ${_questions.length}',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        const Spacer(),
                        Text(
                          q?.skillArea ?? '',
                          style: TextStyle(fontSize: 11, color: ActColors.midGray),
                        ),
                      ],
                    ),
                  ),

                  // Question content
                  Expanded(
                    child: PageView.builder(
                      controller: _pageCtrl,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _questions.length,
                      itemBuilder: (_, i) {
                        final question = _questions[i];
                        return _QuestionPage(
                          question: question,
                          selectedAnswer: i == _current ? _selectedAnswer : _answers[i],
                          showFeedback: i == _current ? _showFeedback : _answers.containsKey(i),
                          onSelect: i == _current ? _selectAnswer : null,
                          isDark: isDark,
                        );
                      },
                    ),
                  ),

                  // Bottom action bar
                  _BottomBar(
                    current: _current,
                    total: _questions.length,
                    selectedAnswer: _selectedAnswer,
                    showFeedback: _showFeedback,
                    onPrev: _prevQuestion,
                    onConfirm: _confirmAnswer,
                    onNext: _nextQuestion,
                    isListening: _listening,
                    micEnabled: _micEnabled,
                    onMicTap: _startListening,
                  ),
                ],
              ),
                  // Floating calculator overlay
                  if (_calcVisible && (widget.section == ActSection.math || widget.section == ActSection.science))
                    Positioned(
                      right: 12, bottom: 100,
                      child: _MiniCalculator(
                        display: _calcDisplay,
                        onInput: (token) => setState(() => _calcInput(token)),
                        onClose: () => setState(() => _calcVisible = false),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  // ── Mini calculator engine ─────────────────────────────────────────────────
  void _calcInput(String v) {
    if (v == 'C') {
      _calcDisplay = '0'; _calcOp = ''; _calcVal = 0; _calcNewNum = true; return;
    }
    if (v == '⌫') {
      _calcDisplay = _calcDisplay.length > 1 ? _calcDisplay.substring(0, _calcDisplay.length - 1) : '0'; return;
    }
    if (v == '=') {
      final cur = double.tryParse(_calcDisplay) ?? 0;
      double r = cur;
      if (_calcOp == '+') r = _calcVal + cur;
      else if (_calcOp == '−') r = _calcVal - cur;
      else if (_calcOp == '×') r = _calcVal * cur;
      else if (_calcOp == '÷') r = cur == 0 ? 0 : _calcVal / cur;
      _calcDisplay = r == r.truncateToDouble() ? r.toInt().toString() : r.toStringAsFixed(6).replaceAll(RegExp(r'0+\$'), '');
      _calcOp = ''; _calcNewNum = true; return;
    }
    if (['+', '−', '×', '÷'].contains(v)) {
      _calcVal = double.tryParse(_calcDisplay) ?? 0;
      _calcOp = v; _calcNewNum = true; return;
    }
    if (v == '.') {
      if (_calcNewNum) { _calcDisplay = '0.'; _calcNewNum = false; }
      else if (!_calcDisplay.contains('.')) _calcDisplay += '.';
      return;
    }
    if (_calcNewNum) { _calcDisplay = v; _calcNewNum = false; }
    else { _calcDisplay = _calcDisplay == '0' ? v : (_calcDisplay.length < 14 ? _calcDisplay + v : _calcDisplay); }
  }
}

// ── Question page ─────────────────────────────────────────────────────────────
class _QuestionPage extends StatelessWidget {
  final ActQuestion question;
  final String? selectedAnswer;
  final bool showFeedback;
  final void Function(String)? onSelect;
  final bool isDark;

  const _QuestionPage({
    required this.question,
    required this.selectedAnswer,
    required this.showFeedback,
    required this.onSelect,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Passage (reading / science)
          if (question.passageText != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: isDark ? ActColors.darkCard : const Color(0xFFF9F9F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isDark ? ActColors.darkBorder : ActColors.lightBorder),
              ),
              child: Text(
                question.passageText!,
                style: TextStyle(fontSize: 13, height: 1.55, color: isDark ? Colors.white70 : Colors.black87),
              ),
            ),
          ],

          // Question text
          Text(
            question.questionText,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.5),
          ),
          const SizedBox(height: 18),

          // Options
          ...List.generate(question.options.length, (i) {
            final letter = question.optionLetters[i];
            final text   = question.options[i];
            final isSelected = selectedAnswer == letter;
            final isCorrect  = letter == question.correctAnswer;

            Color borderColor = isDark ? ActColors.darkBorder : ActColors.lightBorder;
            Color bgColor = isDark ? ActColors.darkCard : Colors.white;
            Color? textColor;
            IconData? trailingIcon;

            if (showFeedback) {
              if (isCorrect) {
                borderColor = ActColors.success;
                bgColor = ActColors.success.withOpacity(0.09);
                textColor = ActColors.success;
                trailingIcon = Icons.check_circle_outline;
              } else if (isSelected) {
                borderColor = ActColors.danger;
                bgColor = ActColors.danger.withOpacity(0.09);
                textColor = ActColors.danger;
                trailingIcon = Icons.cancel_outlined;
              }
            } else if (isSelected) {
              borderColor = ActColors.primary;
              bgColor = ActColors.primary.withOpacity(0.07);
            }

            return GestureDetector(
              onTap: onSelect == null ? null : () => onSelect!(letter),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: borderColor, width: isSelected || showFeedback ? 1.5 : 1),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? (showFeedback
                                ? (isCorrect ? ActColors.success : ActColors.danger)
                                : ActColors.primary)
                            : (showFeedback && isCorrect
                                ? ActColors.success
                                : (isDark ? ActColors.darkSurface : const Color(0xFFF0F0F0))),
                      ),
                      child: Center(
                        child: Text(letter,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: (isSelected || (showFeedback && isCorrect)) ? Colors.white : (isDark ? Colors.white70 : Colors.black54),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(text,
                        style: TextStyle(fontSize: 13.5, height: 1.4, color: textColor,
                            fontWeight: (showFeedback && (isCorrect || isSelected)) ? FontWeight.w600 : FontWeight.normal),
                      ),
                    ),
                    if (trailingIcon != null)
                      Icon(trailingIcon, color: textColor, size: 18),
                  ],
                ),
              ),
            );
          }),

          // Explanation + tip (after answer)
          if (showFeedback) ...[
            const SizedBox(height: 8),
            _ExplanationCard(question: question, isDark: isDark),
          ],
        ],
      ),
    );
  }
}

class _ExplanationCard extends StatelessWidget {
  final ActQuestion question;
  final bool isDark;
  const _ExplanationCard({required this.question, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: ActColors.info.withOpacity(0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: ActColors.info.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.info_outline, size: 15, color: ActColors.info),
                const SizedBox(width: 6),
                const Text('Explanation', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              ]),
              const SizedBox(height: 8),
              Text(question.explanation, style: const TextStyle(fontSize: 13, height: 1.5)),
            ],
          ),
        ),
        if (question.topicTip != null) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ActColors.accent.withOpacity(0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: ActColors.accent.withOpacity(0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.lightbulb_outline, size: 15, color: ActColors.accent),
                  const SizedBox(width: 6),
                  const Text('Topic Tip', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                ]),
                const SizedBox(height: 8),
                Text(question.topicTip!, style: const TextStyle(fontSize: 13, height: 1.5)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int current, total;
  final String? selectedAnswer;
  final bool showFeedback, isListening, micEnabled;
  final VoidCallback onPrev, onConfirm, onNext, onMicTap;

  const _BottomBar({
    required this.current, required this.total,
    required this.selectedAnswer, required this.showFeedback,
    required this.onPrev, required this.onConfirm, required this.onNext,
    required this.isListening, required this.micEnabled, required this.onMicTap,
  });

  @override
  Widget build(BuildContext context) {
    final isLast = current == total - 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: ActColors.lightBorder)),
      ),
      child: Row(
        children: [
          // Previous
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            tooltip: 'Previous (P / Left)',
            onPressed: current > 0 ? onPrev : null,
          ),

          // Mic button
          if (micEnabled) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onMicTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isListening ? ActColors.primary : ActColors.primary.withOpacity(0.10),
                ),
                child: Icon(
                  isListening ? Icons.mic : Icons.mic_outlined,
                  color: isListening ? Colors.white : ActColors.primary,
                  size: 20,
                ),
              ),
            ),
          ],

          const Spacer(),

          // Confirm / Next
          if (!showFeedback)
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: ActColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: selectedAnswer != null ? onConfirm : null,
              child: const Text('Confirm', style: TextStyle(fontWeight: FontWeight.w700)),
            )
          else
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: ActColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: onNext,
              icon: Icon(isLast ? Icons.done_all : Icons.arrow_forward, size: 18),
              label: Text(isLast ? 'Finish' : 'Next', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}

// ── Mini floating calculator widget ──────────────────────────────────────────
class _MiniCalculator extends StatelessWidget {
  final String display;
  final void Function(String) onInput;
  final VoidCallback onClose;

  const _MiniCalculator({
    required this.display,
    required this.onInput,
    required this.onClose,
  });

  Widget _btn(String label, {Color bg = const Color(0xFF2A2A2E), Color fg = Colors.white}) {
    return Expanded(
      child: GestureDetector(
        onTap: () => onInput(label),
        child: Container(
          margin: const EdgeInsets.all(2),
          height: 40,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: Text(label,
              style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 15)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 256,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            const Expanded(child: Text('Calculator', style: TextStyle(color: Colors.white54, fontSize: 11))),
            GestureDetector(onTap: onClose, child: const Icon(Icons.close, color: Colors.white38, size: 18)),
          ]),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
            child: Text(display,
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w300),
              textAlign: TextAlign.right,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(height: 8),
          Row(children: [
            _btn('C',  bg: const Color(0xFF636366)),
            _btn('⌫', bg: const Color(0xFF636366)),
            _btn('%',  bg: const Color(0xFF636366)),
            _btn('÷',  bg: const Color(0xFFFF9F0A), fg: Colors.black),
          ]),
          Row(children: [
            _btn('7'), _btn('8'), _btn('9'),
            _btn('×', bg: const Color(0xFFFF9F0A), fg: Colors.black),
          ]),
          Row(children: [
            _btn('4'), _btn('5'), _btn('6'),
            _btn('−', bg: const Color(0xFFFF9F0A), fg: Colors.black),
          ]),
          Row(children: [
            _btn('1'), _btn('2'), _btn('3'),
            _btn('+', bg: const Color(0xFFFF9F0A), fg: Colors.black),
          ]),
          Row(children: [
            _btn('0'), _btn('.'), _btn('⌫', bg: const Color(0xFF3A3A3C)),
            _btn('=', bg: ActColors.primary),
          ]),
        ],
      ),
    );
  }
}
