import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../utils/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TIMER WIDGET
// ─────────────────────────────────────────────────────────────────────────────
/// Standalone countdown timer that calls [onExpire] exactly once.
/// Used in [SectionScreen] and challenge screens.
class ActTimerWidget extends StatefulWidget {
  final Duration duration;
  final VoidCallback onExpire;
  final bool running;

  const ActTimerWidget({
    super.key,
    required this.duration,
    required this.onExpire,
    this.running = true,
  });

  @override
  State<ActTimerWidget> createState() => _ActTimerWidgetState();
}

class _ActTimerWidgetState extends State<ActTimerWidget> {
  late Duration _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remaining = widget.duration;
    if (widget.running) _start();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _remaining -= const Duration(seconds: 1));
      if (_remaining.inSeconds <= 0) {
        t.cancel();
        widget.onExpire();
      }
    });
  }

  @override
  void didUpdateWidget(covariant ActTimerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.running && _timer == null) _start();
    if (!widget.running) _timer?.cancel();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final safe = _remaining.isNegative ? Duration.zero : _remaining;
    final lowTime = safe.inSeconds <= 60;
    final color = lowTime ? ActColors.danger : ActColors.success;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: 15, color: color),
          const SizedBox(width: 5),
          Text(
            _format(safe),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: color,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCORE CARD WIDGET
// ─────────────────────────────────────────────────────────────────────────────
/// Displays an ACT scaled score (1–36) with label and accuracy bar.
class ActScoreCardWidget extends StatelessWidget {
  final double actScore;   // 1.0 – 36.0
  final double accuracy;   // 0.0 – 1.0
  final int correct;
  final int total;
  final String label;

  const ActScoreCardWidget({
    super.key,
    required this.actScore,
    required this.accuracy,
    required this.correct,
    required this.total,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = ActColors.scoreColor(actScore);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? ActColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: ActColors.midGray, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(actScore.toStringAsFixed(1),
                style: TextStyle(fontSize: 52, fontWeight: FontWeight.w900, color: color, height: 1)),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(' / 36', style: TextStyle(fontSize: 18, color: ActColors.midGray)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$correct / $total correct  ·  ${(accuracy * 100).toStringAsFixed(0)}%',
            style: TextStyle(fontSize: 12, color: ActColors.midGray),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: accuracy.clamp(0.0, 1.0),
              minHeight: 7,
              color: color,
              backgroundColor: color.withOpacity(0.12),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION CARD WIDGET
// ─────────────────────────────────────────────────────────────────────────────
/// Compact card for each ACT section shown on the home screen grid.
class ActSectionCardWidget extends StatelessWidget {
  final ActSection section;
  final String subtitle;
  final bool isLocked;
  final VoidCallback onTap;

  const ActSectionCardWidget({
    super.key,
    required this.section,
    required this.subtitle,
    required this.isLocked,
    required this.onTap,
  });

  IconData get _icon {
    switch (section) {
      case ActSection.math:    return Icons.functions_outlined;
      case ActSection.reading: return Icons.menu_book_outlined;
      case ActSection.science: return Icons.science_outlined;
      default:                 return Icons.edit_note_outlined;
    }
  }

  Color get _accentColor {
    switch (section) {
      case ActSection.math:    return const Color(0xFF1565C0);
      case ActSection.reading: return const Color(0xFF2E7D32);
      case ActSection.science: return const Color(0xFF6A1B9A);
      default:                 return ActColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isLocked ? ActColors.midGray : _accentColor;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? ActColors.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(isLocked ? 0.12 : 0.22)),
          boxShadow: isLocked ? [] : [BoxShadow(color: color.withOpacity(0.07), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: color.withOpacity(0.11),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(isLocked ? Icons.lock_outlined : _icon, size: 18, color: color),
            ),
            const Spacer(),
            Text(
              actSectionDisplayName(section),
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: isLocked ? ActColors.midGray : null),
            ),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(fontSize: 10, color: ActColors.midGray)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LEADERBOARD WIDGET  (inline, for embedding in home or result screen)
// ─────────────────────────────────────────────────────────────────────────────
class ActLeaderboardWidget extends StatelessWidget {
  final List<LeaderboardEntry> entries;
  final String? currentUserName;

  const ActLeaderboardWidget({
    super.key,
    required this.entries,
    this.currentUserName,
  });

  Color _badgeColor(String badge) {
    switch (badge) {
      case 'gold':   return const Color(0xFFD4A017);
      case 'silver': return const Color(0xFF9E9E9E);
      case 'bronze': return const Color(0xFFCD7F32);
      default:       return ActColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          'Complete a practice session to appear on the leaderboard.',
          textAlign: TextAlign.center,
          style: TextStyle(color: ActColors.midGray, fontSize: 13),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: min(entries.length, 10),
      separatorBuilder: (_, __) => Divider(height: 1, color: isDark ? ActColors.darkBorder : ActColors.lightBorder),
      itemBuilder: (context, i) {
        final e = entries[i];
        final isUser = e.isRealUser || (currentUserName != null && e.displayName.contains(currentUserName!));
        final hasTop3Badge = ['gold', 'silver', 'bronze'].contains(e.badge);

        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 14,
            backgroundColor: hasTop3Badge ? _badgeColor(e.badge).withOpacity(0.15) : (isDark ? ActColors.darkSurface : const Color(0xFFF0F0F0)),
            child: Text(
              '${e.rank}',
              style: TextStyle(
                color: hasTop3Badge ? _badgeColor(e.badge) : null,
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
          ),
          title: Text(
            isUser ? '${e.displayName} (You)' : e.displayName,
            style: TextStyle(
              fontWeight: isUser ? FontWeight.w700 : FontWeight.w500,
              fontSize: 13,
              color: isUser ? ActColors.accent : null,
            ),
          ),
          trailing: Text(
            e.compositeScore.toStringAsFixed(1),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: ActColors.scoreColor(e.compositeScore),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MOTIVATION BANNER WIDGET
// ─────────────────────────────────────────────────────────────────────────────
class ActMotivationBanner extends StatelessWidget {
  final String message;

  const ActMotivationBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? ActColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ActColors.primary.withOpacity(0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            width: 3,
            height: 40,
            decoration: BoxDecoration(
              color: ActColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: isDark ? Colors.white70 : Colors.black87,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// READINESS GAUGE WIDGET
// ─────────────────────────────────────────────────────────────────────────────
/// Semi-circle gauge showing how ready the user is for the real ACT.
/// Score range: 1–36. Threshold zones:
///   < 18 = Needs Work (red)
///   18–25 = Average (orange)
///   26–31 = Good (yellow)
///   32–36 = Excellent (green)
class ActReadinessGauge extends StatelessWidget {
  final double score; // 1.0 – 36.0

  const ActReadinessGauge({super.key, required this.score});

  Color get _color => ActColors.scoreColor(score);

  String get _label {
    if (score >= 32) return 'Excellent';
    if (score >= 26) return 'Good';
    if (score >= 18) return 'Average';
    return 'Needs Work';
  }

  @override
  Widget build(BuildContext context) {
    final pct = ((score - 1) / 35).clamp(0.0, 1.0);
    return SizedBox(
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(200, 110),
            painter: _GaugePainter(progress: pct, color: _color),
          ),
          Positioned(
            bottom: 8,
            child: Column(
              children: [
                Text(
                  score.toStringAsFixed(1),
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: _color),
                ),
                Text(_label, style: TextStyle(fontSize: 12, color: _color, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double progress;
  final Color color;

  _GaugePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final radius = size.width / 2 - 8;

    final bgPaint = Paint()
      ..color = color.withOpacity(0.12)
      ..strokeWidth = 14
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fgPaint = Paint()
      ..color = color
      ..strokeWidth = 14
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const startAngle = pi;
    const sweepAngle = pi;

    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweepAngle, false, bgPaint);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweepAngle * progress, false, fgPaint);
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.progress != progress || old.color != color;
}
