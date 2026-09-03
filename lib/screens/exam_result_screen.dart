import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/exam_settings_service.dart';
import '../utils/theme.dart';
import 'home_screen.dart';

/// Exam result screen showing real ACT-style scores per section + composite.
class ExamResultScreen extends StatelessWidget {
  final Map<ActSection, List<QuestionResult>> sectionResults;
  final Map<ActSection, int> sectionScores; // scaled 1-36 per section
  final int compositeScore;
  final Map<ActSection, List<ActQuestion>> sectionQuestions;
  final ExamSettings settings;

  const ExamResultScreen({
    super.key,
    required this.sectionResults,
    required this.sectionScores,
    required this.compositeScore,
    required this.sectionQuestions,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final compositeColor = ActColors.scoreColor(compositeScore.toDouble());
    final target = settings.targetScore;
    final metTarget = compositeScore >= target;

    return Scaffold(
      backgroundColor: isDark ? ActColors.darkBg : ActColors.lightBg,
      appBar: AppBar(
        title: const Text('Exam Results'),
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
            // ── Composite Score card ────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [ActColors.primaryDark, ActColors.primary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  if (settings.studentName != null) ...[
                    Text(settings.studentName!,
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                  ],
                  const Text('ACT Composite Score',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          letterSpacing: 0.5)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('$compositeScore',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 64,
                              fontWeight: FontWeight.w900,
                              height: 1)),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10, left: 4),
                        child: Text('/36',
                            style: TextStyle(
                                color: Colors.white60,
                                fontSize: 22,
                                fontWeight: FontWeight.w400)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: compositeColor.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(20),
                      border:
                          Border.all(color: compositeColor.withOpacity(0.5)),
                    ),
                    child: Text(_compositeLabel(compositeScore),
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                  ),
                  const SizedBox(height: 16),
                  // Target
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      Icon(metTarget ? Icons.emoji_events : Icons.flag_outlined,
                          color: Colors.white70, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(
                        metTarget
                            ? 'You met your target score of $target! Excellent work!'
                            : 'Target: $target · Gap: ${target - compositeScore} points to go',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12, height: 1.4),
                      )),
                    ]),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Per-section scores ──────────────────────────────────────────
            const Text('Section Scores',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),

            ...sectionScores.entries.map((entry) {
              final section = entry.key;
              final scaled = entry.value;
              final results = sectionResults[section] ?? [];
              final raw = results.where((r) => r.isCorrect).length;
              final total = results.length;
              final pct = total == 0 ? 0.0 : raw / total;

              return _SectionScoreCard(
                section: section,
                scaledScore: scaled,
                rawCorrect: raw,
                totalQuestions: total,
                accuracy: pct,
                isDark: isDark,
              );
            }),

            const SizedBox(height: 20),

            // ── Scoring explanation ─────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? ActColors.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color:
                        isDark ? ActColors.darkBorder : ActColors.lightBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('How ACT Scores Work',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 10),
                  _ScoreRangeRow(
                      range: '33–36',
                      label: 'Exceptional',
                      color: const Color(0xFF1B7D4B)),
                  _ScoreRangeRow(
                      range: '26–32',
                      label: 'Above Average',
                      color: const Color(0xFF2E7D32)),
                  _ScoreRangeRow(
                      range: '20–25',
                      label: 'Average (National: ~21)',
                      color: const Color(0xFFD4A017)),
                  _ScoreRangeRow(
                      range: '14–19',
                      label: 'Below Average',
                      color: const Color(0xFFE65100)),
                  _ScoreRangeRow(
                      range: '1–13',
                      label: 'Needs Significant Improvement',
                      color: ActColors.danger),
                  const SizedBox(height: 8),
                  Text(
                    'Composite = average of all section scores (rounded to nearest whole number). '
                    'No penalty for wrong answers — answer every question!',
                    style: TextStyle(
                        fontSize: 11, color: ActColors.midGray, height: 1.4),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Skill breakdown ─────────────────────────────────────────────
            if (_hasSkillData()) ...[
              const Text('Skill Analysis',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              ..._buildSkillBreakdown(isDark),
            ],

            const SizedBox(height: 20),

            // ── Score Prediction ───────────────────────────────────────────
            _ScorePredictionCard(
              compositeScore: compositeScore,
              targetScore: settings.targetScore,
              sectionScores: sectionScores,
              isDark: isDark,
            ),

            const SizedBox(height: 32),

            // Actions
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: ActColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.home_outlined),
                label: const Text('Back to Home',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                onPressed: () => Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                  (_) => false,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.replay),
                label: const Text('Take Another Exam'),
                onPressed: () => Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ExamModeScreenWrapper()),
                  (_) => false,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  String _compositeLabel(int score) {
    if (score >= 34) return 'Exceptional';
    if (score >= 30) return 'Strong Performer';
    if (score >= 26) return 'Above Average';
    if (score >= 21) return 'Average';
    if (score >= 16) return 'Below Average';
    return 'Needs Improvement';
  }

  bool _hasSkillData() {
    return sectionQuestions.values.any((qs) => qs.isNotEmpty);
  }

  List<Widget> _buildSkillBreakdown(bool isDark) {
    final Map<String, int> skillTotal = {};
    final Map<String, int> skillCorrect = {};

    for (final entry in sectionResults.entries) {
      final questions = sectionQuestions[entry.key] ?? [];
      final results = entry.value;
      for (int i = 0; i < min(questions.length, results.length); i++) {
        final skill = questions[i].skillArea;
        skillTotal[skill] = (skillTotal[skill] ?? 0) + 1;
        if (results[i].isCorrect)
          skillCorrect[skill] = (skillCorrect[skill] ?? 0) + 1;
      }
    }

    final skills = skillTotal.entries.map((e) {
      final correct = skillCorrect[e.key] ?? 0;
      return MapEntry(e.key, correct / e.value);
    }).toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    return skills.map((e) {
      final pct = e.value;
      final color = pct >= 0.8
          ? ActColors.success
          : pct >= 0.6
              ? ActColors.warning
              : ActColors.danger;
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? ActColors.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: isDark ? ActColors.darkBorder : ActColors.lightBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child: Text(e.key,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13))),
              Text('${(pct * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 13, color: color)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 6,
                color: color,
                backgroundColor: color.withOpacity(0.12),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
}

int min(int a, int b) => a < b ? a : b;

// Wrapper so "Take Another Exam" re-enters setup flow
/// Goes back to HomeScreen (avoids circular import with exam_mode_screen).
class ExamModeScreenWrapper extends StatelessWidget {
  const ExamModeScreenWrapper({super.key});
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    });
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

// ── Score Prediction Card ──────────────────────────────────────────────────────
// ── Per-section target score defaults ─────────────────────────────────────────
const Map<ActSection, int> _sectionTargetDefaults = {
  ActSection.english: 24,
  ActSection.math: 24,
  ActSection.reading: 24,
  ActSection.science: 24,
};

String _sessionsAdvice(int gap) {
  if (gap <= 0) return 'On track — keep practising to maintain this score.';
  if (gap <= 2)
    return 'Almost there! Review explanations for missed questions.';
  if (gap <= 5)
    return 'Focused daily practice on weak topics will close this gap.';
  if (gap <= 10)
    return 'Work through skill areas one by one. Consistent effort pays off.';
  return 'Start with the foundational skills; build from the basics up.';
}

int _sessionsCount(int gap) {
  if (gap <= 0) return 0;
  if (gap <= 2) return 5;
  if (gap <= 5) return 15;
  if (gap <= 10) return 35;
  return 70;
}

Map<ActSection, List<String>> _sectionTopics = {
  ActSection.english: [
    'Punctuation & Grammar',
    'Sentence Structure',
    'Rhetorical Skills',
    'Word Choice & Style',
    'Essay Organization',
  ],
  ActSection.math: [
    'Pre-Algebra & Number Theory',
    'Algebra & Functions',
    'Geometry & Trigonometry',
    'Statistics & Probability',
    'Coordinate Geometry',
  ],
  ActSection.reading: [
    'Main Idea & Purpose',
    'Detail & Inference',
    'Vocabulary in Context',
    'Comparative Passages',
    'Author\'s Tone & Purpose',
  ],
  ActSection.science: [
    'Data Interpretation',
    'Research Summaries',
    'Conflicting Viewpoints',
    'Scientific Reasoning',
    'Graph & Table Analysis',
  ],
};

class _ScorePredictionCard extends StatelessWidget {
  final int compositeScore, targetScore;
  final Map<ActSection, int> sectionScores;
  final bool isDark;

  const _ScorePredictionCard({
    required this.compositeScore,
    required this.targetScore,
    required this.sectionScores,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final gap = targetScore - compositeScore;
    final metTarget = gap <= 0;
    final cardColor = metTarget ? ActColors.success : ActColors.info;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Composite prediction header ────────────────────────────────────────
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: cardColor.withOpacity(0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cardColor.withOpacity(0.25)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(metTarget ? Icons.emoji_events : Icons.trending_up,
                color: cardColor, size: 20),
            const SizedBox(width: 10),
            Expanded(
                child: Text('Score Prediction & Study Path',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: cardColor))),
          ]),
          const SizedBox(height: 14),

          // Composite gauge
          Row(children: [
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('Composite Score',
                      style: TextStyle(fontSize: 11, color: ActColors.midGray)),
                  Text('$compositeScore / 36',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color:
                              ActColors.scoreColor(compositeScore.toDouble()),
                          height: 1.1)),
                  Text(_scoreLabel(compositeScore),
                      style: TextStyle(
                          fontSize: 11,
                          color:
                              ActColors.scoreColor(compositeScore.toDouble()),
                          fontWeight: FontWeight.w600)),
                ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('Your Target',
                  style: TextStyle(fontSize: 11, color: ActColors.midGray)),
              Text('$targetScore / 36',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: ActColors.scoreColor(targetScore.toDouble()),
                      height: 1.1)),
              Text(metTarget ? '✓ Achieved!' : 'Gap: $gap pts',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color:
                          metTarget ? ActColors.success : ActColors.warning)),
            ]),
          ]),
          const SizedBox(height: 12),

          // Progress bar with target line
          Stack(children: [
            ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                  value: compositeScore / 36,
                  minHeight: 10,
                  color: ActColors.scoreColor(compositeScore.toDouble()),
                  backgroundColor:
                      ActColors.scoreColor(compositeScore.toDouble())
                          .withOpacity(0.12),
                )),
            FractionallySizedBox(
                widthFactor: (targetScore / 36).clamp(0.0, 1.0),
                child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                        border: Border(
                            right: BorderSide(
                                color: ActColors.primary, width: 2.5))))),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            Text('1', style: TextStyle(fontSize: 9, color: ActColors.midGray)),
            const Spacer(),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: ActColors.primary.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(4)),
                child: Text('Target $targetScore',
                    style: TextStyle(
                        fontSize: 9,
                        color: ActColors.primary,
                        fontWeight: FontWeight.w700))),
            const Spacer(),
            Text('36', style: TextStyle(fontSize: 9, color: ActColors.midGray)),
          ]),

          if (!metTarget) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: cardColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_sessionsAdvice(gap),
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cardColor)),
                    const SizedBox(height: 5),
                    Text(
                        'Est. focused practice sessions needed: ~${_sessionsCount(gap)}',
                        style:
                            TextStyle(fontSize: 11, color: ActColors.midGray)),
                  ]),
            ),
          ],

          // College ranges
          const SizedBox(height: 14),
          Text('What this composite means:',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: ActColors.midGray)),
          const SizedBox(height: 6),
          ..._collegeRanges(compositeScore),
        ]),
      ),

      // ── Per-section predictions ────────────────────────────────────────────
      const SizedBox(height: 16),
      const Text('Subject Score Predictions',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),

      ...sectionScores.entries.map((e) => _SubjectPredictionCard(
            section: e.key,
            scaledScore: e.value,
            isDark: isDark,
          )),
    ]);
  }

  String _scoreLabel(int s) {
    if (s >= 34) return 'Exceptional';
    if (s >= 30) return 'Strong Performer';
    if (s >= 26) return 'Above Average';
    if (s >= 21) return 'Average';
    if (s >= 16) return 'Below Average';
    return 'Needs Improvement';
  }

  List<Widget> _collegeRanges(int score) {
    final tiers = [
      _CollegeTier('Elite — MIT, Harvard, Stanford', 34, 36),
      _CollegeTier('Highly Competitive — UCLA, Michigan', 31, 33),
      _CollegeTier('Competitive — State Flagships', 26, 30),
      _CollegeTier('Average College Admissions', 20, 25),
      _CollegeTier('Open Enrollment', 1, 19),
    ];
    return tiers.map((t) {
      final inRange = score >= t.min && score <= t.max;
      final color = ActColors.scoreColor(score.toDouble());
      return Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: inRange ? color.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: inRange ? Border.all(color: color.withOpacity(0.3)) : null,
        ),
        child: Row(children: [
          SizedBox(
              width: 44,
              child: Text('${t.min}–${t.max}',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: inRange ? color : ActColors.midGray))),
          const SizedBox(width: 8),
          Expanded(
              child: Text(t.label,
                  style: TextStyle(
                      fontSize: 11,
                      color: inRange ? color : ActColors.midGray,
                      fontWeight:
                          inRange ? FontWeight.w700 : FontWeight.normal))),
          if (inRange) Icon(Icons.place, size: 12, color: color),
        ]),
      );
    }).toList();
  }
}

class _CollegeTier {
  final String label;
  final int min, max;
  const _CollegeTier(this.label, this.min, this.max);
}

// ── Per-subject prediction card ────────────────────────────────────────────────
class _SubjectPredictionCard extends StatelessWidget {
  final ActSection section;
  final int scaledScore;
  final bool isDark;

  const _SubjectPredictionCard({
    required this.section,
    required this.scaledScore,
    required this.isDark,
  });

  Color get _sectionColor {
    switch (section) {
      case ActSection.math:
        return const Color(0xFF1565C0);
      case ActSection.reading:
        return const Color(0xFF2E7D32);
      case ActSection.science:
        return const Color(0xFF6A1B9A);
      default:
        return ActColors.primary;
    }
  }

  IconData get _icon {
    switch (section) {
      case ActSection.math:
        return Icons.functions_outlined;
      case ActSection.reading:
        return Icons.menu_book_outlined;
      case ActSection.science:
        return Icons.science_outlined;
      default:
        return Icons.edit_note_outlined;
    }
  }

  // What score to aim for per section (composite target is avg of all)
  int get _sectionTarget {
    if (scaledScore >= 30) return (scaledScore + 3).clamp(1, 36);
    if (scaledScore >= 24) return (scaledScore + 4).clamp(1, 36);
    if (scaledScore >= 18) return (scaledScore + 5).clamp(1, 36);
    return (scaledScore + 6).clamp(1, 36);
  }

  String _sectionAdvice(int score) {
    switch (section) {
      case ActSection.english:
        if (score >= 30)
          return 'Excellent! Review rhetorical skills and complex sentence structure.';
        if (score >= 24)
          return 'Strong foundation. Focus on punctuation rules and transitions.';
        if (score >= 18)
          return 'Practice grammar rules daily. Read published essays for style.';
        return 'Start with subject-verb agreement, commas, and basic sentence structure.';
      case ActSection.math:
        if (score >= 30)
          return 'Excellent! Refine trigonometry, complex numbers, and logs.';
        if (score >= 24)
          return 'Good base. Work on coordinate geometry and advanced algebra.';
        if (score >= 18)
          return 'Strengthen algebra and geometry. Practice time management.';
        return 'Master pre-algebra, fractions, and basic equations first.';
      case ActSection.reading:
        if (score >= 30)
          return 'Strong! Work on timing — practice 35 min / 4 passages strictly.';
        if (score >= 24)
          return 'Good comprehension. Focus on inference questions and vocab in context.';
        if (score >= 18)
          return 'Read more diverse texts. Practice finding main ideas quickly.';
        return 'Read daily — newspapers, essays. Build reading speed and retention.';
      case ActSection.science:
        if (score >= 30)
          return 'Excellent! Focus on conflicting viewpoints and complex graph sets.';
        if (score >= 24)
          return 'Good data skills. Practice multi-figure graph interpretation.';
        if (score >= 18)
          return 'Work on reading data tables and research summary questions.';
        return 'Remember: no science knowledge needed — it\'s all about reading data.';
    }
  }

  List<String> _focusTopics(int score) {
    final topics = _sectionTopics[section] ?? [];
    // Return the most relevant 2-3 topics based on score level
    if (score >= 30) return topics.skip(3).toList();
    if (score >= 24) return topics.skip(2).take(3).toList();
    if (score >= 18) return topics.skip(1).take(3).toList();
    return topics.take(3).toList();
  }

  @override
  Widget build(BuildContext context) {
    final gap = _sectionTarget - scaledScore;
    final met = gap <= 0;
    final scoreColor = ActColors.scoreColor(scaledScore.toDouble());
    final topics = _focusTopics(scaledScore);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? ActColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: met
                ? ActColors.success.withOpacity(0.3)
                : _sectionColor.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header row
        Row(children: [
          Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: _sectionColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(_icon, color: _sectionColor, size: 18)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(actSectionDisplayName(section),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 13)),
                Text(
                    met
                        ? 'On target!'
                        : 'Next goal: $_sectionTarget / 36  (+$gap pts)',
                    style: TextStyle(
                        fontSize: 11,
                        color: met ? ActColors.success : ActColors.midGray,
                        fontWeight: met ? FontWeight.w700 : FontWeight.normal)),
              ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('$scaledScore',
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: scoreColor,
                    height: 1)),
            Text('/36',
                style: TextStyle(fontSize: 11, color: ActColors.midGray)),
          ]),
        ]),

        const SizedBox(height: 10),

        // Score bar with next-goal marker
        Stack(children: [
          ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: scaledScore / 36,
                minHeight: 8,
                color: _sectionColor,
                backgroundColor: _sectionColor.withOpacity(0.10),
              )),
          if (!met)
            FractionallySizedBox(
                widthFactor: (_sectionTarget / 36).clamp(0.0, 1.0),
                child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                        border: Border(
                            right:
                                BorderSide(color: _sectionColor, width: 2))))),
        ]),

        const SizedBox(height: 10),

        // Advice
        Text(_sectionAdvice(scaledScore),
            style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: isDark ? Colors.white70 : Colors.black87)),

        if (topics.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Focus topics:',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: ActColors.midGray)),
          const SizedBox(height: 6),
          Wrap(
              spacing: 6,
              runSpacing: 6,
              children: topics
                  .map((t) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: _sectionColor.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: _sectionColor.withOpacity(0.25)),
                        ),
                        child: Text(t,
                            style: TextStyle(
                                fontSize: 10,
                                color: _sectionColor,
                                fontWeight: FontWeight.w600)),
                      ))
                  .toList()),
        ],

        if (!met) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
                color: _sectionColor.withOpacity(0.06),
                borderRadius: BorderRadius.circular(6)),
            child: Row(children: [
              Icon(Icons.schedule_outlined, size: 13, color: _sectionColor),
              const SizedBox(width: 6),
              Text(
                  '~${_sessionsCount(gap)} focused sessions to reach $_sectionTarget',
                  style: TextStyle(
                      fontSize: 11,
                      color: _sectionColor,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _SectionScoreCard extends StatelessWidget {
  final ActSection section;
  final int scaledScore, rawCorrect, totalQuestions;
  final double accuracy;
  final bool isDark;

  const _SectionScoreCard({
    required this.section,
    required this.scaledScore,
    required this.rawCorrect,
    required this.totalQuestions,
    required this.accuracy,
    required this.isDark,
  });

  Color get _sectionColor {
    switch (section) {
      case ActSection.math:
        return const Color(0xFF1565C0);
      case ActSection.reading:
        return const Color(0xFF2E7D32);
      case ActSection.science:
        return const Color(0xFF6A1B9A);
      default:
        return ActColors.primary;
    }
  }

  IconData get _sectionIcon {
    switch (section) {
      case ActSection.math:
        return Icons.functions_outlined;
      case ActSection.reading:
        return Icons.menu_book_outlined;
      case ActSection.science:
        return Icons.science_outlined;
      default:
        return Icons.edit_note_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scoreColor = ActColors.scoreColor(scaledScore.toDouble());
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? ActColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark ? ActColors.darkBorder : ActColors.lightBorder),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _sectionColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(_sectionIcon, color: _sectionColor, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(actSectionDisplayName(section),
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 4),
            Text(
                '$rawCorrect / $totalQuestions correct · ${(accuracy * 100).toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 12, color: ActColors.midGray)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: accuracy,
                minHeight: 5,
                color: _sectionColor,
                backgroundColor: _sectionColor.withOpacity(0.12),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 14),
        Column(children: [
          Text('$scaledScore',
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 30,
                  color: scoreColor,
                  height: 1)),
          Text('/36', style: TextStyle(fontSize: 12, color: ActColors.midGray)),
        ]),
      ]),
    );
  }
}

class _ScoreRangeRow extends StatelessWidget {
  final String range, label;
  final Color color;
  const _ScoreRangeRow(
      {required this.range, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Container(
            width: 52,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(range,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: color)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
        ]),
      );
}
