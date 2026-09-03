import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/database_service.dart';
import '../services/leaderboard_service.dart';
import '../services/user_profile_service.dart';
import '../utils/theme.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  List<LeaderboardEntry> _entries = [];
  bool _loading = true;
  String _groupId = '';
  String _displayName = '';
  int? _userRank;
  String? _lastMilestone;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load(sync: true);
    // Auto-refresh every 5 minutes — simulates live board activity
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (_) => _load(sync: true));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool sync = false}) async {
    if (!mounted) return;
    if (_entries.isEmpty) setState(() => _loading = true);

    _displayName = await UserProfileService.getDisplayName() ?? 'You';
    _groupId = await ActLeaderboardService.getOrCreateGroupId();

    // Get user's own entries
    final ownRows = await DatabaseService.instance.getLeaderboardEntries();
    final realRows = ownRows.map((r) => {
      'displayName': r['displayName'] as String? ?? _displayName,
      'compositeScore': r['compositeScore'] ?? 0.0,
      'accuracy': r['accuracy'] ?? 0.0,
      'attempts': r['attempts'] ?? 1,
    }).toList();

    final entries = await ActLeaderboardService.buildMergedBoard(realRows, sync: sync);

    // Find user rank
    int? userRank;
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].isRealUser) {
        userRank = entries[i].rank;
        break;
      }
    }

    // Check for milestone achievement
    String? milestone;
    if (userRank != null) {
      milestone = ActLeaderboardService.checkMilestone(userRank);
    }

    if (!mounted) return;
    setState(() {
      _entries = entries;
      _userRank = userRank;
      _loading = false;
    });

    // Show milestone popup if newly achieved
    if (milestone != null && milestone != _lastMilestone) {
      _lastMilestone = milestone;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showMilestoneBadge(milestone!));
    }
  }

  void _showMilestoneBadge(String milestone) {
    String title, subtitle, emoji;
    switch (milestone) {
      case 'gold':
        title = 'Rank #1 — Top of the Board';
        subtitle = 'You are the highest-ranked student in your group. Extraordinary work.';
        emoji = '1';
        break;
      case 'silver':
        title = 'Rank #2 — Elite Tier';
        subtitle = 'Second place in your group. You are outperforming nearly everyone.';
        emoji = '2';
        break;
      case 'bronze':
        title = 'Rank #3 — Top Three';
        subtitle = 'Third place in your group. You are among the top performers.';
        emoji = '3';
        break;
      case 'top5':
        title = 'Top 5 — Outstanding';
        subtitle = 'You have broken into the top 5 of your group. Keep pushing.';
        emoji = '5';
        break;
      case 'top10':
        title = 'Top 10 — Excellent Standing';
        subtitle = 'You have reached the top 10 in your group. Solid performance.';
        emoji = '10';
        break;
      default:
        return;
    }

    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: milestone == 'gold'
                        ? [const Color(0xFFD4A017), const Color(0xFFF0C040)]
                        : milestone == 'silver'
                            ? [const Color(0xFF9E9E9E), const Color(0xFFCFCFCF)]
                            : milestone == 'bronze'
                                ? [const Color(0xFF8D4E2A), const Color(0xFFCD7F32)]
                                : [ActColors.primary, ActColors.primaryLight],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: Text(
                    emoji,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 28),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              const SizedBox(height: 10),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: ActColors.midGray, height: 1.45)),
              const SizedBox(height: 24),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: ActColors.primary,
                  minimumSize: const Size(double.infinity, 46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Continue', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Leaderboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => _load(sync: true),
          ),
        ],
      ),
      body: Column(
        children: [
          // Notice banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: ActColors.primary.withOpacity(0.07),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Group $_groupId',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ActColors.primary),
                ),
                Text(
                  'You are placed in a random group. You may not see friends here — this is by design. Updated every 5 minutes.',
                  style: TextStyle(fontSize: 10, color: ActColors.midGray, height: 1.4),
                ),
              ],
            ),
          ),

          // User rank summary
          if (_userRank != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: ActColors.accent.withOpacity(0.07),
              child: Row(
                children: [
                  Icon(Icons.person_outline, size: 16, color: ActColors.accent),
                  const SizedBox(width: 8),
                  Text(
                    'Your rank: #$_userRank',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: ActColors.accent),
                  ),
                  const Spacer(),
                  Text(
                    _rankLabel(_userRank!),
                    style: TextStyle(fontSize: 11, color: ActColors.accent),
                  ),
                ],
              ),
            ),

          // List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _entries.length,
                    itemBuilder: (context, i) {
                      final e = _entries[i];
                      final isUser = e.isRealUser;
                      return _LeaderboardRow(
                        entry: e,
                        isUser: isUser,
                        isDark: isDark,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _rankLabel(int rank) {
    if (rank == 1) return 'Top of the board';
    if (rank <= 3) return 'Top 3';
    if (rank <= 5) return 'Top 5';
    if (rank <= 10) return 'Top 10';
    if (rank <= 25) return 'Top 25';
    return 'Keep climbing';
  }
}

class _LeaderboardRow extends StatelessWidget {
  final LeaderboardEntry entry;
  final bool isUser;
  final bool isDark;

  const _LeaderboardRow({
    required this.entry,
    required this.isUser,
    required this.isDark,
  });

  Widget _badgeWidget(String badge) {
    if (badge.isEmpty) return const SizedBox.shrink();
    Color color;
    String label;
    switch (badge) {
      case 'gold':   color = const Color(0xFFD4A017); label = '#1'; break;
      case 'silver': color = const Color(0xFF9E9E9E); label = '#2'; break;
      case 'bronze': color = const Color(0xFFCD7F32); label = '#3'; break;
      case 'top5':   color = ActColors.primary;        label = 'T5'; break;
      case 'top10':  color = ActColors.info;           label = 'T10'; break;
      default:       return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = isUser
        ? ActColors.accent.withOpacity(0.08)
        : (isDark ? ActColors.darkCard : Colors.white);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isUser ? ActColors.accent.withOpacity(0.30) : (isDark ? ActColors.darkBorder : ActColors.lightBorder),
          width: isUser ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          // Rank
          SizedBox(
            width: 32,
            child: Text(
              '#${entry.rank}',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: entry.rank <= 3 ? _badgeColor(entry.badge) : null,
              ),
            ),
          ),

          // Badge
          _badgeWidget(entry.badge),
          const SizedBox(width: 8),

          // Name
          Expanded(
            child: Text(
              isUser ? '${entry.displayName} (You)' : entry.displayName,
              style: TextStyle(
                fontWeight: isUser ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13,
                color: isUser ? ActColors.accent : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Score
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                entry.compositeScore.toStringAsFixed(1),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: ActColors.scoreColor(entry.compositeScore),
                ),
              ),
              Text(
                '${(entry.accuracy * 100).toStringAsFixed(0)}% acc',
                style: TextStyle(fontSize: 10, color: ActColors.midGray),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _badgeColor(String badge) {
    switch (badge) {
      case 'gold':   return const Color(0xFFD4A017);
      case 'silver': return const Color(0xFF9E9E9E);
      case 'bronze': return const Color(0xFFCD7F32);
      default:       return ActColors.primary;
    }
  }
}
