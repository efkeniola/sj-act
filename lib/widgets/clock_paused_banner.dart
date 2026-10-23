import 'package:flutter/material.dart';

/// Shown while paid access is PAUSED because the phone's date looks moved
/// back (see TrustedClock.isPaused). Access resumes automatically once the
/// date is corrected, or as soon as the app reaches the server.
class ClockPausedBanner extends StatelessWidget {
  const ClockPausedBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFD4A017).withOpacity(0.18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.pause_circle_outline, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              "Your phone's date looks like it was moved back, so paid features are paused. "
              'Set Date & time to "Set automatically" (or correct the date) and connect to the internet to restore them.',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
