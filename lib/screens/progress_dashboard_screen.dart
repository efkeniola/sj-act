import 'package:flutter/material.dart';

import '../data/questions_data.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/exam_settings_service.dart';
import '../utils/theme.dart';

// ════════════════════════════════════════════════════════════════════════════
// Progress Dashboard — full score prediction, per-subject analysis,
// weak topics, study plan, college ranges.
// Accessible from the home screen score card.
// ════════════════════════════════════════════════════════════════════════════

class ProgressDashboardScreen extends StatefulWidget {
  const ProgressDashboardScreen({super.key});
  @override
  State<ProgressDashboardScreen> createState() =>
      _ProgressDashboardScreenState();
}

class _ProgressDashboardScreenState extends State<ProgressDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _loading = true;

  // Aggregated data
  double _compositeScore = 0;
  int _targetScore = 28;
  int _totalSessions = 0;
  int _totalQuestions = 0;
  double _overallAccuracy = 0;

  // Per-section best scaled scores
  Map<ActSection, double> _sectionBest = {};
  // Per-section accuracy across all attempts
  Map<ActSection, double> _sectionAccuracy = {};
  // Per-section attempt count
  Map<ActSection, int> _sectionAttempts = {};
  // Per-skill accuracy
  Map<ActSection, Map<String, _SkillStat>> _skillStats = {};

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final attempts = await DatabaseService.instance.getAllAttempts();
    final target = await ExamSettingsService.getTargetScore();

    // Aggregate per section
    final Map<ActSection, List<double>> sectionScores = {};
    final Map<ActSection, int> sectionCorrect = {};
    final Map<ActSection, int> sectionTotal = {};

    // Per-skill tracking using questions_data to look up skillArea
    final Map<ActSection, Map<String, _SkillStat>> skillMap = {
      for (final s in ActSection.values) s: {}
    };

    for (final attempt in attempts) {
      final sec = attempt.section;
      if (sec == null) continue;

      sectionScores.putIfAbsent(sec, () => []);
      sectionScores[sec]!.add(attempt.actScaledScore);
      sectionCorrect[sec] = (sectionCorrect[sec] ?? 0) + attempt.correctCount;
      sectionTotal[sec] = (sectionTotal[sec] ?? 0) + attempt.totalCount;

      // Match results to questions by index (best-effort)
      final questions = questionsForSection(sec);
      for (int i = 0; i < attempt.results.length; i++) {
        final skill = i < questions.length ? questions[i].skillArea : 'General';
        skillMap[sec]!.putIfAbsent(skill, () => _SkillStat(skill));
        skillMap[sec]![skill]!.total++;
        if (attempt.results[i].isCorrect) skillMap[sec]![skill]!.correct++;
      }
    }

    // Build section best
    final Map<ActSection, double> sectionBest = {};
    final Map<ActSection, double> sectionAcc = {};
    final Map<ActSection, int> sectionAttemptCount = {};

    for (final s in ActSection.values) {
      final scores = sectionScores[s] ?? [];
      if (scores.isNotEmpty) {
        sectionBest[s] = scores.reduce((a, b) => a > b ? a : b);
      }
      final c = sectionCorrect[s] ?? 0;
      final t = sectionTotal[s] ?? 0;
      sectionAcc[s] = t == 0 ? 0 : c / t;
      sectionAttemptCount[s] = (sectionScores[s] ?? []).length;
    }

    // Composite = average of section bests (only sections attempted)
    final attempted = sectionBest.values.toList();
    final composite = attempted.isEmpty
        ? 0.0
        : attempted.reduce((a, b) => a + b) / attempted.length;

    final totalQ = sectionTotal.values.fold(0, (a, b) => a + b);
    final totalC = sectionCorrect.values.fold(0, (a, b) => a + b);

    if (!mounted) return;
    setState(() {
      _compositeScore = composite;
      _targetScore = target;
      _totalSessions = attempts.length;
      _totalQuestions = totalQ;
      _overallAccuracy = totalQ == 0 ? 0 : totalC / totalQ;
      _sectionBest = sectionBest;
      _sectionAccuracy = sectionAcc;
      _sectionAttempts = sectionAttemptCount;
      _skillStats = skillMap;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Score Prediction & Progress'),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: Colors.white,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Subjects'),
            Tab(text: 'Weak Topics'),
            Tab(text: 'Study Plan'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _totalSessions == 0
              ? _EmptyState()
              : TabBarView(
                  controller: _tab,
                  children: [
                    _OverviewTab(
                      composite: _compositeScore,
                      target: _targetScore,
                      sessions: _totalSessions,
                      totalQ: _totalQuestions,
                      accuracy: _overallAccuracy,
                      sectionBest: _sectionBest,
                      isDark: isDark,
                    ),
                    _SubjectsTab(
                      sectionBest: _sectionBest,
                      sectionAccuracy: _sectionAccuracy,
                      sectionAttempts: _sectionAttempts,
                      target: _targetScore,
                      isDark: isDark,
                    ),
                    _WeakTopicsTab(
                      skillStats: _skillStats,
                      isDark: isDark,
                    ),
                    _StudyPlanTab(
                      composite: _compositeScore,
                      target: _targetScore,
                      sectionBest: _sectionBest,
                      isDark: isDark,
                    ),
                  ],
                ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 1 — Overview
// ─────────────────────────────────────────────────────────────────────────────
class _OverviewTab extends StatelessWidget {
  final double composite, accuracy;
  final int target, sessions, totalQ;
  final Map<ActSection, double> sectionBest;
  final bool isDark;

  const _OverviewTab({
    required this.composite,
    required this.target,
    required this.sessions,
    required this.totalQ,
    required this.accuracy,
    required this.sectionBest,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final score = composite.round();
    final gap = target - score;
    final metTarget = gap <= 0;
    final color = ActColors.scoreColor(composite);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Big composite card ────────────────────────────────────────────
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
          child: Column(children: [
            const Text('ACT Composite Score',
                style: TextStyle(
                    color: Colors.white70, fontSize: 13, letterSpacing: 0.5)),
            const SizedBox(height: 12),
            Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$score',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 72,
                          fontWeight: FontWeight.w900,
                          height: 1)),
                  Padding(
                      padding: const EdgeInsets.only(bottom: 12, left: 4),
                      child: Text('/36',
                          style: TextStyle(
                              color: Colors.white60,
                              fontSize: 22,
                              fontWeight: FontWeight.w300))),
                ]),
            const SizedBox(height: 6),
            Text(_scoreLabel(score),
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 16),
            // Target row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                            ? 'You\'ve met your target of $target!'
                            : 'Target: $target  ·  Gap: $gap points',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13))),
              ]),
            ),
          ]),
        ),

        const SizedBox(height: 20),

        // ── Stats row ─────────────────────────────────────────────────────
        Row(children: [
          _MiniStat(
              label: 'Sessions',
              value: '$sessions',
              icon: Icons.assignment_outlined),
          const SizedBox(width: 8),
          _MiniStat(
              label: 'Questions', value: '$totalQ', icon: Icons.quiz_outlined),
          const SizedBox(width: 8),
          _MiniStat(
              label: 'Accuracy',
              value: '${(accuracy * 100).toStringAsFixed(0)}%',
              icon: Icons.track_changes_outlined),
        ]),

        const SizedBox(height: 20),

        // ── Progress bar toward 36 ────────────────────────────────────────
        _SectionHeader('Score vs Target'),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardDecor(isDark),
          child: Column(children: [
            Row(children: [
              Text('$score',
                  style: TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 20, color: color)),
              const Spacer(),
              Text('Target: $target',
                  style: TextStyle(
                      fontSize: 12,
                      color: ActColors.primary,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              const Text('36',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ]),
            const SizedBox(height: 8),
            Stack(children: [
              ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                      value: composite / 36,
                      minHeight: 14,
                      color: color,
                      backgroundColor: color.withOpacity(0.10))),
              FractionallySizedBox(
                  widthFactor: (target / 36).clamp(0.0, 1.0),
                  child: Container(
                      height: 14,
                      decoration: BoxDecoration(
                          border: Border(
                              right: BorderSide(
                                  color: ActColors.primary, width: 2.5))))),
            ]),
            const SizedBox(height: 8),
            Text(_collegeRange(score),
                style: TextStyle(
                    fontSize: 12, color: ActColors.midGray, height: 1.4)),
          ]),
        ),

        const SizedBox(height: 20),

        // ── Section radar-style bars ──────────────────────────────────────
        _SectionHeader('Section Scores'),
        ...ActSection.values.map((s) {
          final best = sectionBest[s];
          if (best == null) return const SizedBox.shrink();
          return _SectionBarRow(section: s, score: best, isDark: isDark);
        }),

        const SizedBox(height: 20),

        // ── College ranges ────────────────────────────────────────────────
        _SectionHeader('What Your Score Means'),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardDecor(isDark),
          child: Column(children: [
            ..._collegeTiers.map((t) {
              final inRange = score >= t.min && score <= t.max;
              final c = ActColors.scoreColor((t.min + t.max) / 2);
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: inRange ? c.withOpacity(0.10) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border:
                      inRange ? Border.all(color: c.withOpacity(0.35)) : null,
                ),
                child: Row(children: [
                  SizedBox(
                      width: 48,
                      child: Text('${t.min}–${t.max}',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: inRange ? c : ActColors.midGray))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(t.label,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight:
                                  inRange ? FontWeight.w700 : FontWeight.normal,
                              color: inRange ? c : null))),
                  if (inRange) Icon(Icons.place, size: 14, color: c),
                ]),
              );
            }),
          ]),
        ),

        const SizedBox(height: 24),
      ]),
    );
  }

  String _scoreLabel(int s) {
    if (s >= 34) return 'Exceptional';
    if (s >= 30) return 'Strong Performer';
    if (s >= 26) return 'Above Average';
    if (s >= 21) return 'Average';
    if (s >= 16) return 'Below Average';
    return 'Needs Improvement';
  }

  String _collegeRange(int s) {
    if (s >= 34) return 'Elite universities (MIT, Harvard, Stanford)';
    if (s >= 31) return 'Highly competitive colleges (UCLA, Michigan)';
    if (s >= 26) return 'Competitive — state flagship universities';
    if (s >= 20) return 'Average college admissions range';
    return 'Open enrollment / community college range';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 2 — Subjects
// ─────────────────────────────────────────────────────────────────────────────
class _SubjectsTab extends StatelessWidget {
  final Map<ActSection, double> sectionBest, sectionAccuracy;
  final Map<ActSection, int> sectionAttempts;
  final int target;
  final bool isDark;

  const _SubjectsTab({
    required this.sectionBest,
    required this.sectionAccuracy,
    required this.sectionAttempts,
    required this.target,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Tap a subject to see detailed predictions.',
            style: TextStyle(fontSize: 12, color: ActColors.midGray)),
        const SizedBox(height: 14),
        ...ActSection.values.map((s) => _SubjectDetailCard(
              section: s,
              bestScore: sectionBest[s] ?? 0,
              accuracy: sectionAccuracy[s] ?? 0,
              attempts: sectionAttempts[s] ?? 0,
              isDark: isDark,
            )),
      ]),
    );
  }
}

class _SubjectDetailCard extends StatefulWidget {
  final ActSection section;
  final double bestScore, accuracy;
  final int attempts;
  final bool isDark;

  const _SubjectDetailCard({
    required this.section,
    required this.bestScore,
    required this.accuracy,
    required this.attempts,
    required this.isDark,
  });

  @override
  State<_SubjectDetailCard> createState() => _SubjectDetailCardState();
}

class _SubjectDetailCardState extends State<_SubjectDetailCard> {
  bool _expanded = false;

  Color get _color {
    switch (widget.section) {
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
    switch (widget.section) {
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

  int get _nextGoal {
    final s = widget.bestScore.round();
    if (s >= 30) return (s + 3).clamp(1, 36);
    if (s >= 24) return (s + 4).clamp(1, 36);
    if (s >= 18) return (s + 5).clamp(1, 36);
    return (s + 6).clamp(1, 36);
  }

  String _advice(int score) {
    switch (widget.section) {
      case ActSection.english:
        if (score >= 30)
          return 'Review rhetorical skills and complex sentence structure for top marks.';
        if (score >= 24)
          return 'Focus on punctuation rules, transitions, and sentence combining.';
        if (score >= 18)
          return 'Practise grammar rules daily. Study commas, colons, and semicolons.';
        return 'Start with subject-verb agreement, commas, and basic sentence structure.';
      case ActSection.math:
        if (score >= 30)
          return 'Refine trigonometry, complex numbers, logarithms, and matrices.';
        if (score >= 24)
          return 'Work on coordinate geometry, advanced algebra, and statistics.';
        if (score >= 18)
          return 'Strengthen algebra and geometry. Practise time management.';
        return 'Master pre-algebra, fractions, ratios, and basic equations first.';
      case ActSection.reading:
        if (score >= 30)
          return 'Practise timing — 35 min / 4 passages. Focus on dual passages.';
        if (score >= 24)
          return 'Focus on inference questions and vocabulary in context.';
        if (score >= 18)
          return 'Read diverse texts daily. Practise finding the main idea quickly.';
        return 'Build reading speed with newspapers and essays. Focus on retention.';
      case ActSection.science:
        if (score >= 30)
          return 'Focus on conflicting viewpoints passages and complex multi-graph sets.';
        if (score >= 24)
          return 'Practise multi-figure graph interpretation and experiment design.';
        if (score >= 18)
          return 'Work on data table reading and research summary questions.';
        return 'No science knowledge needed — it\'s all about reading graphs and data.';
    }
  }

  List<String> _topics(int score) {
    final all = _allTopics[widget.section] ?? [];
    if (score >= 30) return all.sublist(all.length - 2);
    if (score >= 24) return all.sublist(2, 5).take(3).toList();
    if (score >= 18) return all.sublist(1, 4);
    return all.take(3).toList();
  }

  @override
  Widget build(BuildContext context) {
    final score = widget.bestScore.round();
    final gap = _nextGoal - score;
    final scoreColor = ActColors.scoreColor(widget.bestScore);
    final notAttempted = widget.attempts == 0;

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: widget.isDark ? ActColors.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: notAttempted
                  ? (widget.isDark
                      ? ActColors.darkBorder
                      : ActColors.lightBorder)
                  : _color.withOpacity(0.25)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _color.withOpacity(notAttempted ? 0.05 : 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_icon,
                  color: notAttempted ? ActColors.midGray : _color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(actSectionDisplayName(widget.section),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 14)),
                  Text(
                      notAttempted
                          ? 'Not attempted yet'
                          : '${widget.attempts} session${widget.attempts != 1 ? 's' : ''} · ${(widget.accuracy * 100).toStringAsFixed(0)}% accuracy',
                      style: TextStyle(fontSize: 11, color: ActColors.midGray)),
                ])),
            if (!notAttempted) ...[
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('$score',
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 28,
                        color: scoreColor,
                        height: 1)),
                Text('/36',
                    style: TextStyle(fontSize: 11, color: ActColors.midGray)),
              ]),
            ],
            const SizedBox(width: 8),
            Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                color: ActColors.midGray, size: 20),
          ]),

          if (!notAttempted) ...[
            const SizedBox(height: 12),
            // Score bar
            Stack(children: [
              ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                      value: widget.bestScore / 36,
                      minHeight: 8,
                      color: _color,
                      backgroundColor: _color.withOpacity(0.10))),
              FractionallySizedBox(
                  widthFactor: (_nextGoal / 36).clamp(0.0, 1.0),
                  child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                          border: Border(
                              right: BorderSide(color: _color, width: 2))))),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Text('Score: $score',
                  style: TextStyle(fontSize: 10, color: ActColors.midGray)),
              const Spacer(),
              Text('Next goal: $_nextGoal (+$gap pts)',
                  style: TextStyle(
                      fontSize: 10,
                      color: _color,
                      fontWeight: FontWeight.w700)),
            ]),
          ],

          // Expanded detail
          if (_expanded && !notAttempted) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 14),

            // Advice
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _color.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_advice(score),
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: widget.isDark ? Colors.white70 : Colors.black87)),
            ),

            // Focus topics
            const SizedBox(height: 12),
            Text('Focus Topics:',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: ActColors.midGray)),
            const SizedBox(height: 6),
            Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _topics(score)
                    .map((t) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: _color.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: _color.withOpacity(0.25)),
                          ),
                          child: Text(t,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: _color,
                                  fontWeight: FontWeight.w600)),
                        ))
                    .toList()),

            // Sessions estimate
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  color: _color.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Icon(Icons.schedule_outlined, size: 14, color: _color),
                const SizedBox(width: 8),
                Text('~${_sessions(gap)} focused sessions to reach $_nextGoal',
                    style: TextStyle(
                        fontSize: 12,
                        color: _color,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ],

          if (_expanded && notAttempted) ...[
            const SizedBox(height: 12),
            Text(
                'Complete a practice session in this subject to see your predictions.',
                style: TextStyle(
                    fontSize: 12, color: ActColors.midGray, height: 1.4)),
          ],
        ]),
      ),
    );
  }

  int _sessions(int gap) {
    if (gap <= 2) return 5;
    if (gap <= 5) return 15;
    if (gap <= 10) return 35;
    return 70;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 3 — Weak Topics
// ─────────────────────────────────────────────────────────────────────────────
class _WeakTopicsTab extends StatelessWidget {
  final Map<ActSection, Map<String, _SkillStat>> skillStats;
  final bool isDark;

  const _WeakTopicsTab({required this.skillStats, required this.isDark});

  @override
  Widget build(BuildContext context) {
    // Collect all skills, sorted weakest first
    final all = <_SkillRow>[];
    for (final sec in ActSection.values) {
      final skills = skillStats[sec] ?? {};
      for (final stat in skills.values) {
        if (stat.total > 0) {
          all.add(_SkillRow(section: sec, stat: stat));
        }
      }
    }
    all.sort((a, b) => a.stat.accuracy.compareTo(b.stat.accuracy));

    final weak = all.where((r) => r.stat.accuracy < 0.6).toList();
    final medium = all
        .where((r) => r.stat.accuracy >= 0.6 && r.stat.accuracy < 0.8)
        .toList();
    final strong = all.where((r) => r.stat.accuracy >= 0.8).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (all.isEmpty)
          _EmptyState()
        else ...[
          if (weak.isNotEmpty) ...[
            _SectionHeader('Needs Work  ⚠️'),
            ...weak.map((r) => _SkillStatTile(row: r, isDark: isDark)),
          ],
          if (medium.isNotEmpty) ...[
            _SectionHeader('Developing  📈'),
            ...medium.map((r) => _SkillStatTile(row: r, isDark: isDark)),
          ],
          if (strong.isNotEmpty) ...[
            _SectionHeader('Strong  ✅'),
            ...strong.map((r) => _SkillStatTile(row: r, isDark: isDark)),
          ],
        ],
        const SizedBox(height: 24),
      ]),
    );
  }
}

class _SkillStatTile extends StatelessWidget {
  final _SkillRow row;
  final bool isDark;
  const _SkillStatTile({required this.row, required this.isDark});

  Color get _sectionColor {
    switch (row.section) {
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

  @override
  Widget build(BuildContext context) {
    final pct = row.stat.accuracy;
    final barColor = pct >= 0.8
        ? ActColors.success
        : pct >= 0.6
            ? ActColors.warning
            : ActColors.danger;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? ActColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isDark ? ActColors.darkBorder : ActColors.lightBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: _sectionColor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
                actSectionDisplayName(row.section)
                    .substring(0, 3)
                    .toUpperCase(),
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: _sectionColor)),
          ),
          const SizedBox(width: 8),
          Expanded(
              child: Text(row.stat.skill,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13))),
          Text('${row.stat.correct}/${row.stat.total}',
              style: TextStyle(fontSize: 11, color: ActColors.midGray)),
          const SizedBox(width: 8),
          Text('${(pct * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 13, color: barColor)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
                value: pct,
                minHeight: 6,
                color: barColor,
                backgroundColor: barColor.withOpacity(0.10))),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 4 — Study Plan
// ─────────────────────────────────────────────────────────────────────────────
class _StudyPlanTab extends StatelessWidget {
  final double composite;
  final int target;
  final Map<ActSection, double> sectionBest;
  final bool isDark;

  const _StudyPlanTab({
    required this.composite,
    required this.target,
    required this.sectionBest,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final score = composite.round();
    final gap = target - score;
    final weeks = _weeksNeeded(gap);

    // Sort sections weakest first
    final ranked = ActSection.values
        .where((s) => sectionBest.containsKey(s))
        .toList()
      ..sort((a, b) => (sectionBest[a] ?? 0).compareTo(sectionBest[b] ?? 0));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Summary
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [ActColors.primaryDark, ActColors.primary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Your Study Plan',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16)),
            const SizedBox(height: 6),
            Text(
                gap <= 0
                    ? 'You\'ve reached your target! Set a new goal in Settings.'
                    : 'To go from $score → $target (${gap > 0 ? '+$gap' : '$gap'} pts), estimated $weeks weeks of focused study.',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.88),
                    fontSize: 12,
                    height: 1.5)),
          ]),
        ),

        const SizedBox(height: 20),
        _SectionHeader('Weekly Focus Plan'),

        // Week-by-week plan
        ..._buildWeekPlan(ranked, gap),

        const SizedBox(height: 20),
        _SectionHeader('Daily Habits That Work'),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardDecor(isDark),
          child: Column(children: [
            _HabitRow('📖', 'Read 1 ACT passage daily (timed, 8 min)', isDark),
            _HabitRow('✏️', 'Solve 10 Math questions per day', isDark),
            _HabitRow('🔍', 'Review every wrong answer — read the explanation',
                isDark),
            _HabitRow(
                '⏱️', 'Practise under real time pressure once a week', isDark),
            _HabitRow('📊', 'Track your weak topics here weekly', isDark),
            _HabitRow(
                '🎯', 'Take 1 full exam per month to measure progress', isDark),
          ]),
        ),

        const SizedBox(height: 20),
        _SectionHeader('Score Improvement Timeline'),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardDecor(isDark),
          child: Column(children: [
            _TimelineRow(
                '1–2 weeks',
                'Learn your weak skill areas. Stop losing easy points.',
                isDark),
            _TimelineRow(
                '3–4 weeks',
                'Practise weak topics daily. Aim for 80%+ on those skills.',
                isDark),
            _TimelineRow('5–8 weeks',
                'Full timed sections. Build stamina and pace.', isDark),
            _TimelineRow(
                '8–12 weeks',
                'Full mock exams. Refine timing and test-taking strategy.',
                isDark),
            _TimelineRow(
                '12+ weeks',
                'Maintain and consolidate. Small gains from consistent review.',
                isDark),
          ]),
        ),

        const SizedBox(height: 32),
      ]),
    );
  }

  int _weeksNeeded(int gap) {
    if (gap <= 0) return 0;
    if (gap <= 2) return 2;
    if (gap <= 4) return 4;
    if (gap <= 6) return 8;
    if (gap <= 10) return 12;
    return 20;
  }

  List<Widget> _buildWeekPlan(List<ActSection> ranked, int gap) {
    if (gap <= 0) {
      return [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: ActColors.success.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: ActColors.success.withOpacity(0.25)),
          ),
          child: Row(children: [
            Icon(Icons.emoji_events, color: ActColors.success, size: 22),
            const SizedBox(width: 12),
            Expanded(
                child: Text(
                    'Target achieved! Keep practising to maintain your score.',
                    style: TextStyle(
                        fontSize: 13,
                        color: ActColors.success,
                        fontWeight: FontWeight.w600))),
          ]),
        )
      ];
    }

    final plans = <Widget>[];
    int week = 1;
    // Prioritise weakest sections
    for (int i = 0; i < ranked.length && week <= 8; i++) {
      final s = ranked[i];
      final weekLabel =
          ranked.length == 1 ? 'Weeks $week–${week + 1}' : 'Week $week';
      plans.add(_WeekCard(
        week: weekLabel,
        section: actSectionDisplayName(s),
        tasks: _weekTasks(s, (sectionBest[s] ?? 0).round()),
        color: _sectionColor(s),
        isDark: isDark,
      ));
      week += ranked.length == 1 ? 2 : 1;
    }
    // Wrap-up week
    plans.add(_WeekCard(
      week: 'Final Weeks',
      section: 'Full Exam Practice',
      tasks: [
        'Take 1 complete timed exam',
        'Review all missed questions',
        'Focus on your weakest section',
        'Check score vs target'
      ],
      color: ActColors.primary,
      isDark: isDark,
    ));
    return plans;
  }

  List<String> _weekTasks(ActSection s, int score) {
    switch (s) {
      case ActSection.english:
        if (score < 18)
          return [
            'Review comma rules & apostrophes',
            'Practice subject-verb agreement',
            '20 English questions/day',
            'Read explanation for every miss'
          ];
        return [
          'Study transitions & rhetoric',
          'Practice word choice questions',
          'Time: 45 min / 75 questions',
          '30 English questions/day'
        ];
      case ActSection.math:
        if (score < 18)
          return [
            'Review fractions, percentages, ratios',
            'Practice linear equations',
            '15 Math questions/day',
            'No calculator for basic arithmetic'
          ];
        return [
          'Study coordinate geometry',
          'Practice trig basics (sin/cos/tan)',
          'Time: 60 min / 60 questions',
          '20 Math questions/day'
        ];
      case ActSection.reading:
        if (score < 18)
          return [
            'Read 1 article daily (8 min max)',
            'Practice main-idea questions',
            'Skip & return on hard questions',
            'Summarise each passage in 1 sentence'
          ];
        return [
          'Practice dual-passage questions',
          'Inference and vocab-in-context',
          'Strict timing: 8–9 min/passage',
          '1 full reading section/day'
        ];
      case ActSection.science:
        return [
          'Read graphs before reading text',
          'Practice data-representation Qs',
          'Conflicting viewpoints strategy',
          '1 full science section/day'
        ];
    }
  }

  Color _sectionColor(ActSection s) {
    switch (s) {
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
}

class _WeekCard extends StatelessWidget {
  final String week, section;
  final List<String> tasks;
  final Color color;
  final bool isDark;
  const _WeekCard(
      {required this.week,
      required this.section,
      required this.tasks,
      required this.color,
      required this.isDark});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? ActColors.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(week,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800, color: color)),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Text(section,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13))),
          ]),
          const SizedBox(height: 10),
          ...tasks.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check_box_outline_blank,
                          size: 16, color: color),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(t,
                              style:
                                  const TextStyle(fontSize: 12, height: 1.4))),
                    ]),
              )),
        ]),
      );
}

class _HabitRow extends StatelessWidget {
  final String emoji, text;
  final bool isDark;
  const _HabitRow(this.emoji, this.text, this.isDark);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 12),
          Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 12, height: 1.4))),
        ]),
      );
}

class _TimelineRow extends StatelessWidget {
  final String period, text;
  final bool isDark;
  const _TimelineRow(this.period, this.text, this.isDark);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 80,
              child: Text(period,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: ActColors.primary))),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 12, height: 1.4))),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

class _SectionBarRow extends StatelessWidget {
  final ActSection section;
  final double score;
  final bool isDark;
  const _SectionBarRow(
      {required this.section, required this.score, required this.isDark});

  Color get _color {
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

  @override
  Widget build(BuildContext context) {
    final s = score.round();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: _cardDecor(isDark),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(actSectionDisplayName(section),
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const Spacer(),
          Text('$s / 36',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: ActColors.scoreColor(score))),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
                value: score / 36,
                minHeight: 8,
                color: _color,
                backgroundColor: _color.withOpacity(0.10))),
      ]),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _MiniStat(
      {required this.label, required this.value, required this.icon});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
        child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: _cardDecor(isDark),
      child: Column(children: [
        Icon(icon, size: 18, color: ActColors.primary),
        const SizedBox(height: 6),
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        Text(label, style: TextStyle(fontSize: 10, color: ActColors.midGray)),
      ]),
    ));
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.insights_outlined,
                size: 56, color: ActColors.midGray.withOpacity(0.4)),
            const SizedBox(height: 16),
            const Text('No data yet',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
                'Complete a practice session or full exam\nto see your predictions and study plan.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13, color: ActColors.midGray, height: 1.5)),
          ]),
        ),
      );
}

BoxDecoration _cardDecor(bool isDark) => BoxDecoration(
      color: isDark ? ActColors.darkCard : Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
          color: isDark ? ActColors.darkBorder : ActColors.lightBorder),
    );

Widget _SectionHeader(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 10),
      child: Text(text,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
    );

// ─────────────────────────────────────────────────────────────────────────────
// Data helpers
// ─────────────────────────────────────────────────────────────────────────────

class _SkillStat {
  final String skill;
  int correct = 0;
  int total = 0;
  _SkillStat(this.skill);
  double get accuracy => total == 0 ? 0 : correct / total;
}

class _SkillRow {
  final ActSection section;
  final _SkillStat stat;
  const _SkillRow({required this.section, required this.stat});
}

class _CollegeTier {
  final String label;
  final int min, max;
  const _CollegeTier(this.label, this.min, this.max);
}

const List<_CollegeTier> _collegeTiers = [
  _CollegeTier('Elite — MIT, Harvard, Stanford', 34, 36),
  _CollegeTier('Highly Competitive — UCLA, Michigan', 31, 33),
  _CollegeTier('Competitive — State Flagships', 26, 30),
  _CollegeTier('Average College Admissions', 20, 25),
  _CollegeTier('Open Enrollment', 1, 19),
];

const Map<ActSection, List<String>> _allTopics = {
  ActSection.english: [
    'Punctuation & Commas',
    'Subject-Verb Agreement',
    'Sentence Structure',
    'Transitions & Conjunctions',
    'Rhetorical Skills',
    'Word Choice & Style',
  ],
  ActSection.math: [
    'Pre-Algebra & Fractions',
    'Linear Equations',
    'Quadratics & Functions',
    'Geometry & Triangles',
    'Coordinate Geometry',
    'Trigonometry & Stats',
  ],
  ActSection.reading: [
    'Main Idea & Purpose',
    'Supporting Details',
    'Inference Questions',
    'Vocabulary in Context',
    'Comparative Passages',
    'Author\'s Tone & Purpose',
  ],
  ActSection.science: [
    'Reading Graphs & Tables',
    'Data Representation',
    'Research Summaries',
    'Experiment Design',
    'Conflicting Viewpoints',
    'Multi-Figure Analysis',
  ],
};
