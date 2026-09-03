import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/questions_data.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/voice_service.dart';
import '../services/exam_settings_service.dart';
import '../services/user_profile_service.dart';
import '../utils/theme.dart';
import 'exam_result_screen.dart';

// ── ACT raw-score-to-scale conversion tables (official lookup) ────────────────
// Source: ACT published scoring guides. Maps raw score → scaled score (1-36).
const Map<int, int> _englishScaleMap = {
  75: 36, 74: 35, 73: 35, 72: 34, 71: 33, 70: 33, 69: 32, 68: 31,
  67: 30, 66: 30, 65: 29, 64: 28, 63: 28, 62: 27, 61: 26, 60: 26,
  59: 25, 58: 24, 57: 24, 56: 23, 55: 23, 54: 22, 53: 21, 52: 21,
  51: 20, 50: 20, 49: 19, 48: 19, 47: 18, 46: 17, 45: 17, 44: 16,
  43: 16, 42: 15, 41: 15, 40: 14, 39: 14, 38: 13, 37: 13, 36: 12,
  35: 12, 34: 11, 33: 11, 32: 10, 31: 10, 30: 9,  20: 7,  10: 4,
  5: 2,  0: 1,
};
const Map<int, int> _mathScaleMap = {
  60: 36, 59: 35, 58: 34, 57: 33, 56: 32, 55: 31, 54: 30, 53: 29,
  52: 28, 51: 27, 50: 27, 49: 26, 48: 25, 47: 24, 46: 23, 45: 23,
  44: 22, 43: 21, 42: 21, 41: 20, 40: 20, 39: 19, 38: 18, 37: 18,
  36: 17, 35: 17, 34: 16, 33: 16, 32: 15, 31: 15, 30: 14, 25: 12,
  20: 10, 15: 8,  10: 6,  5: 3,   0: 1,
};
const Map<int, int> _readingScaleMap = {
  40: 36, 39: 35, 38: 34, 37: 33, 36: 31, 35: 30, 34: 29, 33: 27,
  32: 26, 31: 25, 30: 24, 29: 23, 28: 22, 27: 21, 26: 20, 25: 19,
  24: 19, 23: 18, 22: 17, 21: 16, 20: 15, 18: 14, 15: 12, 10: 9,
  5: 5,   0: 1,
};
const Map<int, int> _scienceScaleMap = {
  40: 36, 39: 35, 38: 34, 37: 32, 36: 31, 35: 30, 34: 29, 33: 28,
  32: 27, 31: 26, 30: 25, 29: 24, 28: 23, 27: 22, 26: 21, 25: 20,
  24: 19, 23: 18, 22: 17, 21: 16, 20: 15, 18: 14, 15: 11, 10: 8,
  5: 4,   0: 1,
};

int _lookupScale(Map<int, int> map, int raw) {
  if (map.containsKey(raw)) return map[raw]!;
  // Interpolate from nearest lower key
  final keys = map.keys.toList()..sort();
  for (int i = keys.length - 1; i >= 0; i--) {
    if (keys[i] <= raw) return map[keys[i]]!;
  }
  return 1;
}

int actScaleScore(ActSection section, int rawCorrect) {
  switch (section) {
    case ActSection.english:  return _lookupScale(_englishScaleMap, rawCorrect);
    case ActSection.math:     return _lookupScale(_mathScaleMap, rawCorrect);
    case ActSection.reading:  return _lookupScale(_readingScaleMap, rawCorrect);
    case ActSection.science:  return _lookupScale(_scienceScaleMap, rawCorrect);
  }
}

// ── Exam section descriptor ───────────────────────────────────────────────────
class _ExamSection {
  final ActSection section;
  final List<ActQuestion> questions;
  final int timeLimitSeconds;
  _ExamSection({required this.section, required this.questions, required this.timeLimitSeconds});
}

// ═══════════════════════════════════════════════════════════════════════════════
// ExamModeScreen — Full ACT exam flow
// ═══════════════════════════════════════════════════════════════════════════════
class ExamModeScreen extends StatefulWidget {
  const ExamModeScreen({super.key});

  @override
  State<ExamModeScreen> createState() => _ExamModeScreenState();
}

class _ExamModeScreenState extends State<ExamModeScreen> {
  bool _loading = true;
  ExamSettings? _settings;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final settings = await ExamSettingsService.loadAll();
    final profileDone = await ExamSettingsService.isProfileSetupDone();
    if (!mounted) return;
    setState(() { _settings = settings; _loading = false; });

    if (!profileDone) {
      // Show profile setup first
      WidgetsBinding.instance.addPostFrameCallback((_) => _showProfileSetup());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showExamSetup());
    }
  }

  void _showProfileSetup() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProfileSetupDialog(
        onDone: (name, target) async {
          await ExamSettingsService.setStudentName(name);
          await ExamSettingsService.setTargetScore(target);
          await ExamSettingsService.markProfileSetupDone();
          if (mounted) {
            setState(() => _settings = _settings!.copyWith(studentName: name, targetScore: target));
            _showExamSetup();
          }
        },
      ),
    );
  }

  void _showExamSetup() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ExamSetupDialog(
        settings: _settings!,
        onStart: (settings) async {
          await ExamSettingsService.saveAll(settings);
          setState(() => _settings = settings);
          if (mounted) _launchExam(settings);
        },
        onCancel: () {
          if (mounted) Navigator.pop(context);
        },
      ),
    );
  }

  void _launchExam(ExamSettings settings) {
    // Build section list
    final sections = <_ExamSection>[];
    if (settings.includeEnglish) {
      final qs = questionsForSection(ActSection.english);
      if (qs.isNotEmpty) {
        sections.add(_ExamSection(
          section: ActSection.english,
          questions: qs,
          timeLimitSeconds: settings.englishMinutes * 60,
        ));
      }
    }
    if (settings.includeMath) {
      final qs = questionsForSection(ActSection.math);
      if (qs.isNotEmpty) {
        sections.add(_ExamSection(
          section: ActSection.math,
          questions: qs,
          timeLimitSeconds: settings.mathMinutes * 60,
        ));
      }
    }
    if (settings.includeReading) {
      final qs = questionsForSection(ActSection.reading);
      if (qs.isNotEmpty) {
        sections.add(_ExamSection(
          section: ActSection.reading,
          questions: qs,
          timeLimitSeconds: settings.readingMinutes * 60,
        ));
      }
    }
    if (settings.includeScience) {
      final qs = questionsForSection(ActSection.science);
      if (qs.isNotEmpty) {
        sections.add(_ExamSection(
          section: ActSection.science,
          questions: qs,
          timeLimitSeconds: settings.scienceMinutes * 60,
        ));
      }
    }

    if (sections.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No sections selected. Please select at least one section.')),
      );
      return;
    }

    Navigator.pushReplacement(context, MaterialPageRoute(
      builder: (_) => _FullExamSession(sections: sections, settings: settings),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Full ACT Exam')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : const Center(child: CircularProgressIndicator()),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Profile setup dialog — shown once, or accessible from settings
// ═══════════════════════════════════════════════════════════════════════════════
class _ProfileSetupDialog extends StatefulWidget {
  final void Function(String name, int targetScore) onDone;
  const _ProfileSetupDialog({required this.onDone});

  @override
  State<_ProfileSetupDialog> createState() => _ProfileSetupDialogState();
}

class _ProfileSetupDialogState extends State<_ProfileSetupDialog> {
  final _nameCtrl = TextEditingController();
  int _target = 28;

  @override
  void dispose() { _nameCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        Icon(Icons.school_outlined, color: ActColors.primary),
        const SizedBox(width: 10),
        const Text('Exam Profile Setup', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ]),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Set up your exam profile. You can change this anytime in Settings.',
              style: TextStyle(fontSize: 12, color: ActColors.midGray),
            ),
            const SizedBox(height: 20),
            const Text('Your Name', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 6),
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                hintText: 'Enter your full name',
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Target ACT Composite Score', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 4),
            Text('National average is 21. Top universities prefer 30+.', style: TextStyle(fontSize: 11, color: ActColors.midGray)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _target.toDouble(),
                    min: 1, max: 36, divisions: 35,
                    activeColor: ActColors.primary,
                    label: '$_target',
                    onChanged: (v) => setState(() => _target = v.round()),
                  ),
                ),
                Container(
                  width: 44,
                  alignment: Alignment.center,
                  child: Text('$_target', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: ActColors.scoreColor(_target.toDouble()).withOpacity(0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Icon(Icons.flag_outlined, size: 14, color: ActColors.scoreColor(_target.toDouble())),
                const SizedBox(width: 6),
                Expanded(child: Text(_scoreLabel(_target),
                  overflow: TextOverflow.ellipsis, maxLines: 1,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                    color: ActColors.scoreColor(_target.toDouble())))),
              ]),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: ActColors.primary),
          onPressed: () {
            final name = _nameCtrl.text.trim();
            if (name.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please enter your name.')));
              return;
            }
            Navigator.pop(context);
            widget.onDone(name, _target);
          },
          child: const Text('Save & Continue'),
        ),
      ],
    );
  }

  String _scoreLabel(int score) {
    if (score >= 34) return 'Elite — Top 1% nationally';
    if (score >= 30) return 'Excellent — Top universities';
    if (score >= 26) return 'Good — Many competitive colleges';
    if (score >= 21) return 'Average — Meets most requirements';
    if (score >= 16) return 'Below Average — More practice needed';
    return 'Needs Significant Improvement';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Exam setup dialog — sections, time, options
// ═══════════════════════════════════════════════════════════════════════════════
class _ExamSetupDialog extends StatefulWidget {
  final ExamSettings settings;
  final void Function(ExamSettings) onStart;
  final VoidCallback onCancel;
  const _ExamSetupDialog({required this.settings, required this.onStart, required this.onCancel});

  @override
  State<_ExamSetupDialog> createState() => _ExamSetupDialogState();
}

class _ExamSetupDialogState extends State<_ExamSetupDialog> {
  late ExamSettings _s;

  @override
  void initState() {
    super.initState();
    _s = widget.settings;
  }

  String _fmtTime(int minutes) {
    if (minutes >= 60) {
      final h = minutes ~/ 60;
      final m = minutes % 60;
      return m == 0 ? '${h}h' : '${h}h ${m}m';
    }
    return '${minutes}m';
  }

  Widget _sectionRow({
    required String label,
    required IconData icon,
    required Color color,
    required bool included,
    required int minutes,
    required int defaultMinutes,
    required int questionCount,
    required void Function(bool) onToggle,
    required void Function(int) onTimeChange,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? ActColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: included ? color.withOpacity(0.35) : (isDark ? ActColors.darkBorder : ActColors.lightBorder),
        ),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            leading: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: (included ? color : ActColors.midGray).withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: included ? color : ActColors.midGray),
            ),
            title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            subtitle: Text('$questionCount questions · ${_fmtTime(minutes)}${minutes != defaultMinutes ? ' (custom)' : ''}',
                style: TextStyle(fontSize: 11, color: ActColors.midGray)),
            trailing: Switch(value: included, activeColor: color, onChanged: onToggle),
          ),
          if (included) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Time: ${_fmtTime(minutes)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      if (minutes != defaultMinutes)
                        TextButton.icon(
                          icon: const Icon(Icons.restart_alt, size: 14),
                          label: Text('Reset (${_fmtTime(defaultMinutes)})', style: const TextStyle(fontSize: 11)),
                          style: TextButton.styleFrom(
                            foregroundColor: ActColors.midGray,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 0),
                          ),
                          onPressed: () => onTimeChange(defaultMinutes),
                        ),
                    ],
                  ),
                  Slider(
                    value: minutes.toDouble(),
                    min: 10, max: minutes > defaultMinutes ? (defaultMinutes * 2).toDouble() : defaultMinutes.toDouble() + 30,
                    divisions: ((defaultMinutes * 2 - 10) ~/ 5).clamp(4, 40),
                    activeColor: color,
                    label: '${minutes}min',
                    onChanged: (v) => onTimeChange(v.round()),
                  ),
                  Row(children: [
                    _quickTime(10, color, onTimeChange),
                    const SizedBox(width: 6),
                    _quickTime(defaultMinutes ~/ 2, color, onTimeChange),
                    const SizedBox(width: 6),
                    _quickTime(defaultMinutes, color, onTimeChange, label: 'Real'),
                  ]),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _quickTime(int min, Color color, void Function(int) onTap, {String? label}) {
    return GestureDetector(
      onTap: () => onTap(min),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: color.withOpacity(0.4)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label ?? '${min}m', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalQ = (_s.includeEnglish ? questionsForSection(ActSection.english).length : 0) +
        (_s.includeMath ? questionsForSection(ActSection.math).length : 0) +
        (_s.includeReading ? questionsForSection(ActSection.reading).length : 0) +
        (_s.includeScience ? questionsForSection(ActSection.science).length : 0);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 720),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [ActColors.primaryDark, ActColors.primary],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  Row(children: [
                    const Icon(Icons.assignment_outlined, color: Colors.white, size: 22),
                    const SizedBox(width: 10),
                    const Expanded(child: Text('Full ACT Exam Setup',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17))),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                      onPressed: widget.onCancel,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    _s.studentName != null ? 'Student: ${_s.studentName} · Target: ${_s.targetScore}' : '',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),

            // Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Summary chips
                    Row(children: [
                      _SummaryChip(label: '$totalQ Questions', icon: Icons.quiz_outlined),
                      const SizedBox(width: 8),
                      _SummaryChip(label: '${_fmtTime(_s.totalMinutes)} Total', icon: Icons.timer_outlined),
                    ]),
                    const SizedBox(height: 16),

                    // English
                    _sectionRow(
                      label: 'English', icon: Icons.edit_note_outlined,
                      color: ActColors.primary,
                      included: _s.includeEnglish, minutes: _s.englishMinutes,
                      defaultMinutes: ExamSettingsService.defaultEnglishMinutes,
                      questionCount: questionsForSection(ActSection.english).length,
                      onToggle: (v) => setState(() => _s = _s.copyWith(includeEnglish: v)),
                      onTimeChange: (v) => setState(() => _s = _s.copyWith(englishMinutes: v)),
                    ),
                    _sectionRow(
                      label: 'Mathematics', icon: Icons.functions_outlined,
                      color: const Color(0xFF1565C0),
                      included: _s.includeMath, minutes: _s.mathMinutes,
                      defaultMinutes: ExamSettingsService.defaultMathMinutes,
                      questionCount: questionsForSection(ActSection.math).length,
                      onToggle: (v) => setState(() => _s = _s.copyWith(includeMath: v)),
                      onTimeChange: (v) => setState(() => _s = _s.copyWith(mathMinutes: v)),
                    ),
                    _sectionRow(
                      label: 'Reading', icon: Icons.menu_book_outlined,
                      color: const Color(0xFF2E7D32),
                      included: _s.includeReading, minutes: _s.readingMinutes,
                      defaultMinutes: ExamSettingsService.defaultReadingMinutes,
                      questionCount: questionsForSection(ActSection.reading).length,
                      onToggle: (v) => setState(() => _s = _s.copyWith(includeReading: v)),
                      onTimeChange: (v) => setState(() => _s = _s.copyWith(readingMinutes: v)),
                    ),
                    _sectionRow(
                      label: 'Science', icon: Icons.science_outlined,
                      color: const Color(0xFF6A1B9A),
                      included: _s.includeScience, minutes: _s.scienceMinutes,
                      defaultMinutes: ExamSettingsService.defaultScienceMinutes,
                      questionCount: questionsForSection(ActSection.science).length,
                      onToggle: (v) => setState(() => _s = _s.copyWith(includeScience: v)),
                      onTimeChange: (v) => setState(() => _s = _s.copyWith(scienceMinutes: v)),
                    ),

                    // Options
                    const Divider(height: 24),
                    // Answer reveal mode
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isDark ? ActColors.darkCard : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isDark ? ActColors.darkBorder : ActColors.lightBorder),
                      ),
                      child: Column(children: [
                        ListTile(
                          dense: true,
                          leading: Icon(Icons.visibility_outlined, color: ActColors.primary, size: 20),
                          title: const Text('Answer Reveal', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          subtitle: Text(
                            _s.answerReveal == 'end'
                              ? 'Real ACT mode — answers shown only at results'
                              : 'Practice mode — correct answer shown after each question',
                            style: TextStyle(fontSize: 11, color: ActColors.midGray, height: 1.3),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Row(children: [
                            _RevealChip(
                              label: 'Practice', sublabel: 'Show after each Q',
                              icon: Icons.check_circle_outline,
                              selected: _s.answerReveal == 'immediate',
                              onTap: () => setState(() => _s = _s.copyWith(answerReveal: 'immediate')),
                            ),
                            const SizedBox(width: 8),
                            _RevealChip(
                              label: 'Real ACT', sublabel: 'Show at end only',
                              icon: Icons.lock_clock,
                              selected: _s.answerReveal == 'end',
                              onTap: () => setState(() => _s = _s.copyWith(answerReveal: 'end')),
                            ),
                          ]),
                        ),
                      ]),
                    ),
                    _OptionRow(
                      icon: Icons.calculate_outlined,
                      title: 'Show Calculator',
                      subtitle: 'Floating calculator available during Math & Science sections',
                      value: _s.showCalculator,
                      onChanged: (v) => setState(() => _s = _s.copyWith(showCalculator: v)),
                    ),
                    _OptionRow(
                      icon: Icons.save_outlined,
                      title: 'Auto-Save Results',
                      subtitle: 'Automatically save scores to your history when exam completes',
                      value: _s.autoSave,
                      onChanged: (v) => setState(() => _s = _s.copyWith(autoSave: v)),
                    ),

                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: ActColors.info.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: ActColors.info.withOpacity(0.2)),
                      ),
                      child: Row(children: [
                        Icon(Icons.info_outline, size: 14, color: ActColors.info),
                        const SizedBox(width: 8),
                        Expanded(child: Text(
                          'Real ACT: English 75q/45min · Math 60q/60min · Reading 40q/35min · Science 40q/35min. '
                          'Your settings are saved automatically.',
                          style: TextStyle(fontSize: 11, color: ActColors.midGray, height: 1.4),
                        )),
                      ]),
                    ),
                  ],
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                border: Border(top: BorderSide(color: ActColors.lightBorder)),
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: ActColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 22),
                  label: Text(
                    'Start Exam · $totalQ Questions · ${_fmtTime(_s.totalMinutes)}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  onPressed: totalQ == 0 ? null : () {
                    Navigator.pop(context);
                    widget.onStart(_s);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _RevealChip extends StatelessWidget {
  final String label, sublabel; final IconData icon;
  final bool selected; final VoidCallback onTap;
  const _RevealChip({required this.label, required this.sublabel, required this.icon,
    required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? ActColors.primary.withOpacity(0.10) : (isDark ? ActColors.darkSurface : const Color(0xFFF5F5F5)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? ActColors.primary : (isDark ? ActColors.darkBorder : ActColors.lightBorder), width: selected ? 1.5 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 14, color: selected ? ActColors.primary : ActColors.midGray),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12,
              color: selected ? ActColors.primary : null)),
          ]),
          const SizedBox(height: 2),
          Text(sublabel, style: TextStyle(fontSize: 10, color: ActColors.midGray, height: 1.3)),
        ]),
      ),
    ));
  }
}

class _SummaryChip extends StatelessWidget {
  final String label; final IconData icon;
  const _SummaryChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: isDark ? ActColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? ActColors.darkBorder : ActColors.lightBorder),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: ActColors.primary),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
      ]),
    );
  }
}

class _OptionRow extends StatelessWidget {
  final IconData icon; final String title, subtitle;
  final bool value; final void Function(bool) onChanged;
  const _OptionRow({required this.icon, required this.title, required this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? ActColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? ActColors.darkBorder : ActColors.lightBorder),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: ActColors.primary, size: 20),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 11, color: ActColors.midGray, height: 1.3)),
        trailing: Switch(value: value, activeColor: ActColors.primary, onChanged: onChanged),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Full Exam Session — drives through all sections
// ═══════════════════════════════════════════════════════════════════════════════
class _FullExamSession extends StatefulWidget {
  final List<_ExamSection> sections;
  final ExamSettings settings;
  const _FullExamSession({required this.sections, required this.settings});

  @override
  State<_FullExamSession> createState() => _FullExamSessionState();
}

class _FullExamSessionState extends State<_FullExamSession> {
  int _sectionIndex = 0;
  int _questionIndex = 0;
  final Map<int, Map<int, String>> _sectionAnswers = {}; // sectionIdx → {qIdx → answer}
  bool _showFeedback = false;
  String? _selectedAnswer;
  bool _paused = false;
  bool _calcVisible = false;
  bool _voiceEnabled = false;
  bool _micEnabled = false;
  bool _listening = false;

  late int _secondsLeft;
  late int _totalSectionSeconds;
  Timer? _timer;

  final PageController _pageCtrl = PageController();
  final FocusNode _focusNode = FocusNode();

  // Calc state (mini inline calculator)
  String _calcDisplay = '0';
  String _calcOp = '';
  double _calcVal = 0;
  bool _calcNewNum = true;

  @override
  void initState() {
    super.initState();
    _startSection();
    _initVoice();
  }

  Future<void> _initVoice() async {
    await VoiceService.instance.init();
    final tts = await VoiceService.instance.isTtsEnabled();
    final mic = await VoiceService.instance.isSttEnabled();
    if (mounted) setState(() { _voiceEnabled = tts; _micEnabled = mic; });
    if (tts) _readCurrentQuestion();
  }

  void _readCurrentQuestion() {
    if (!_voiceEnabled) return;
    final questions = _currentQuestions;
    if (questions.isEmpty) return;
    final q = questions[_questionIndex];
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
      },
    );
  }

  void _toggleVoice() async {
    final newVal = !_voiceEnabled;
    await VoiceService.instance.setTtsEnabled(newVal);
    setState(() => _voiceEnabled = newVal);
    if (newVal) _readCurrentQuestion();
    else VoiceService.instance.stopReading();
  }

  void _toggleMic() async {
    final newVal = !_micEnabled;
    await VoiceService.instance.setSttEnabled(newVal);
    setState(() => _micEnabled = newVal);
  }

  void _startSection() {
    _questionIndex = 0;
    _selectedAnswer = null;
    _showFeedback = false;
    _totalSectionSeconds = widget.sections[_sectionIndex].timeLimitSeconds;
    _secondsLeft = _totalSectionSeconds;
    _sectionAnswers[_sectionIndex] = {};
    _startTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_paused) return;
      if (_secondsLeft <= 0) {
        _timer?.cancel();
        _timeUp();
        return;
      }
      if (mounted) setState(() => _secondsLeft--);
    });
  }

  void _timeUp() {
    // Auto-move to next section or finish
    if (_sectionIndex < widget.sections.length - 1) {
      _showBreakDialog(autoAdvance: true);
    } else {
      _finishExam();
    }
  }

  _ExamSection get _currentSection => widget.sections[_sectionIndex];
  List<ActQuestion> get _currentQuestions => _currentSection.questions;

  void _selectAnswer(String letter) {
    if (_showFeedback) return;
    setState(() => _selectedAnswer = letter);
  }

  void _confirmAnswer() {
    if (_selectedAnswer == null || _showFeedback) return;
    _sectionAnswers[_sectionIndex]![_questionIndex] = _selectedAnswer!;
    // Real ACT mode: don't reveal correct/incorrect — just move on
    final revealNow = widget.settings.answerReveal != 'end';
    setState(() => _showFeedback = revealNow);
    if (!revealNow) _nextQuestion(); // auto-advance in real ACT mode
  }

  void _nextQuestion() {
    if (_questionIndex < _currentQuestions.length - 1) {
      final revealNow = widget.settings.answerReveal != 'end';
      setState(() {
        _questionIndex++;
        _selectedAnswer = _sectionAnswers[_sectionIndex]?[_questionIndex];
        // In 'end' mode, never show inline feedback during exam
        _showFeedback = revealNow && (_sectionAnswers[_sectionIndex]?.containsKey(_questionIndex) ?? false);
      });
      if (_voiceEnabled) _readCurrentQuestion();
      _pageCtrl.nextPage(duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
    } else {
      // End of section
      if (_sectionIndex < widget.sections.length - 1) {
        _showBreakDialog(autoAdvance: false);
      } else {
        _finishExam();
      }
    }
  }

  void _prevQuestion() {
    if (_questionIndex > 0) {
      setState(() {
        _questionIndex--;
        _selectedAnswer = _sectionAnswers[_sectionIndex]?[_questionIndex];
        _showFeedback = _sectionAnswers[_sectionIndex]?.containsKey(_questionIndex) ?? false;
      });
      _pageCtrl.previousPage(duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
    }
  }

  void _showBreakDialog({required bool autoAdvance}) {
    _timer?.cancel();
    final nextSection = widget.sections[_sectionIndex + 1];
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Row(children: [
          Icon(autoAdvance ? Icons.timer_off : Icons.check_circle_outline,
              color: autoAdvance ? ActColors.warning : ActColors.success),
          const SizedBox(width: 10),
          Text(autoAdvance ? 'Time\'s Up!' : 'Section Complete!',
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(autoAdvance
                ? 'Time for ${actSectionDisplayName(_currentSection.section)} has ended.'
                : 'You\'ve completed ${actSectionDisplayName(_currentSection.section)}.',
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ActColors.info.withOpacity(0.07),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Row(children: [
                    Icon(Icons.arrow_forward, size: 14, color: ActColors.info),
                    const SizedBox(width: 6),
                    Text('Next: ${actSectionDisplayName(nextSection.section)}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ]),
                  const SizedBox(height: 4),
                  Text('${nextSection.questions.length} questions · ${nextSection.timeLimitSeconds ~/ 60} minutes',
                      style: TextStyle(fontSize: 11, color: ActColors.midGray)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: ActColors.primary),
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: const Text('Continue to Next Section'),
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _sectionIndex++;
                _calcVisible = false;
              });
              _pageCtrl.jumpToPage(0);
              _startSection();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _finishExam() async {
    _timer?.cancel();
    // Build per-section results
    final sectionResults = <ActSection, List<QuestionResult>>{};
    for (int si = 0; si < widget.sections.length; si++) {
      final sec = widget.sections[si];
      final answers = _sectionAnswers[si] ?? {};
      final results = <QuestionResult>[];
      for (int qi = 0; qi < sec.questions.length; qi++) {
        final given = answers[qi] ?? '';
        results.add(QuestionResult(
          questionId: sec.questions[qi].id,
          givenAnswer: given,
          isCorrect: given == sec.questions[qi].correctAnswer,
          timeSpent: Duration(seconds: sec.timeLimitSeconds),
        ));
      }
      sectionResults[sec.section] = results;
    }

    // Compute scores
    final sectionScores = <ActSection, int>{};
    for (final entry in sectionResults.entries) {
      final raw = entry.value.where((r) => r.isCorrect).length;
      sectionScores[entry.key] = actScaleScore(entry.key, raw);
    }
    final composite = sectionScores.values.isEmpty
        ? 1
        : (sectionScores.values.reduce((a, b) => a + b) / sectionScores.length).round();

    // Save if autoSave
    if (widget.settings.autoSave) {
      final name = widget.settings.studentName ?? await UserProfileService.getDisplayName() ?? 'Student';
      for (final entry in sectionResults.entries) {
        final attempt = ExamAttempt(
          id: '${DateTime.now().toIso8601String()}-${entry.key.name}',
          startedAt: DateTime.now().subtract(Duration(seconds: widget.sections
              .firstWhere((s) => s.section == entry.key).timeLimitSeconds)),
          completedAt: DateTime.now(),
          setNumber: 1,
          section: entry.key,
          results: entry.value,
        );
        await DatabaseService.instance.saveAttempt(attempt);
        await DatabaseService.instance.upsertLeaderboardEntry(name, composite.toDouble(), composite / 36);
      }
    }

    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(
      builder: (_) => ExamResultScreen(
        sectionResults: sectionResults,
        sectionScores: sectionScores,
        compositeScore: composite,
        sectionQuestions: {for (final s in widget.sections) s.section: s.questions},
        settings: widget.settings,
      ),
    ));
  }

  void _confirmExit() {
    _timer?.cancel();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Exit Exam?'),
        content: const Text('Your progress will be lost. Are you sure you want to exit?'),
        actions: [
          TextButton(onPressed: () { Navigator.pop(context); _startTimer(); }, child: const Text('Stay')),
          TextButton(
            onPressed: () { Navigator.pop(context); Navigator.pop(context); },
            child: Text('Exit', style: TextStyle(color: ActColors.danger)),
          ),
        ],
      ),
    );
  }

  String _formatTime(int s) {
    final m = s ~/ 60; final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  Color get _timerColor {
    final pct = _totalSectionSeconds > 0 ? _secondsLeft / _totalSectionSeconds : 0.0;
    if (pct > 0.4) return ActColors.success;
    if (pct > 0.15) return ActColors.warning;
    return ActColors.danger;
  }

  bool get _showCalcButton =>
      widget.settings.showCalculator &&
      (_currentSection.section == ActSection.math || _currentSection.section == ActSection.science);

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.keyA) { _selectAnswer('A'); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.keyB) { _selectAnswer('B'); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.keyC) { _selectAnswer('C'); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.keyD) { _selectAnswer('D'); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
      _showFeedback ? _nextQuestion() : _confirmAnswer(); return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) { _showFeedback ? _nextQuestion() : _confirmAnswer(); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.arrowLeft) { _prevQuestion(); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.keyV) { _toggleVoice(); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.keyM) { _micEnabled ? _startListening() : _toggleMic(); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.escape) { _confirmExit(); return KeyEventResult.handled; }
    return KeyEventResult.ignored;
  }

  // ── Mini calculator logic ─────────────────────────────────────────────────
  void _calcInput(String v) {
    setState(() {
      if (v == 'C') { _calcDisplay = '0'; _calcOp = ''; _calcVal = 0; _calcNewNum = true; return; }
      if (v == '⌫') {
        _calcDisplay = _calcDisplay.length > 1 ? _calcDisplay.substring(0, _calcDisplay.length - 1) : '0';
        return;
      }
      if (v == '=') {
        final cur = double.tryParse(_calcDisplay) ?? 0;
        double result = cur;
        if (_calcOp == '+') result = _calcVal + cur;
        else if (_calcOp == '−') result = _calcVal - cur;
        else if (_calcOp == '×') result = _calcVal * cur;
        else if (_calcOp == '÷') result = _calcVal == 0 ? 0 : _calcVal / cur;
        else if (_calcOp == 'x²') result = _calcVal * _calcVal;
        else if (_calcOp == '√') result = sqrt(_calcVal);
        _calcDisplay = result == result.truncateToDouble() ? result.toInt().toString() : result.toStringAsFixed(6).replaceAll(RegExp(r'0+$'), '');
        _calcOp = ''; _calcNewNum = true; return;
      }
      if (v == 'x²') { _calcVal = double.tryParse(_calcDisplay) ?? 0; _calcOp = 'x²'; _calcDisplay = '0'; _calcNewNum = true; return; }
      if (v == '√') { _calcVal = double.tryParse(_calcDisplay) ?? 0; _calcOp = '√'; _calcDisplay = '0'; _calcNewNum = true; return; }
      if (v == '+/-') { _calcDisplay = _calcDisplay.startsWith('-') ? _calcDisplay.substring(1) : '-$_calcDisplay'; return; }
      if (v == '%') { _calcDisplay = (double.tryParse(_calcDisplay) ?? 0 / 100).toString(); return; }
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
      else { _calcDisplay = _calcDisplay == '0' ? v : _calcDisplay + v; }
    });
  }

  Widget _calcBtn(String label, {Color? bg, Color? fg}) {
    return Expanded(
      child: GestureDetector(
        onTap: () => _calcInput(label),
        child: Container(
          margin: const EdgeInsets.all(2),
          height: 42,
          decoration: BoxDecoration(
            color: bg ?? const Color(0xFF2A2A2E),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: Text(label, style: TextStyle(
              color: fg ?? Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            )),
          ),
        ),
      ),
    );
  }

  Widget _buildCalculator() {
    return Container(
      width: 260,
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
            const Expanded(child: Text('Calculator', style: TextStyle(color: Colors.white60, fontSize: 11))),
            GestureDetector(
              onTap: () => setState(() => _calcVisible = false),
              child: const Icon(Icons.close, color: Colors.white38, size: 18),
            ),
          ]),
          const SizedBox(height: 6),
          Container(
            width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(color: const Color(0xFF0A0A0A), borderRadius: BorderRadius.circular(8)),
            child: Text(_calcDisplay,
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w300),
                textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(height: 8),
          Row(children: [_calcBtn('C', bg: const Color(0xFF636366)), _calcBtn('+/-', bg: const Color(0xFF636366)),
            _calcBtn('%', bg: const Color(0xFF636366)), _calcBtn('÷', bg: const Color(0xFFFF9F0A), fg: Colors.black)]),
          Row(children: [_calcBtn('7'), _calcBtn('8'), _calcBtn('9'), _calcBtn('×', bg: const Color(0xFFFF9F0A), fg: Colors.black)]),
          Row(children: [_calcBtn('4'), _calcBtn('5'), _calcBtn('6'), _calcBtn('−', bg: const Color(0xFFFF9F0A), fg: Colors.black)]),
          Row(children: [_calcBtn('1'), _calcBtn('2'), _calcBtn('3'), _calcBtn('+', bg: const Color(0xFFFF9F0A), fg: Colors.black)]),
          Row(children: [_calcBtn('x²', bg: const Color(0xFF3A3A3C)), _calcBtn('√', bg: const Color(0xFF3A3A3C)),
            _calcBtn('.'), _calcBtn('=', bg: const Color(0xFFFF9F0A), fg: Colors.black)]),
          Row(children: [_calcBtn('⌫', bg: const Color(0xFF3A3A3C))]),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageCtrl.dispose();
    _focusNode.dispose();
    VoiceService.instance.stopReading();
    VoiceService.instance.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sec = _currentSection;
    final q = _currentQuestions.isNotEmpty ? _currentQuestions[_questionIndex] : null;
    final answered = _sectionAnswers[_sectionIndex]?.length ?? 0;

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKey,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Row(children: [
            // Section tabs
            ...List.generate(widget.sections.length, (i) {
              final s = widget.sections[i];
              final isCurrent = i == _sectionIndex;
              final isDone = i < _sectionIndex;
              return Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isCurrent
                      ? Colors.white.withOpacity(0.25)
                      : (isDone ? Colors.white.withOpacity(0.10) : Colors.transparent),
                  borderRadius: BorderRadius.circular(6),
                  border: isCurrent ? Border.all(color: Colors.white38) : null,
                ),
                child: Text(
                  actSectionDisplayName(s.section).split(' ').first,
                  style: TextStyle(
                    color: isCurrent ? Colors.white : (isDone ? Colors.white60 : Colors.white38),
                    fontSize: 11,
                    fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              );
            }),
          ]),
          actions: [
            // Timer
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _timerColor.withOpacity(0.20),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _timerColor.withOpacity(0.5)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.timer_outlined, size: 14, color: _timerColor),
                const SizedBox(width: 4),
                Text(_formatTime(_secondsLeft),
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: _timerColor)),
              ]),
            ),
            // Voice reading toggle
            IconButton(
              icon: Icon(_voiceEnabled ? Icons.volume_up : Icons.volume_off_outlined,
                  color: _voiceEnabled ? Colors.white : Colors.white60),
              tooltip: 'Voice Reading (V)',
              onPressed: _toggleVoice,
            ),
            // Mic answer toggle
            IconButton(
              icon: Icon(_listening ? Icons.mic : (_micEnabled ? Icons.mic_outlined : Icons.mic_off_outlined),
                  color: _listening ? ActColors.accent : (_micEnabled ? Colors.white : Colors.white60)),
              tooltip: 'Voice Answer (M)',
              onPressed: _micEnabled ? _startListening : _toggleMic,
            ),
            // Calculator toggle (Math/Science only)
            if (_showCalcButton)
              IconButton(
                icon: Icon(_calcVisible ? Icons.calculate : Icons.calculate_outlined,
                    color: _calcVisible ? ActColors.accent : Colors.white70),
                tooltip: 'Calculator',
                onPressed: () => setState(() => _calcVisible = !_calcVisible),
              ),
            IconButton(icon: const Icon(Icons.close), onPressed: _confirmExit),
          ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
                // Section progress bar
                LinearProgressIndicator(
                  value: _currentQuestions.isEmpty ? 0 : (_questionIndex + 1) / _currentQuestions.length,
                  color: _sectionColor(sec.section),
                  backgroundColor: _sectionColor(sec.section).withOpacity(0.12),
                  minHeight: 4,
                ),

                // Info row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _sectionColor(sec.section).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(actSectionDisplayName(sec.section),
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                              color: _sectionColor(sec.section))),
                    ),
                    const SizedBox(width: 8),
                    Text('Q${_questionIndex + 1} of ${_currentQuestions.length}',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const Spacer(),
                    Text('$answered answered',
                        style: TextStyle(fontSize: 11, color: ActColors.midGray)),
                  ]),
                ),

                // Questions
                Expanded(
                  child: q == null
                      ? const Center(child: Text('No questions available.'))
                      : PageView.builder(
                    controller: _pageCtrl,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _currentQuestions.length,
                    itemBuilder: (_, i) {
                      final question = _currentQuestions[i];
                      final isCurrent = i == _questionIndex;
                      return _QuestionPage(
                        question: question,
                        selectedAnswer: isCurrent ? _selectedAnswer : _sectionAnswers[_sectionIndex]?[i],
                        showFeedback: isCurrent ? _showFeedback : (_sectionAnswers[_sectionIndex]?.containsKey(i) ?? false),
                        onSelect: isCurrent ? _selectAnswer : null,
                        isDark: isDark,
                      );
                    },
                  ),
                ),

                // Bottom bar
                _BottomBar(
                  current: _questionIndex,
                  total: _currentQuestions.length,
                  selectedAnswer: _selectedAnswer,
                  showFeedback: _showFeedback,
                  isLastSection: _sectionIndex == widget.sections.length - 1,
                  onPrev: _prevQuestion,
                  onConfirm: _confirmAnswer,
                  onNext: _nextQuestion,
                  sectionColor: _sectionColor(sec.section),
                  isListening: _listening,
                  micEnabled: _micEnabled,
                  onMicTap: _startListening,
                ),
              ],
            ),

            // Floating Calculator overlay
            if (_calcVisible && _showCalcButton)
              Positioned(
                right: 12,
                bottom: 100,
                child: Draggable(
                  feedback: _buildCalculator(),
                  childWhenDragging: const SizedBox.shrink(),
                  child: _buildCalculator(),
                  onDragEnd: (_) {},
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _sectionColor(ActSection s) {
    switch (s) {
      case ActSection.math:    return const Color(0xFF1565C0);
      case ActSection.reading: return const Color(0xFF2E7D32);
      case ActSection.science: return const Color(0xFF6A1B9A);
      default:                 return ActColors.primary;
    }
  }
}

// ── Question page ──────────────────────────────────────────────────────────────
class _QuestionPage extends StatelessWidget {
  final ActQuestion question;
  final String? selectedAnswer;
  final bool showFeedback;
  final void Function(String)? onSelect;
  final bool isDark;

  const _QuestionPage({
    required this.question, required this.selectedAnswer,
    required this.showFeedback, required this.onSelect, required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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

            if (showFeedback) {
              if (isCorrect) {
                borderColor = ActColors.success; bgColor = ActColors.success.withOpacity(0.09);
                textColor = ActColors.success; trailingIcon = Icons.check_circle_outline;
              } else if (isSelected) {
                borderColor = ActColors.danger; bgColor = ActColors.danger.withOpacity(0.09);
                textColor = ActColors.danger; trailingIcon = Icons.cancel_outlined;
              }
            } else if (isSelected) {
              borderColor = ActColors.primary; bgColor = ActColors.primary.withOpacity(0.07);
            }

            return GestureDetector(
              onTap: onSelect == null ? null : () => onSelect!(letter),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: bgColor, borderRadius: BorderRadius.circular(9),
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
                      child: Center(child: Text(letter,
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12,
                              color: (isSelected || (showFeedback && isCorrect)) ? Colors.white : (isDark ? Colors.white70 : Colors.black54)))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(text,
                        style: TextStyle(fontSize: 13.5, height: 1.4, color: textColor,
                            fontWeight: (showFeedback && (isCorrect || isSelected)) ? FontWeight.w600 : FontWeight.normal))),
                    if (trailingIcon != null) Icon(trailingIcon, color: textColor, size: 18),
                  ],
                ),
              ),
            );
          }),
          if (showFeedback) ...[
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
        ],
      ),
    );
  }
}

// ── Bottom action bar ──────────────────────────────────────────────────────────
class _BottomBar extends StatelessWidget {
  final int current, total;
  final String? selectedAnswer;
  final bool showFeedback, isLastSection;
  final bool isListening, micEnabled;
  final VoidCallback onPrev, onConfirm, onNext, onMicTap;
  final Color sectionColor;

  const _BottomBar({
    required this.current, required this.total, required this.selectedAnswer,
    required this.showFeedback, required this.isLastSection,
    required this.onPrev, required this.onConfirm, required this.onNext,
    required this.sectionColor,
    this.isListening = false, this.micEnabled = false,
    required this.onMicTap,
  });

  @override
  Widget build(BuildContext context) {
    final isLastQ = current == total - 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: ActColors.lightBorder)),
      ),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: current > 0 ? onPrev : null,
        ),
        // Mic button in bottom bar when mic is enabled
        if (micEnabled)
          GestureDetector(
            onTap: onMicTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isListening ? ActColors.accent.withOpacity(0.15) : Colors.transparent,
                border: Border.all(
                  color: isListening ? ActColors.accent : ActColors.midGray.withOpacity(0.4),
                  width: 1.5,
                ),
              ),
              child: Icon(
                isListening ? Icons.mic : Icons.mic_outlined,
                size: 20,
                color: isListening ? ActColors.accent : ActColors.midGray,
              ),
            ),
          ),
        const Spacer(),
        if (!showFeedback)
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: sectionColor,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: selectedAnswer != null ? onConfirm : null,
            child: const Text('Confirm', style: TextStyle(fontWeight: FontWeight.w700)),
          )
        else
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: sectionColor,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: onNext,
            icon: Icon(isLastQ && isLastSection ? Icons.done_all : Icons.arrow_forward, size: 18),
            label: Text(
              isLastQ ? (isLastSection ? 'Finish Exam' : 'Next Section') : 'Next',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
      ]),
    );
  }
}
