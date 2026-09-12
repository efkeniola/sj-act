import 'package:flutter/material.dart';

import '../models/models.dart';
import '../utils/theme.dart';

/// Reviews a completed full exam question-by-question, in the same visual
/// style and navigation pattern as the actual exam-taking screen
/// (_FullExamSession / _QuestionPage in exam_mode_screen.dart) — one
/// question per page, swipe or Prev/Next to move through it, section name
/// and "Q x/y" in the app bar — rather than a collapsed accordion list.
/// Answers are always shown (feedback mode), and options are read-only.
class ExamReviewScreen extends StatefulWidget {
  final Map<ActSection, List<ActQuestion>> sectionQuestions;
  final Map<ActSection, List<QuestionResult>> sectionResults;
  final int initialIndex;

  const ExamReviewScreen({
    super.key,
    required this.sectionQuestions,
    required this.sectionResults,
    this.initialIndex = 0,
  });

  @override
  State<ExamReviewScreen> createState() => _ExamReviewScreenState();
}

class _ReviewEntry {
  final ActSection section;
  final ActQuestion question;
  final QuestionResult? result;
  _ReviewEntry(this.section, this.question, this.result);
}

class _ExamReviewScreenState extends State<ExamReviewScreen> {
  late final List<_ReviewEntry> _entries;
  late final PageController _controller;
  late int _current;

  @override
  void initState() {
    super.initState();
    _entries = [];
    for (final section in widget.sectionQuestions.keys) {
      final questions = widget.sectionQuestions[section] ?? [];
      final results = widget.sectionResults[section] ?? [];
      for (var i = 0; i < questions.length; i++) {
        _entries.add(_ReviewEntry(section, questions[i], i < results.length ? results[i] : null));
      }
    }
    _current = widget.initialIndex.clamp(0, _entries.isEmpty ? 0 : _entries.length - 1);
    _controller = PageController(initialPage: _current);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    if (index < 0 || index >= _entries.length) return;
    _controller.animateToPage(index, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_entries.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Review')),
        body: const Center(child: Text('No questions to review.')),
      );
    }

    final entry = _entries[_current];
    final correctCount = _entries.where((e) => e.result?.isCorrect ?? false).length;

    return Scaffold(
      appBar: AppBar(
        title: Text('${actSectionDisplayName(entry.section)} — Q${_current + 1}/${_entries.length}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: Text('$correctCount/${_entries.length} correct',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: (_current + 1) / _entries.length,
            minHeight: 3,
            backgroundColor: isDark ? ActColors.darkBorder : ActColors.lightBorder,
            color: ActColors.primary,
          ),
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: _entries.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (context, i) => _ReviewQuestionPage(entry: _entries[i], isDark: isDark),
            ),
          ),
          _ReviewBottomBar(
            current: _current,
            total: _entries.length,
            onPrev: _current > 0 ? () => _goTo(_current - 1) : null,
            onNext: _current < _entries.length - 1 ? () => _goTo(_current + 1) : null,
          ),
        ],
      ),
    );
  }
}

/// Same layout/coloring as exam_mode_screen.dart's _QuestionPage in
/// showFeedback mode (correct answer highlighted green, a wrong selection
/// highlighted red, explanation + topic tip cards) but permanently
/// read-only — there's no onSelect here, since this is review, not a live
/// question.
class _ReviewQuestionPage extends StatelessWidget {
  final _ReviewEntry entry;
  final bool isDark;
  const _ReviewQuestionPage({required this.entry, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final question = entry.question;
    final selectedAnswer = entry.result?.givenAnswer;
    final answered = selectedAnswer != null && selectedAnswer.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!answered)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: ActColors.midGray.withOpacity(0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.remove_circle_outline, size: 15, color: ActColors.midGray),
                  const SizedBox(width: 6),
                  const Text('Not answered', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
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
              child: Text(question.passageText!,
                  style: TextStyle(fontSize: 13, height: 1.6, color: isDark ? Colors.white70 : Colors.black87)),
            ),
          ],
          Text(question.questionText,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.5)),
          const SizedBox(height: 18),
          ...List.generate(question.options.length, (i) {
            final letter = question.optionLetters[i];
            final text = question.options[i];
            final isSelected = selectedAnswer == letter;
            final isCorrect = letter == question.correctAnswer;

            Color borderColor = isDark ? ActColors.darkBorder : ActColors.lightBorder;
            Color bgColor = isDark ? ActColors.darkCard : Colors.white;
            Color? textColor;
            IconData? trailingIcon;

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

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: borderColor, width: isSelected || isCorrect ? 1.5 : 1),
              ),
              child: Row(
                children: [
                  Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected
                          ? (isCorrect ? ActColors.success : ActColors.danger)
                          : (isCorrect ? ActColors.success : (isDark ? ActColors.darkSurface : const Color(0xFFF0F0F0))),
                    ),
                    child: Center(child: Text(letter,
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12,
                            color: (isSelected || isCorrect) ? Colors.white : (isDark ? Colors.white70 : Colors.black54)))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(text,
                      style: TextStyle(fontSize: 13.5, height: 1.4, color: textColor,
                          fontWeight: (isCorrect || isSelected) ? FontWeight.w600 : FontWeight.normal))),
                  if (trailingIcon != null) Icon(trailingIcon, color: textColor, size: 18),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ActColors.info.withOpacity(0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: ActColors.info.withOpacity(0.2)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.info_outline, size: 15, color: ActColors.info),
                const SizedBox(width: 6),
                const Text('Explanation', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              ]),
              const SizedBox(height: 8),
              Text(question.explanation, style: const TextStyle(fontSize: 13, height: 1.5)),
            ]),
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
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.lightbulb_outline, size: 15, color: ActColors.accent),
                  const SizedBox(width: 6),
                  const Text('Topic Tip', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                ]),
                const SizedBox(height: 8),
                Text(question.topicTip!, style: const TextStyle(fontSize: 13, height: 1.5)),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

/// Simple Prev/Next bar — same idea as exam_mode_screen.dart's _BottomBar,
/// but stripped down to just navigation since review has no answer/mic
/// controls.
class _ReviewBottomBar extends StatelessWidget {
  final int current, total;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  const _ReviewBottomBar({required this.current, required this.total, required this.onPrev, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? ActColors.darkCard : Colors.white,
        border: Border(top: BorderSide(color: isDark ? ActColors.darkBorder : ActColors.lightBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onPrev,
              icon: const Icon(Icons.chevron_left, size: 18),
              label: const Text('Previous'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: ActColors.primary),
              onPressed: onNext,
              icon: const Text('Next'),
              label: const Icon(Icons.chevron_right, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}
