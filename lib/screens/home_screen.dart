import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/motivation_data.dart';
import '../models/models.dart';
import '../services/activation_service.dart';
import '../services/database_service.dart';
import '../services/exam_settings_service.dart';
import '../services/user_profile_service.dart';
import '../utils/constants.dart';
import '../utils/theme.dart';
import 'activation_screen.dart';
import 'exam_mode_screen.dart';
import 'section_screen.dart';
import 'syllabus_screen.dart';
import 'leaderboard_screen.dart';
import 'online_challenge_screen.dart';
import 'wifi_challenge_screen.dart';
import 'settings_screen.dart';
import 'progress_screen.dart';
import 'progress_dashboard_screen.dart';
import 'notes_screen.dart';
import 'timetable_screen.dart';
import 'calculator_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _displayName = 'there';
  bool _standardActive = false;
  bool _onlineActive = false;
  bool _wifiActive = false;
  bool _loading = true;
  int _totalAttempts = 0;
  double _overallAccuracy = 0;
  double _bestComposite = 0;
  int _targetScore = 28;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final name = await UserProfileService.getDisplayName();
    final statuses = await ActivationService.getAllStatuses();
    final targetScore = await ExamSettingsService.getTargetScore();
    final attempts = await DatabaseService.instance.getAllAttempts();
    final totalQ = attempts.fold<int>(0, (p, a) => p + a.totalCount);
    final totalC = attempts.fold<int>(0, (p, a) => p + a.correctCount);
    if (!mounted) return;
    setState(() {
      _displayName = name ?? 'there';
      _standardActive =
          statuses[AppConstants.catStandard]?.isFullyActive ?? false;
      _onlineActive =
          statuses[AppConstants.catOnlineChallenge]?.isFullyActive ?? false;
      _wifiActive =
          statuses[AppConstants.catWifiChallenge]?.isFullyActive ?? false;
      _targetScore = targetScore;
      _totalAttempts = attempts.length;
      _overallAccuracy = totalQ == 0 ? 0 : totalC / totalQ;
      final bestAttempt = attempts.isEmpty
          ? null
          : attempts
              .reduce((a, b) => a.actScaledScore > b.actScaledScore ? a : b);
      _bestComposite = bestAttempt?.actScaledScore ?? 0;
      _loading = false;
    });
  }

  Future<void> _openStore() async {
    final uri = Uri.parse(AppConstants.codeStoreUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Could not open the link. Please check your connection.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? ActColors.darkBg : ActColors.lightBg,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(slivers: [
              // ── Header ──────────────────────────────────────────────────
              SliverAppBar(
                expandedHeight: 160,
                pinned: true,
                backgroundColor: ActColors.primary,
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [ActColors.primaryDark, ActColors.primary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: SafeArea(
                        child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text('SJ ACT',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 14,
                                        letterSpacing: 1.5)),
                              ),
                              const Spacer(),
                              IconButton(
                                  icon: const Icon(Icons.card_giftcard_outlined,
                                      color: Colors.white),
                                  tooltip: 'Get Activation Code',
                                  onPressed: _openStore),
                              IconButton(
                                  icon: const Icon(Icons.verified_outlined,
                                      color: Colors.white),
                                  tooltip: 'Activate',
                                  onPressed: () async {
                                    await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                const ActivationScreen()));
                                    _load();
                                  }),
                              IconButton(
                                  icon: const Icon(Icons.settings_outlined,
                                      color: Colors.white),
                                  onPressed: () async {
                                    await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                const SettingsScreen()));
                                    _load();
                                  }),
                            ]),
                            const SizedBox(height: 12),
                            Text('Hello, $_displayName',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(getMotivation(_displayName),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.80),
                                    fontSize: 12,
                                    height: 1.4)),
                          ]),
                    )),
                  ),
                ),
              ),

              SliverToBoxAdapter(
                  child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Stats ────────────────────────────────────────────────
                      if (_totalAttempts > 0) ...[
                        Row(children: [
                          _StatChip(
                              label: 'Sessions',
                              value: '$_totalAttempts',
                              icon: Icons.assignment_outlined),
                          const SizedBox(width: 8),
                          _StatChip(
                              label: 'Accuracy',
                              value:
                                  '${(_overallAccuracy * 100).toStringAsFixed(0)}%',
                              icon: Icons.track_changes_outlined),
                        ]),
                        const SizedBox(height: 16),
                      ],

                      // ── Score prediction mini-card ───────────────────────────
                      if (_bestComposite > 0)
                        _HomeScoreCard(
                          composite: _bestComposite,
                          target: _targetScore,
                        ),

                      // ── Activation banner ────────────────────────────────────
                      if (!_standardActive)
                        _ActivationBanner(onTap: () async {
                          await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const ActivationScreen()));
                          _load();
                        }),

                      // ═══════════════════════════════════════════════════════
                      // FULL EXAM MODE — first, most prominent card
                      // ═══════════════════════════════════════════════════════
                      _ExamModeHero(
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const ExamModeScreen())),
                      ),
                      const SizedBox(height: 20),

                      // ── Practice Sections ────────────────────────────────────
                      _SectionHeader('Practice Sections'),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.55,
                        children: [
                          _SectionCard(
                              section: ActSection.english,
                              subtitle: '75 Questions · 45 min',
                              isLocked: false,
                              onTap: () => _goToSection(ActSection.english)),
                          _SectionCard(
                              section: ActSection.math,
                              subtitle: '60 Questions · 60 min',
                              isLocked: false,
                              onTap: () => _goToSection(ActSection.math)),
                          _SectionCard(
                              section: ActSection.reading,
                              subtitle: '40 Questions · 35 min',
                              isLocked: !_standardActive,
                              onTap: () => _standardActive
                                  ? _goToSection(ActSection.reading)
                                  : _promptActivation()),
                          _SectionCard(
                              section: ActSection.science,
                              subtitle: '40 Questions · 35 min',
                              isLocked: !_standardActive,
                              onTap: () => _standardActive
                                  ? _goToSection(ActSection.science)
                                  : _promptActivation()),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // ── Tools ────────────────────────────────────────────────
                      _SectionHeader('Tools'),
                      _ToolsRow(
                        standardActive: _standardActive,
                        onSyllabus: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const SyllabusScreen())),
                        onProgress: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const ProgressScreen())),
                        onNotes: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const NotesScreen())),
                        onTimetable: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const TimetableScreen())),
                        onCalculator: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const CalculatorScreen())),
                        onLeaderboard: () => _standardActive
                            ? Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const LeaderboardScreen()))
                            : _promptActivation(),
                      ),

                      // ── Premium Challenges ───────────────────────────────────
                      _SectionHeader('Premium Challenges'),
                      _PremiumChallengeCard(
                        title: 'Online Challenge',
                        subtitle:
                            '30-question speed test vs a live opponent.\nUSA Room · Foreign Room · Subject pick.',
                        icon: Icons.public,
                        badge: 'LIVE',
                        badgeColor: const Color(0xFF1565C0),
                        gradientColors: [
                          const Color(0xFF0D47A1),
                          const Color(0xFF1976D2)
                        ],
                        isLocked: !_onlineActive,
                        // Standard gets 1 free/day
                        freeInfo: _standardActive && !_onlineActive
                            ? '1 free match per day'
                            : null,
                        onTap: () => _onlineActive || _standardActive
                            ? Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const OnlineChallengeScreen()))
                            : _promptActivation(
                                cat: AppConstants.catOnlineChallenge),
                      ),
                      const SizedBox(height: 12),
                      _PremiumChallengeCard(
                        title: 'WiFi Challenge',
                        subtitle:
                            '1v1 real-time on the same network.\nPlace bets · Live chat · Streak rewards.',
                        icon: Icons.wifi,
                        badge: 'HOT',
                        badgeColor: const Color(0xFF2E7D32),
                        gradientColors: [
                          const Color(0xFF1B5E20),
                          const Color(0xFF388E3C)
                        ],
                        isLocked: !_wifiActive,
                        // Standard gets 2 free/day but limited setup
                        freeInfo: _standardActive && !_wifiActive
                            ? '2 free matches/day · 30q min'
                            : null,
                        onTap: () => _wifiActive || _standardActive
                            ? Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => WifiChallengeScreen(
                                        fullAccess: _wifiActive)))
                            : _promptActivation(
                                cat: AppConstants.catWifiChallenge),
                      ),

                      const SizedBox(height: 32),
                    ]),
              )),
            ]),
    );
  }

  void _goToSection(ActSection section) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => SectionScreen(section: section)));
  }

  void _promptActivation({String? cat}) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ActivationScreen(
                initialCategory: cat ?? AppConstants.catStandard)));
    _load();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Exam Mode Hero card — full width, first thing on screen
// ─────────────────────────────────────────────────────────────────────────────
class _ExamModeHero extends StatelessWidget {
  final VoidCallback onTap;
  const _ExamModeHero({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF8C0000), Color(0xFFB30000), Color(0xFFCC2200)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFFB30000).withOpacity(0.4),
                blurRadius: 18,
                offset: const Offset(0, 6))
          ],
        ),
        child: Stack(children: [
          // Background decoration circles
          Positioned(
              right: -20,
              top: -20,
              child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.05)))),
          Positioned(
              right: 30,
              bottom: -30,
              child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.04)))),
          Padding(
            padding: const EdgeInsets.all(20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.20),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white38),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle, color: Colors.white)),
                    const SizedBox(width: 6),
                    const Text('FULL EXAM MODE',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2)),
                  ]),
                ),
                const Spacer(),
                const Icon(Icons.arrow_forward_ios,
                    color: Colors.white60, size: 16),
              ]),
              const SizedBox(height: 14),
              const Text('Official ACT Exam',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      height: 1.1)),
              const SizedBox(height: 6),
              Text(
                  '215 questions · Real timing · Official 1-36 scoring\nCalculator included · Score prediction',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.82),
                      fontSize: 12,
                      height: 1.5)),
              const SizedBox(height: 16),
              // Section chips
              Wrap(spacing: 6, runSpacing: 6, children: [
                _ExamChip('English  75q  45min'),
                _ExamChip('Math  60q  60min'),
                _ExamChip('Reading  40q  35min'),
                _ExamChip('Science  40q  35min'),
              ]),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                    child: Text('Start Full Exam',
                        style: TextStyle(
                            color: Color(0xFFB30000),
                            fontWeight: FontWeight.w800,
                            fontSize: 15))),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _ExamChip extends StatelessWidget {
  final String label;
  const _ExamChip(this.label);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w600)),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium Challenge Card — eye-catching gradient cards for online/wifi
// ─────────────────────────────────────────────────────────────────────────────
class _PremiumChallengeCard extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final String badge;
  final Color badgeColor;
  final List<Color> gradientColors;
  final bool isLocked;
  final String? freeInfo;
  final VoidCallback onTap;

  const _PremiumChallengeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.badge,
    required this.badgeColor,
    required this.gradientColors,
    required this.isLocked,
    required this.onTap,
    this.freeInfo,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: isLocked
              ? null
              : LinearGradient(
                  colors: gradientColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
          color: isLocked ? (isDark ? ActColors.darkCard : Colors.white) : null,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isLocked
                ? (isDark ? ActColors.darkBorder : ActColors.lightBorder)
                : Colors.transparent,
          ),
          boxShadow: isLocked
              ? []
              : [
                  BoxShadow(
                      color: gradientColors.first.withOpacity(0.4),
                      blurRadius: 14,
                      offset: const Offset(0, 5))
                ],
        ),
        child: Stack(children: [
          if (!isLocked) ...[
            Positioned(
                right: -10,
                bottom: -10,
                child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.06)))),
          ],
          Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isLocked
                        ? ActColors.midGray.withOpacity(0.10)
                        : Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(isLocked ? Icons.lock_outlined : icon,
                      color: isLocked ? ActColors.midGray : Colors.white,
                      size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Row(children: [
                        Text(title,
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: isLocked ? null : Colors.white)),
                        const SizedBox(width: 8),
                        if (!isLocked || freeInfo != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: isLocked
                                  ? badgeColor.withOpacity(0.12)
                                  : Colors.white.withOpacity(0.25),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(badge,
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.8,
                                    color:
                                        isLocked ? badgeColor : Colors.white)),
                          ),
                      ]),
                      const SizedBox(height: 2),
                      if (freeInfo != null)
                        Text(freeInfo!,
                            style: TextStyle(
                                fontSize: 10,
                                color: isLocked ? badgeColor : Colors.white70,
                                fontWeight: FontWeight.w600)),
                    ])),
                Icon(Icons.chevron_right,
                    color: isLocked ? ActColors.midGray : Colors.white70,
                    size: 20),
              ]),
              const SizedBox(height: 12),
              Text(subtitle,
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: isLocked
                          ? ActColors.midGray
                          : Colors.white.withOpacity(0.88))),
              if (!isLocked) ...[
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(children: [
                    Icon(Icons.play_circle_filled,
                        color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Text('Tap to start a match',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ]),
                ),
              ],
              if (isLocked && freeInfo == null) ...[
                const SizedBox(height: 10),
                Row(children: [
                  Icon(Icons.lock_outlined, size: 12, color: ActColors.midGray),
                  const SizedBox(width: 6),
                  Text('Activate to unlock full access',
                      style: TextStyle(fontSize: 11, color: ActColors.midGray)),
                ]),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── Reused small widgets ───────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 10),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
      );
}

class _StatChip extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _StatChip(
      {required this.label, required this.value, required this.icon});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
        child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? ActColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isDark ? ActColors.darkBorder : ActColors.lightBorder),
      ),
      child: Row(children: [
        Icon(icon, size: 16, color: ActColors.primary),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          Text(label, style: TextStyle(fontSize: 10, color: ActColors.midGray)),
        ]),
      ]),
    ));
  }
}

class _ActivationBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _ActivationBanner({required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: ActColors.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: ActColors.primary.withOpacity(0.25)),
          ),
          child: Row(children: [
            Icon(Icons.lock_open_outlined, color: ActColors.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('Unlock Full Access',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: ActColors.primary)),
                  Text(
                      'Enter your activation code to unlock all sections, challenges, and tools.',
                      style: TextStyle(
                          fontSize: 11, color: ActColors.midGray, height: 1.4)),
                ])),
            Icon(Icons.chevron_right, color: ActColors.primary, size: 18),
          ]),
        ),
      );
}

class _SectionCard extends StatelessWidget {
  final ActSection section;
  final String subtitle;
  final bool isLocked;
  final VoidCallback onTap;
  const _SectionCard(
      {required this.section,
      required this.subtitle,
      required this.isLocked,
      required this.onTap});

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? ActColors.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isLocked
                  ? (isDark ? ActColors.darkBorder : ActColors.lightBorder)
                  : _color.withOpacity(0.20)),
          boxShadow: isLocked
              ? []
              : [
                  BoxShadow(
                      color: _color.withOpacity(0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: (isLocked ? ActColors.midGray : _color).withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(isLocked ? Icons.lock_outlined : _icon,
                size: 18, color: isLocked ? ActColors.midGray : _color),
          ),
          const Spacer(),
          Text(actSectionDisplayName(section),
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: isLocked ? ActColors.midGray : null)),
          const SizedBox(height: 2),
          Text(subtitle,
              style: TextStyle(fontSize: 10, color: ActColors.midGray)),
        ]),
      ),
    );
  }
}

class _ToolsRow extends StatelessWidget {
  final bool standardActive;
  final VoidCallback onSyllabus,
      onProgress,
      onNotes,
      onTimetable,
      onCalculator,
      onLeaderboard;
  const _ToolsRow(
      {required this.standardActive,
      required this.onSyllabus,
      required this.onProgress,
      required this.onNotes,
      required this.onTimetable,
      required this.onCalculator,
      required this.onLeaderboard});

  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: 8, runSpacing: 8, children: [
        _ToolChip(
            label: 'Syllabus',
            icon: Icons.list_alt_outlined,
            onTap: onSyllabus),
        _ToolChip(
            label: 'Dashboard',
            icon: Icons.dashboard_outlined,
            onTap: onProgress,
            isHighlighted: false),
        _ToolChip(
            label: 'Progress',
            icon: Icons.insights_outlined,
            onTap: onProgress),
        _ToolChip(
            label: 'Notes', icon: Icons.note_alt_outlined, onTap: onNotes),
        _ToolChip(
            label: 'Timetable',
            icon: Icons.calendar_month_outlined,
            onTap: onTimetable),
        _ToolChip(
            label: 'Calculator',
            icon: Icons.calculate_outlined,
            onTap: onCalculator,
            isHighlighted: true),
        _ToolChip(
            label: 'Leaderboard',
            icon: Icons.leaderboard_outlined,
            isLocked: !standardActive,
            onTap: onLeaderboard),
      ]);
}

class _ToolChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isHighlighted;
  final bool isLocked;
  const _ToolChip(
      {required this.label,
      required this.icon,
      required this.onTap,
      this.isHighlighted = false,
      this.isLocked = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveColor = isLocked
        ? ActColors.midGray
        : (isHighlighted ? ActColors.accent : ActColors.midGray);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: isHighlighted && !isLocked
              ? ActColors.accent.withOpacity(0.12)
              : (isDark ? ActColors.darkCard : Colors.white),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: isHighlighted && !isLocked
                  ? ActColors.accent.withOpacity(0.35)
                  : (isDark ? ActColors.darkBorder : ActColors.lightBorder)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(isLocked ? Icons.lock_outlined : icon,
              size: 15, color: effectiveColor),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isLocked ? ActColors.midGray
                      : (isHighlighted ? ActColors.accent : null))),
        ]),
      ),
    );
  }
}

// ── Home screen score prediction mini-card ─────────────────────────────────────
class _HomeScoreCard extends StatelessWidget {
  final double composite;
  final int target;
  const _HomeScoreCard({required this.composite, required this.target});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final score = composite.round();
    final gap = target - score;
    final metTarget = gap <= 0;
    final scoreColor = ActColors.scoreColor(composite);

    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const ProgressDashboardScreen())),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? ActColors.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scoreColor.withOpacity(0.25)),
          boxShadow: [
            BoxShadow(
                color: scoreColor.withOpacity(0.08),
                blurRadius: 10,
                offset: const Offset(0, 3))
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.insights_outlined, size: 16, color: scoreColor),
            const SizedBox(width: 8),
            const Text('Score Prediction & Progress',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: scoreColor.withOpacity(0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('View Dashboard',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: scoreColor)),
                const SizedBox(width: 3),
                Icon(Icons.chevron_right, size: 13, color: scoreColor),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            // Score bubble
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scoreColor.withOpacity(0.10),
                border: Border.all(color: scoreColor, width: 2),
              ),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('$score',
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 22,
                            color: scoreColor,
                            height: 1)),
                    Text('/36',
                        style:
                            TextStyle(fontSize: 9, color: ActColors.midGray)),
                  ]),
            ),
            const SizedBox(width: 16),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Stack(children: [
                      LinearProgressIndicator(
                        value: composite / 36,
                        minHeight: 8,
                        color: scoreColor,
                        backgroundColor: scoreColor.withOpacity(0.10),
                      ),
                      if (!metTarget)
                        FractionallySizedBox(
                          widthFactor: (target / 36).clamp(0.0, 1.0),
                          child: Container(
                              height: 8,
                              decoration: BoxDecoration(
                                  border: Border(
                                      right: BorderSide(
                                          color: ActColors.primary,
                                          width: 2)))),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    Text(_label(score),
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: scoreColor)),
                    const Spacer(),
                    if (!metTarget)
                      Text('$gap pts to target',
                          style: TextStyle(
                              fontSize: 10, color: ActColors.midGray)),
                    if (metTarget)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.emoji_events,
                            size: 12, color: ActColors.success),
                        const SizedBox(width: 3),
                        Text('Target met!',
                            style: TextStyle(
                                fontSize: 10,
                                color: ActColors.success,
                                fontWeight: FontWeight.w700)),
                      ]),
                  ]),
                ])),
          ]),
          const SizedBox(height: 12),
          // Tap hint
          Row(children: [
            Icon(Icons.bar_chart, size: 12, color: ActColors.midGray),
            const SizedBox(width: 6),
            Text('Tap to see subject breakdown, weak topics & study plan',
                style: TextStyle(fontSize: 10, color: ActColors.midGray)),
          ]),
        ]),
      ),
    );
  }

  String _label(int s) {
    if (s >= 34) return 'Exceptional';
    if (s >= 30) return 'Strong';
    if (s >= 26) return 'Above Average';
    if (s >= 21) return 'Average';
    if (s >= 16) return 'Below Average';
    return 'Keep Practicing';
  }
}
