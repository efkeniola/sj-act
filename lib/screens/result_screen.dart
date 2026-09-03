import 'package:flutter/material.dart';

import '../data/syllabus_data.dart';
import '../models/models.dart';
import '../utils/theme.dart';
import 'home_screen.dart';

class ResultScreen extends StatelessWidget {
  final ExamAttempt attempt;
  final List<ActQuestion> questions;

  const ResultScreen({super.key, required this.attempt, required this.questions});

  @override
  Widget build(BuildContext context) {
    final correctCount = attempt.correctCount;
    final total = attempt.totalCount;
    final accuracy = attempt.accuracy;
    final actScore = attempt.actScaledScore;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Analyse weak skill areas
    final Map<String, int> skillTotal = {};
    final Map<String, int> skillCorrect = {};
    for (var i = 0; i < questions.length; i++) {
      if (i >= attempt.results.length) break;
      final q = questions[i];
      final r = attempt.results[i];
      skillTotal[q.skillArea] = (skillTotal[q.skillArea] ?? 0) + 1;
      if (r.isCorrect) skillCorrect[q.skillArea] = (skillCorrect[q.skillArea] ?? 0) + 1;
    }

    final skillPct = skillTotal.map((skill, cnt) {
      final correct = skillCorrect[skill] ?? 0;
      return MapEntry(skill, correct / cnt);
    });

    // Weakest skill areas (below 60%)
    final weakSkills = skillPct.entries
        .where((e) => e.value < 0.60)
        .toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    // Best skill areas
    final strongSkills = skillPct.entries
        .where((e) => e.value >= 0.80)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Find relevant syllabus tips for weakest skills
    final weakTopics = weakSkills
        .map((e) => syllabusTopics.where((t) => t.skillArea == e.key).toList())
        .expand((l) => l)
        .take(3)
        .toList();

    final scoreColor = ActColors.scoreColor(actScore);

    return Scaffold(
      backgroundColor: isDark ? ActColors.darkBg : ActColors.lightBg,
      appBar: AppBar(
        title: const Text('Session Results'),
        leading: IconButton(
          icon: const Icon(Icons.home_outlined),
          onPressed: () => Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
            (_) => false,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Score card ─────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [ActColors.primaryDark, ActColors.primary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Text(
                    actSectionDisplayName(attempt.section ?? ActSection.english),
                    style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        actScore.toStringAsFixed(1),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 64,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 10),
                        child: Text(' / 36', style: TextStyle(color: Colors.white60, fontSize: 20, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _scoreLabel(actScore),
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _ScoreStat(label: 'Correct', value: '$correctCount / $total'),
                      _ScoreStat(label: 'Accuracy', value: '${(accuracy * 100).toStringAsFixed(0)}%'),
                      _ScoreStat(
                        label: 'Time Used',
                        value: _formatTime(attempt.completedAt != null
                            ? attempt.completedAt!.difference(attempt.startedAt).inSeconds
                            : 0),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Performance by skill ────────────────────────────────────
            _SectionTitle('Performance by Skill Area'),
            ...skillPct.entries.map((e) => _SkillBar(
              label: e.key,
              value: e.value,
              isDark: isDark,
            )),

            // ── Weak areas ──────────────────────────────────────────────
            if (weakSkills.isNotEmpty) ...[
              const SizedBox(height: 20),
              _SectionTitle('Areas Needing Attention'),
              ...weakSkills.take(4).map((e) => _WeakAreaRow(skill: e.key, pct: e.value)),
            ],

            // ── Study advice from syllabus ──────────────────────────────
            if (weakTopics.isNotEmpty) ...[
              const SizedBox(height: 20),
              _SectionTitle('Targeted Study Advice'),
              ...weakTopics.map((topic) => _AdviceCard(topic: topic, isDark: isDark)),
            ],

            // ── Strong areas ────────────────────────────────────────────
            if (strongSkills.isNotEmpty) ...[
              const SizedBox(height: 20),
              _SectionTitle('Strengths'),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: strongSkills.map((e) => Chip(
                  label: Text(e.key, style: const TextStyle(fontSize: 11)),
                  avatar: Icon(Icons.check_circle_outline, size: 14, color: ActColors.success),
                  backgroundColor: ActColors.success.withOpacity(0.08),
                  side: BorderSide(color: ActColors.success.withOpacity(0.2)),
                )).toList(),
              ),
            ],

            const SizedBox(height: 24),

            // ── Question review ─────────────────────────────────────────
            _SectionTitle('Question-by-Question Review'),
            ...List.generate(questions.length, (i) {
              if (i >= attempt.results.length) return const SizedBox.shrink();
              final q = questions[i];
              final r = attempt.results[i];
              return _ReviewItem(
                index: i + 1,
                question: q,
                result: r,
                isDark: isDark,
              );
            }),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  String _scoreLabel(double score) {
    if (score >= 34) return 'Outstanding';
    if (score >= 30) return 'Excellent';
    if (score >= 26) return 'Above Average';
    if (score >= 20) return 'Average';
    if (score >= 14) return 'Below Average';
    return 'Needs Significant Work';
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
    child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
  );
}

class _ScoreStat extends StatelessWidget {
  final String label, value;
  const _ScoreStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
    ],
  );
}

class _SkillBar extends StatelessWidget {
  final String label;
  final double value;
  final bool isDark;
  const _SkillBar({required this.label, required this.value, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final color = value >= 0.80 ? ActColors.success : (value >= 0.60 ? ActColors.warning : ActColors.danger);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
            Text('${(value * 100).toStringAsFixed(0)}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          ]),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value,
              color: color,
              backgroundColor: color.withOpacity(0.12),
              minHeight: 7,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeakAreaRow extends StatelessWidget {
  final String skill;
  final double pct;
  const _WeakAreaRow({required this.skill, required this.pct});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Icon(Icons.warning_amber_outlined, size: 16, color: ActColors.danger),
        const SizedBox(width: 10),
        Expanded(child: Text(skill, style: const TextStyle(fontSize: 13))),
        Text('${(pct * 100).toStringAsFixed(0)}%',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ActColors.danger)),
      ],
    ),
  );
}

class _AdviceCard extends StatelessWidget {
  final SyllabusTopic topic;
  final bool isDark;
  const _AdviceCard({required this.topic, required this.isDark});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: isDark ? ActColors.darkCard : Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: isDark ? ActColors.darkBorder : ActColors.lightBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.lightbulb_outline, size: 15, color: ActColors.accent),
          const SizedBox(width: 8),
          Expanded(child: Text(topic.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
        ]),
        const SizedBox(height: 8),
        Text('Tip: ${topic.tip}', style: TextStyle(fontSize: 12, height: 1.45, color: isDark ? Colors.white70 : Colors.black87)),
        const SizedBox(height: 8),
        Text('Advice: ${topic.advice}', style: TextStyle(fontSize: 12, height: 1.45, color: ActColors.midGray)),
      ],
    ),
  );
}

class _ReviewItem extends StatefulWidget {
  final int index;
  final ActQuestion question;
  final QuestionResult result;
  final bool isDark;
  const _ReviewItem({required this.index, required this.question, required this.result, required this.isDark});

  @override
  State<_ReviewItem> createState() => _ReviewItemState();
}

class _ReviewItemState extends State<_ReviewItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isCorrect = widget.result.isCorrect;
    final color = isCorrect ? ActColors.success : ActColors.danger;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: widget.isDark ? ActColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.20)),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: color.withOpacity(0.12),
              child: Icon(
                isCorrect ? Icons.check : Icons.close,
                size: 14,
                color: color,
              ),
            ),
            title: Text(
              'Q${widget.index}: ${widget.question.skillArea}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              isCorrect
                  ? 'Correct (${widget.result.givenAnswer})'
                  : 'Your answer: ${widget.result.givenAnswer.isEmpty ? "—" : widget.result.givenAnswer}  |  Correct: ${widget.question.correctAnswer}',
              style: TextStyle(fontSize: 11, color: color),
            ),
            trailing: IconButton(
              icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 18),
              onPressed: () => setState(() => _expanded = !_expanded),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.question.questionText,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.4)),
                  const SizedBox(height: 8),
                  Text('Explanation: ${widget.question.explanation}',
                      style: TextStyle(fontSize: 12, color: ActColors.midGray, height: 1.4)),
                  if (widget.question.topicTip != null) ...[
                    const SizedBox(height: 6),
                    Text('Tip: ${widget.question.topicTip}',
                        style: TextStyle(fontSize: 12, color: ActColors.accent, height: 1.4)),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
