// Core models for SJ ACT

enum ActSection { english, math, reading, science }
enum Difficulty { easy, medium, hard }

ActSection actSectionFromString(String s) {
  switch (s) {
    case 'math':    return ActSection.math;
    case 'reading': return ActSection.reading;
    case 'science': return ActSection.science;
    default:        return ActSection.english;
  }
}

String actSectionToString(ActSection s) {
  switch (s) {
    case ActSection.math:    return 'math';
    case ActSection.reading: return 'reading';
    case ActSection.science: return 'science';
    default:                 return 'english';
  }
}

String actSectionDisplayName(ActSection s) {
  switch (s) {
    case ActSection.math:    return 'Mathematics';
    case ActSection.reading: return 'Reading';
    case ActSection.science: return 'Science';
    default:                 return 'English';
  }
}

Difficulty difficultyFromString(String s) {
  switch (s) {
    case 'hard':   return Difficulty.hard;
    case 'medium': return Difficulty.medium;
    default:       return Difficulty.easy;
  }
}

/// A single ACT practice question. All questions are hardcoded in Dart.
class ActQuestion {
  final String id;
  final int setNumber;       // which question bank set (1, 2, 3...)
  final ActSection section;
  final String skillArea;    // e.g. "Algebra", "Craft and Structure"
  final Difficulty difficulty;
  final String questionText;
  final String? passageText; // for reading/science passages
  final List<String> options; // ACT always uses A/B/C/D (or F/G/H/J for even-numbered)
  final String correctAnswer; // "A", "B", "C", "D" (or "F", "G", "H", "J")
  final String explanation;
  final String? topicTip;    // Specific tip for this skill area

  const ActQuestion({
    required this.id,
    required this.setNumber,
    required this.section,
    required this.skillArea,
    required this.difficulty,
    required this.questionText,
    this.passageText,
    required this.options,
    required this.correctAnswer,
    required this.explanation,
    this.topicTip,
  });

  /// ACT uses A/B/C/D for odd questions, F/G/H/J for even questions.
  /// This helper returns the correct option letter labels.
  List<String> get optionLetters {
    // Standard: A, B, C, D (or F, G, H, J)
    return ['A', 'B', 'C', 'D'];
  }
}

class QuestionResult {
  final String questionId;
  final String givenAnswer;
  final bool isCorrect;
  final Duration timeSpent;

  QuestionResult({
    required this.questionId,
    required this.givenAnswer,
    required this.isCorrect,
    required this.timeSpent,
  });

  Map<String, dynamic> toMap() => {
        'questionId': questionId,
        'givenAnswer': givenAnswer,
        'isCorrect': isCorrect ? 1 : 0,
        'timeSpentMs': timeSpent.inMilliseconds,
      };

  factory QuestionResult.fromMap(Map<String, dynamic> m) => QuestionResult(
        questionId: m['questionId'],
        givenAnswer: m['givenAnswer'],
        isCorrect: m['isCorrect'] == 1,
        timeSpent: Duration(milliseconds: m['timeSpentMs']),
      );
}

/// A full or partial practice attempt.
class ExamAttempt {
  final String id;
  final DateTime startedAt;
  final DateTime? completedAt;
  final int setNumber;
  final ActSection? section;
  final List<QuestionResult> results;

  ExamAttempt({
    required this.id,
    required this.startedAt,
    this.completedAt,
    required this.setNumber,
    this.section,
    required this.results,
  });

  int get correctCount => results.where((r) => r.isCorrect).length;
  int get totalCount => results.length;
  double get accuracy => totalCount == 0 ? 0 : correctCount / totalCount;

  /// Convert raw score to ACT scale (1-36) per section
  double get actScaledScore {
    if (totalCount == 0) return 1.0;
    final pct = accuracy;
    // Rough conversion: 0% → 1, 100% → 36
    return (1 + pct * 35).clamp(1.0, 36.0);
  }
}

/// Independent activation record — one per category.
class ActivationRecord {
  final String category;
  final String code;
  final String deviceId;
  final DateTime activatedAt;
  final DateTime expiresAt;
  final DateTime graceEndsAt;
  final String duration;

  ActivationRecord({
    required this.category,
    required this.code,
    required this.deviceId,
    required this.activatedAt,
    required this.expiresAt,
    required this.graceEndsAt,
    this.duration = '6m',
  });

  bool get isExpired => DateTime.now().isAfter(graceEndsAt);
  bool get isInGrace => DateTime.now().isAfter(expiresAt) && !isExpired;
  bool get isFullyActive => !isExpired;

  Map<String, dynamic> toMap() => {
        'category': category,
        'code': code,
        'deviceId': deviceId,
        'activatedAt': activatedAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'graceEndsAt': graceEndsAt.toIso8601String(),
        'duration': duration,
      };

  factory ActivationRecord.fromMap(Map<String, dynamic> m) => ActivationRecord(
        category: m['category'],
        code: m['code'],
        deviceId: m['deviceId'],
        activatedAt: DateTime.parse(m['activatedAt']),
        expiresAt: DateTime.parse(m['expiresAt']),
        graceEndsAt: DateTime.parse(m['graceEndsAt']),
        duration: m['duration'] ?? '6m',
      );
}

class UserProfile {
  final String fullName;
  final String email;
  final String phone;

  const UserProfile({
    required this.fullName,
    required this.email,
    required this.phone,
  });

  bool get isComplete => fullName.trim().isNotEmpty && email.trim().isNotEmpty && phone.trim().isNotEmpty;
}

/// Leaderboard entry for the fake online leaderboard.
class LeaderboardEntry {
  final int rank;
  final String displayName;
  final double compositeScore;
  final double accuracy;
  final int attempts;
  final bool isRealUser;
  final String badge; // gold/silver/bronze/top5/top10/''
  final DateTime updatedAt;

  LeaderboardEntry({
    required this.rank,
    required this.displayName,
    required this.compositeScore,
    required this.accuracy,
    required this.attempts,
    required this.isRealUser,
    required this.badge,
    required this.updatedAt,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> j) => LeaderboardEntry(
        rank: j['rank'] ?? 0,
        displayName: j['display_name'] ?? '',
        compositeScore: (j['composite_score'] as num?)?.toDouble() ?? 0,
        accuracy: (j['accuracy'] as num?)?.toDouble() ?? 0,
        attempts: j['attempts'] ?? 0,
        isRealUser: j['is_real_user'] ?? false,
        badge: j['badge'] ?? '',
        updatedAt: j['updated_at'] != null
            ? DateTime.tryParse(j['updated_at']) ?? DateTime.now()
            : DateTime.now(),
      );
}

/// Bet for online/wifi challenge
class ChallengeBet {
  final String type;   // ranking | badge | access
  final String value;  // e.g. "5_points_ranking", "gold_badge", "2_hours_access"
  final bool agreed;
  final String proposedBy; // host | guest | opponent

  const ChallengeBet({
    required this.type,
    required this.value,
    required this.agreed,
    required this.proposedBy,
  });
}

/// WiFi challenge room
class WifiRoom {
  final String roomCode;
  final String status;
  final int questionCount;
  final String subject;
  final ChallengeBet? bet;
  final double? hostScore;
  final double? guestScore;

  const WifiRoom({
    required this.roomCode,
    required this.status,
    required this.questionCount,
    required this.subject,
    this.bet,
    this.hostScore,
    this.guestScore,
  });

  factory WifiRoom.fromJson(Map<String, dynamic> j) => WifiRoom(
        roomCode: j['room_code'] ?? '',
        status: j['status'] ?? 'open',
        questionCount: j['question_count'] ?? 30,
        subject: j['subject'] ?? '',
        hostScore: (j['host_score'] as num?)?.toDouble(),
        guestScore: (j['guest_score'] as num?)?.toDouble(),
      );
}
