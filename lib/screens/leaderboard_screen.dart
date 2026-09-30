import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../multiplayer/fake_online_challenge.dart';
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
  DateTime? _badgeSuspendedUntil;
  int _betRankingPoints = 0;
  String? _topChallengerToday;

  // ── Online requirement ────────────────────────────────────────────────
  // The board behaves like a live server board: it pings the network the
  // same way Online Challenge does, and refuses to show anything while
  // there is no real internet (Wi-Fi or mobile data).
  bool _netOk = true;
  bool _busy = false;
  Timer? _connectivityTimer;
  DateTime? _lastSynced;

  // ── Rank / score movement since the last time the board was synced ────
  static const _prefLastRank = 'act_lb_last_rank_v1';
  static const _prefLastScore = 'act_lb_last_score_v1';
  int? _rankDelta; // positive = moved up, negative = moved down
  int? _prevRank;
  double? _scoreBefore;
  double? _scoreNow;

  @override
  void initState() {
    super.initState();
    _load(sync: true);
    // Auto-refresh every 5 minutes — simulates live board activity
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (_) => _load(sync: true));
    // Light connectivity watch: if the connection drops the board is hidden,
    // and it comes back (and re-syncs) on its own when the network returns.
    _connectivityTimer = Timer.periodic(const Duration(seconds: 15), (_) => _watchConnection());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _connectivityTimer?.cancel();
    super.dispose();
  }

  Future<void> _watchConnection() async {
    if (!mounted || _busy) return;
    final ok = await FakeOnlineChallenge.hasRealInternet(timeout: const Duration(seconds: 4));
    if (!mounted || _busy) return;
    if (!ok && _netOk) {
      setState(() => _netOk = false);
    } else if (ok && !_netOk) {
      _load(sync: true);
    }
  }

  Future<void> _load({bool sync = false}) async {
    if (!mounted || _busy) return;
    _busy = true;
    try {
      await _loadInner(sync: sync);
    } finally {
      _busy = false;
    }
  }

  Future<void> _loadInner({bool sync = false}) async {
    if (_entries.isEmpty || !_netOk) setState(() => _loading = true);

    // Ping the network first — no internet, no leaderboard.
    final online = await FakeOnlineChallenge.hasRealInternet(timeout: const Duration(seconds: 4));
    if (!mounted) return;
    if (!online) {
      setState(() {
        _netOk = false;
        _loading = false;
      });
      return;
    }

    _displayName = await UserProfileService.getDisplayName() ?? 'You';
    _groupId = await ActLeaderboardService.getOrCreateGroupId();

    // Remove any stray placeholder-named row left over from before
    // leaderboard writes were guarded on a real display name (this is
    // what caused a duplicate "you" entry to show up on the board).
    await DatabaseService.instance.pruneStalePlaceholderLeaderboardEntries(
      await UserProfileService.getDisplayName(),
    );

    // Get user's own entries
    final ownRows = await DatabaseService.instance.getLeaderboardEntries();
    final realRows = ownRows.map((r) => {
      'displayName': r['displayName'] as String? ?? _displayName,
      'compositeScore': r['compositeScore'] ?? 0.0,
      'accuracy': r['accuracy'] ?? 0.0,
      'attempts': r['attempts'] ?? 1,
    }).toList();

    // Bet-consequence state that affects how this board is rendered: a
    // lost "badge" bet hides the user's own rank badge for 24h, a lost
    // "ranking_reset" bet drops it one tier for this session, and a won
    // "bragging_rights" bet pins someone as Top Challenger for the day.
    _badgeSuspendedUntil = await UserProfileService.getChallengerBadgeSuspendedUntil();
    _betRankingPoints = await UserProfileService.getBetRankingPoints();
    _topChallengerToday = await UserProfileService.getTopChallengerToday();

    final entries = await ActLeaderboardService.buildMergedBoard(
      realRows,
      sync: sync,
      suppressOwnBadge: _badgeSuspendedUntil != null,
    );

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

    // Work out whether the user's score / position moved since the last
    // successful sync (e.g. #88 -> #71 after a better score).
    double? myScore;
    for (final e in entries) {
      if (e.isRealUser) {
        myScore = e.compositeScore;
        break;
      }
    }
    int? rankDelta = _rankDelta;
    int? prevRank = _prevRank;
    double? scoreBefore = _scoreBefore;
    double? scoreNow = _scoreNow;
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedRank = prefs.getInt(_prefLastRank);
      final savedScore = prefs.getDouble(_prefLastScore);
      if (userRank != null && myScore != null) {
        final rankChanged = savedRank != null && savedRank != userRank;
        final scoreChanged = savedScore != null && (savedScore - myScore).abs() >= 0.05;
        if (rankChanged || scoreChanged) {
          prevRank = savedRank;
          rankDelta = savedRank != null ? savedRank - userRank : null;
          scoreBefore = savedScore;
          scoreNow = myScore;
        }
        await prefs.setInt(_prefLastRank, userRank);
        await prefs.setDouble(_prefLastScore, myScore);
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _netOk = true;
      _entries = entries;
      _userRank = userRank;
      _rankDelta = rankDelta;
      _prevRank = prevRank;
      _scoreBefore = scoreBefore;
      _scoreNow = scoreNow;
      _lastSynced = DateTime.now();
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
      body: !_netOk
          ? _buildOffline()
          : Column(
        children: [
          // Notice banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: ActColors.primary.withOpacity(0.07),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Group $_groupId',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ActColors.primary),
                    ),
                    const Spacer(),
                    Container(
                      width: 7, height: 7,
                      decoration: BoxDecoration(color: ActColors.success, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _lastSynced == null ? 'Live' : 'Live · synced ${_hhmm(_lastSynced!)}',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: ActColors.success),
                    ),
                  ],
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

          // Score / position movement since the last sync.
          if (_userRank != null && _rankDelta != null && _rankDelta != 0)
            _buildMovementBanner(),

          // Bet ranking points — persistent tally from "ranking" bets.
          if (_betRankingPoints != 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: (_betRankingPoints > 0 ? ActColors.success : ActColors.danger).withOpacity(0.08),
              child: Row(
                children: [
                  Icon(Icons.military_tech_outlined, size: 15,
                      color: _betRankingPoints > 0 ? ActColors.success : ActColors.danger),
                  const SizedBox(width: 8),
                  Text(
                    'Bet ranking points: ${_betRankingPoints > 0 ? '+' : ''}$_betRankingPoints',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                        color: _betRankingPoints > 0 ? ActColors.success : ActColors.danger),
                  ),
                ],
              ),
            ),

          // Badge suspended — lost a "badge" bet.
          if (_badgeSuspendedUntil != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: ActColors.danger.withOpacity(0.08),
              child: Row(
                children: [
                  Icon(Icons.block, size: 15, color: ActColors.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your Challenger badge is suspended (lost a bet) until '
                      '${_badgeSuspendedUntil!.hour.toString().padLeft(2, '0')}:${_badgeSuspendedUntil!.minute.toString().padLeft(2, '0')}.',
                      style: TextStyle(fontSize: 11, color: ActColors.danger),
                    ),
                  ),
                ],
              ),
            ),

          // Tier drop active — lost a "ranking_reset" bet, for this session.
          if (ActLeaderboardService.isTierDropActiveThisSession)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: ActColors.danger.withOpacity(0.08),
              child: Row(
                children: [
                  Icon(Icons.trending_down, size: 15, color: ActColors.danger),
                  const SizedBox(width: 8),
                  Text(
                    'Your leaderboard tier is dropped one level for this session (lost a bet).',
                    style: TextStyle(fontSize: 11, color: ActColors.danger),
                  ),
                ],
              ),
            ),

          // Top Challenger pin — won a "bragging_rights" bet today.
          if (_topChallengerToday != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: ActColors.warning.withOpacity(0.10),
              child: Row(
                children: [
                  const Icon(Icons.emoji_events_outlined, size: 15, color: Colors.amber),
                  const SizedBox(width: 8),
                  Text(
                    '🏆 Top Challenger today: $_topChallengerToday',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.amber),
                  ),
                ],
              ),
            ),

          // List
          Expanded(
            child: _loading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 14),
                        Text('Connecting to leaderboard…',
                            style: TextStyle(fontSize: 12, color: ActColors.midGray)),
                      ],
                    ),
                  )
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

  String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Widget _buildMovementBanner() {
    final up = (_rankDelta ?? 0) > 0;
    final places = (_rankDelta ?? 0).abs();
    final color = up ? ActColors.success : ActColors.danger;
    final scoreText = (_scoreBefore != null && _scoreNow != null)
        ? ' · score ${_scoreBefore!.toStringAsFixed(1)} → ${_scoreNow!.toStringAsFixed(1)}'
        : '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      color: color.withOpacity(0.09),
      child: Row(
        children: [
          Icon(up ? Icons.trending_up : Icons.trending_down, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${up ? 'Up' : 'Down'} $places place${places == 1 ? '' : 's'}'
              '${_prevRank != null ? ' (#$_prevRank → #$_userRank)' : ''}$scoreText',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
            ),
          ),
          Icon(Icons.cloud_done_outlined, size: 14, color: color),
        ],
      ),
    );
  }

  Widget _buildOffline() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, size: 40, color: ActColors.danger),
            const SizedBox(height: 14),
            const Text('No internet connection detected',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              'The leaderboard needs an internet connection (Wi-Fi or mobile data) to load and update your rank.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: ActColors.midGray),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: ActColors.primary),
              onPressed: () => _load(sync: true),
              child: const Text('Try Again'),
            ),
          ],
        ),
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
