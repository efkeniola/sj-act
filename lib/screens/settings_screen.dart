import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/exam_settings_service.dart';
import '../services/user_profile_service.dart';
import '../services/voice_service.dart';
import '../utils/constants.dart';
import '../utils/theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _darkMode = false;
  bool _voiceEnabled = false;
  bool _sttEnabled = false;
  String _displayName = '';
  final _nameCtrl = TextEditingController();
  bool _nameSaving = false;
  String _answerReveal = 'immediate';

  // Exam settings
  ExamSettings? _examSettings;
  bool _examLoading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final name   = await UserProfileService.getDisplayName();
    final voice  = await VoiceService.instance.isTtsEnabled();
    final stt    = await VoiceService.instance.isSttEnabled();
    final exam   = await ExamSettingsService.loadAll();
    final answerReveal = await ExamSettingsService.getAnswerReveal();
    if (!mounted) return;
    setState(() {
      _darkMode     = darkModeNotifier.value;
      _voiceEnabled = voice;
      _sttEnabled   = stt;
      _displayName  = name ?? '';
      _nameCtrl.text = _displayName;
      _examSettings  = exam;
      _answerReveal  = answerReveal;
      _examLoading   = false;
    });
  }

  Future<void> _saveName() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _nameSaving = true);
    await UserProfileService.setDisplayName(name);
    await ExamSettingsService.setStudentName(name);
    if (mounted) {
      setState(() { _displayName = name; _nameSaving = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Display name updated.'), duration: Duration(seconds: 1)));
    }
  }

  Future<void> _saveExam(ExamSettings s) async {
    setState(() => _examSettings = s);
    await ExamSettingsService.saveAll(s);
  }

  @override
  void dispose() { _nameCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final exam = _examSettings;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.all(16), children: [

        // ── Display ──────────────────────────────────────────────────────────
        _SectionHeader('Display'),
        _SettingsTile(
          icon: Icons.dark_mode_outlined, title: 'Dark Mode',
          subtitle: 'Switch between light and dark theme.', isDark: isDark,
          trailing: Switch(value: _darkMode, activeColor: ActColors.primary,
            onChanged: (v) async { await setDarkMode(v); setState(() => _darkMode = v); }),
        ),

        // ── Profile ──────────────────────────────────────────────────────────
        _SectionHeader('Profile'),
        _SettingsTile(icon: Icons.person_outline, title: 'Display Name',
          subtitle: 'Shown on the leaderboard and in challenges.', isDark: isDark),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
          child: Row(children: [
            Expanded(child: TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                hintText: 'Your display name',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            )),
            const SizedBox(width: 10),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: ActColors.primary),
              onPressed: _nameSaving ? null : _saveName,
              child: _nameSaving
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save'),
            ),
          ]),
        ),

        // ── Exam Mode Settings ───────────────────────────────────────────────
        _SectionHeader('Exam Mode Settings'),
        Container(
          decoration: BoxDecoration(
            color: isDark ? ActColors.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? ActColors.darkBorder : ActColors.lightBorder),
          ),
          child: _examLoading || exam == null
              ? const Padding(padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()))
              : Column(children: [
                  _ExamTimeTile(label: 'English Time', icon: Icons.edit_note_outlined,
                    color: ActColors.primary, minutes: exam.englishMinutes,
                    defaultMinutes: ExamSettingsService.defaultEnglishMinutes,
                    isDark: isDark,
                    onChanged: (v) => _saveExam(exam.copyWith(englishMinutes: v))),
                  _ExamTimeTile(label: 'Math Time', icon: Icons.functions_outlined,
                    color: const Color(0xFF1565C0), minutes: exam.mathMinutes,
                    defaultMinutes: ExamSettingsService.defaultMathMinutes,
                    isDark: isDark,
                    onChanged: (v) => _saveExam(exam.copyWith(mathMinutes: v))),
                  _ExamTimeTile(label: 'Reading Time', icon: Icons.menu_book_outlined,
                    color: const Color(0xFF2E7D32), minutes: exam.readingMinutes,
                    defaultMinutes: ExamSettingsService.defaultReadingMinutes,
                    isDark: isDark,
                    onChanged: (v) => _saveExam(exam.copyWith(readingMinutes: v))),
                  _ExamTimeTile(label: 'Science Time', icon: Icons.science_outlined,
                    color: const Color(0xFF6A1B9A), minutes: exam.scienceMinutes,
                    defaultMinutes: ExamSettingsService.defaultScienceMinutes,
                    isDark: isDark,
                    onChanged: (v) => _saveExam(exam.copyWith(scienceMinutes: v))),
                  const Divider(height: 1),
                  SwitchListTile(
                    value: exam.showCalculator, activeColor: ActColors.primary,
                    title: const Text('Show Calculator in Exam', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text('Floating calculator during Math & Science', style: TextStyle(fontSize: 11, color: ActColors.midGray)),
                    secondary: Icon(Icons.calculate_outlined, color: ActColors.primary),
                    onChanged: (v) => _saveExam(exam.copyWith(showCalculator: v)),
                  ),
                  // Answer reveal mode
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(Icons.visibility_outlined, color: ActColors.primary, size: 18),
                        const SizedBox(width: 8),
                        const Text('Answer Reveal Mode', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        _RevealOption(
                          label: 'Practice', desc: 'Show after each answer',
                          selected: _answerReveal == 'immediate',
                          onTap: () async {
                            await ExamSettingsService.setAnswerReveal('immediate');
                            setState(() => _answerReveal = 'immediate');
                          },
                        ),
                        const SizedBox(width: 8),
                        _RevealOption(
                          label: 'Real ACT', desc: 'Show only at results',
                          selected: _answerReveal == 'end',
                          onTap: () async {
                            await ExamSettingsService.setAnswerReveal('end');
                            setState(() => _answerReveal = 'end');
                          },
                        ),
                      ]),
                      const SizedBox(height: 4),
                    ]),
                  ),
                  SwitchListTile(
                    value: exam.autoSave, activeColor: ActColors.primary,
                    title: const Text('Auto-Save Results', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text('Save scores to history automatically', style: TextStyle(fontSize: 11, color: ActColors.midGray)),
                    secondary: Icon(Icons.save_outlined, color: ActColors.primary),
                    onChanged: (v) => _saveExam(exam.copyWith(autoSave: v)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.restart_alt, size: 16),
                      label: const Text('Reset All Times to Default'),
                      style: OutlinedButton.styleFrom(foregroundColor: ActColors.midGray),
                      onPressed: () async {
                        await ExamSettingsService.resetTimesToDefault();
                        final updated = await ExamSettingsService.loadAll();
                        if (mounted) setState(() => _examSettings = updated);
                      },
                    ),
                  ),
                ]),
        ),

        // ── Target Score ─────────────────────────────────────────────────────
        if (exam != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? ActColors.darkCard : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? ActColors.darkBorder : ActColors.lightBorder),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.flag_outlined, color: ActColors.primary, size: 20),
                const SizedBox(width: 10),
                const Text('Target ACT Score', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: ActColors.scoreColor(exam.targetScore.toDouble()).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('${exam.targetScore}',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20,
                      color: ActColors.scoreColor(exam.targetScore.toDouble()))),
                ),
              ]),
              const SizedBox(height: 12),
              Slider(
                value: exam.targetScore.toDouble(),
                min: 1, max: 36, divisions: 35,
                activeColor: ActColors.primary,
                label: '${exam.targetScore}',
                onChanged: (v) => _saveExam(exam.copyWith(targetScore: v.round())),
              ),
              Text(_scoreLabel(exam.targetScore),
                style: TextStyle(fontSize: 12, color: ActColors.midGray)),
            ]),
          ),
        ],

        // ── Voice Reading ────────────────────────────────────────────────────
        _SectionHeader('Voice Reading'),
        _SettingsTile(
          icon: Icons.volume_up_outlined, title: 'Read Questions Aloud',
          subtitle: 'The app reads each question and options aloud as you practice.',
          isDark: isDark,
          trailing: Switch(value: _voiceEnabled, activeColor: ActColors.primary,
            onChanged: (v) async { await VoiceService.instance.setTtsEnabled(v);
              setState(() => _voiceEnabled = v); }),
        ),
        _SettingsTile(
          icon: Icons.mic_outlined, title: 'Speak Your Answer',
          subtitle: 'Say "A", "B", "C", or "D" to answer hands-free. Needs microphone permission.',
          isDark: isDark,
          trailing: Switch(value: _sttEnabled, activeColor: ActColors.primary,
            onChanged: (v) async { await VoiceService.instance.setSttEnabled(v);
              setState(() => _sttEnabled = v); }),
        ),

        // ── Keyboard Shortcuts ───────────────────────────────────────────────
        _SectionHeader('Keyboard Shortcuts'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? ActColors.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isDark ? ActColors.darkBorder : ActColors.lightBorder),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Available on Windows, macOS, or Linux.',
              style: TextStyle(fontSize: 11, color: ActColors.midGray, height: 1.4)),
            const SizedBox(height: 12),
            ...VoiceService.keyboardShortcuts.entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDark ? ActColors.darkSurface : const Color(0xFFF0F0F0),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: isDark ? ActColors.darkBorder : ActColors.lightBorder),
                  ),
                  child: Text(e.key, style: const TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(e.value, style: const TextStyle(fontSize: 12))),
              ]),
            )),
          ]),
        ),

        // ── Support ──────────────────────────────────────────────────────────
        _SectionHeader('Support'),
        _SettingsTile(
          icon: Icons.email_outlined, title: 'Contact Support',
          subtitle: AppConstants.supportEmail, isDark: isDark,
          onTap: () async {
            final uri = Uri.parse('mailto:${AppConstants.supportEmail}?subject=SJ%20ACT%20Support');
            if (!await launchUrl(uri) && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open email app.')));
            }
          },
        ),
        // ── Prominent Get Activation Code banner ─────────────────────────
        GestureDetector(
          onTap: () async => launchUrl(Uri.parse(AppConstants.codeStoreUrl), mode: LaunchMode.externalApplication),
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [ActColors.primaryDark, ActColors.primary],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: ActColors.primary.withOpacity(0.35),
                blurRadius: 14, offset: const Offset(0, 5))],
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.verified_outlined, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Get Activation Code', style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
                const SizedBox(height: 4),
                Text('Unlock all sections, challenges & tools.',
                  style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12)),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Shop', style: TextStyle(
                  color: ActColors.primary, fontWeight: FontWeight.w800, fontSize: 13)),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 32),
      ]),
    );
  }

  String _scoreLabel(int score) {
    if (score >= 34) return 'Elite — Top 1% nationally';
    if (score >= 30) return 'Excellent — Top universities prefer 30+';
    if (score >= 26) return 'Good — Competitive colleges';
    if (score >= 21) return 'Average — National average is ~21';
    if (score >= 16) return 'Below Average — More practice needed';
    return 'Needs Significant Improvement';
  }
}

// ── Exam time tile ─────────────────────────────────────────────────────────────
class _ExamTimeTile extends StatelessWidget {
  final String label; final IconData icon; final Color color;
  final int minutes, defaultMinutes; final bool isDark;
  final void Function(int) onChanged;

  const _ExamTimeTile({required this.label, required this.icon, required this.color,
    required this.minutes, required this.defaultMinutes, required this.isDark, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const Spacer(),
          Text('${minutes}min', style: TextStyle(fontWeight: FontWeight.w800, color: color)),
          if (minutes != defaultMinutes) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => onChanged(defaultMinutes),
              child: Text('(reset)', style: TextStyle(fontSize: 10, color: ActColors.midGray, decoration: TextDecoration.underline)),
            ),
          ],
        ]),
        Slider(
          value: minutes.toDouble(),
          min: 10, max: defaultMinutes * 2.0,
          divisions: ((defaultMinutes * 2 - 10) ~/ 5).clamp(4, 40),
          activeColor: color,
          label: '${minutes}min',
          onChanged: (v) => onChanged(v.round()),
        ),
      ]),
    );
  }
}

// ── Shared widgets ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text; const _SectionHeader(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
    child: Text(text.toUpperCase(), style: TextStyle(
      fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: ActColors.midGray)),
  );
}

class _SettingsTile extends StatelessWidget {
  final IconData icon; final String title, subtitle; final bool isDark;
  final Widget? trailing; final VoidCallback? onTap;

  const _SettingsTile({required this.icon, required this.title, required this.subtitle,
    required this.isDark, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: isDark ? ActColors.darkCard : Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: isDark ? ActColors.darkBorder : ActColors.lightBorder),
    ),
    child: ListTile(
      leading: Icon(icon, color: ActColors.primary, size: 22),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 11, color: ActColors.midGray, height: 1.35)),
      trailing: trailing ?? (onTap != null ? const Icon(Icons.chevron_right, size: 18) : null),
      onTap: onTap,
    ),
  );
}

class _RevealOption extends StatelessWidget {
  final String label, desc;
  final bool selected;
  final VoidCallback onTap;
  const _RevealOption({required this.label, required this.desc, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? ActColors.primary.withOpacity(0.10) : (isDark ? ActColors.darkSurface : const Color(0xFFF5F5F5)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? ActColors.primary : (isDark ? ActColors.darkBorder : ActColors.lightBorder),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(
            fontWeight: FontWeight.w700, fontSize: 13,
            color: selected ? ActColors.primary : null)),
          const SizedBox(height: 2),
          Text(desc, style: TextStyle(fontSize: 10, color: ActColors.midGray, height: 1.3)),
        ]),
      ),
    ));
  }
}
