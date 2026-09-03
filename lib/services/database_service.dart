import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();
  DatabaseService._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'sj_act.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async => _createTables(db),
    );
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE attempts (
        id TEXT PRIMARY KEY,
        startedAt TEXT,
        completedAt TEXT,
        setNumber INTEGER,
        section TEXT,
        resultsJson TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE notes (
        id TEXT PRIMARY KEY,
        topic TEXT,
        content TEXT,
        updatedAt TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE leaderboard_sim (
        displayName TEXT PRIMARY KEY,
        compositeScore REAL,
        accuracy REAL,
        updatedAt TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE activation_cache (
        category TEXT PRIMARY KEY,
        code TEXT,
        deviceId TEXT,
        activatedAt TEXT,
        expiresAt TEXT,
        graceEndsAt TEXT,
        duration TEXT,
        signature TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE clock_guard (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        lastSeenAt TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE timetable (
        id TEXT PRIMARY KEY,
        section TEXT,
        dayOfWeek INTEGER,
        startHour INTEGER,
        startMinute INTEGER,
        durationMinutes INTEGER,
        label TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE daily_practice (
        dayKey TEXT PRIMARY KEY,
        questionsAnswered INTEGER,
        correctAnswered INTEGER,
        timeSpentMs INTEGER,
        topicsJson TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE challenge_bets (
        id TEXT PRIMARY KEY,
        sessionId TEXT,
        betType TEXT,
        betValue TEXT,
        outcome TEXT,
        createdAt TEXT
      )
    ''');
  }

  // ── Attempts ─────────────────────────────────────────────────────────────
  Future<void> saveAttempt(ExamAttempt attempt) async {
    final map = {
      'id': attempt.id,
      'startedAt': attempt.startedAt.toIso8601String(),
      'completedAt': attempt.completedAt?.toIso8601String(),
      'setNumber': attempt.setNumber,
      'section': attempt.section != null ? actSectionToString(attempt.section!) : null,
      'resultsJson': jsonEncode(attempt.results.map((r) => r.toMap()).toList()),
    };
    if (kIsWeb) {
      await _webUpsert('attempts', 'id', attempt.id, map);
    } else {
      final db = await database;
      await db.insert('attempts', map, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<List<ExamAttempt>> getAllAttempts() async {
    List<Map<String, dynamic>> rows;
    if (kIsWeb) {
      rows = await _webGetAll('attempts');
    } else {
      final db = await database;
      rows = await db.query('attempts', orderBy: 'startedAt DESC');
    }
    return rows.map((r) {
      final results = (jsonDecode(r['resultsJson'] as String? ?? '[]') as List)
          .map((m) => QuestionResult.fromMap(m as Map<String, dynamic>))
          .toList();
      return ExamAttempt(
        id: r['id'] as String,
        startedAt: DateTime.parse(r['startedAt'] as String),
        completedAt: r['completedAt'] != null ? DateTime.tryParse(r['completedAt'] as String) : null,
        setNumber: r['setNumber'] as int? ?? 1,
        section: r['section'] != null ? actSectionFromString(r['section'] as String) : null,
        results: results,
      );
    }).toList();
  }

  // ── Activation cache ──────────────────────────────────────────────────────
  Future<void> cacheActivation(ActivationRecord record, String signature) async {
    final map = {
      'category': record.category,
      'code': record.code,
      'deviceId': record.deviceId,
      'activatedAt': record.activatedAt.toIso8601String(),
      'expiresAt': record.expiresAt.toIso8601String(),
      'graceEndsAt': record.graceEndsAt.toIso8601String(),
      'duration': record.duration,
      'signature': signature,
    };
    if (kIsWeb) {
      await _webUpsert('activation_cache', 'category', record.category, map);
    } else {
      final db = await database;
      await db.insert('activation_cache', map, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<Map<String, dynamic>?> getCachedActivation(String category) async {
    if (kIsWeb) {
      final rows = await _webGetAll('activation_cache');
      try {
        return rows.firstWhere((r) => r['category'] == category);
      } catch (_) {
        return null;
      }
    } else {
      final db = await database;
      final rows = await db.query('activation_cache', where: 'category = ?', whereArgs: [category]);
      return rows.isNotEmpty ? rows.first : null;
    }
  }

  // ── Clock guard ───────────────────────────────────────────────────────────
  Future<bool> checkAndUpdateClockGuard() async {
    final now = DateTime.now();
    Map<String, dynamic>? row;
    if (kIsWeb) {
      final rows = await _webGetAll('clock_guard');
      row = rows.isNotEmpty ? rows.first : null;
    } else {
      final db = await database;
      final rows = await db.query('clock_guard', where: 'id = 1');
      row = rows.isNotEmpty ? rows.first : null;
    }

    if (row != null) {
      final lastSeen = DateTime.tryParse(row['lastSeenAt'] as String? ?? '');
      if (lastSeen != null && now.isBefore(lastSeen.subtract(const Duration(minutes: 5)))) {
        return false; // Clock moved backward
      }
    }

    final guardMap = {'id': 1, 'lastSeenAt': now.toIso8601String()};
    if (kIsWeb) {
      await _webUpsert('clock_guard', 'id', '1', guardMap);
    } else {
      final db = await database;
      await db.insert('clock_guard', guardMap, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    return true;
  }

  // ── Leaderboard sim entries (user's own) ──────────────────────────────────
  Future<void> upsertLeaderboardEntry(String displayName, double compositeScore, double accuracy) async {
    final map = {
      'displayName': displayName,
      'compositeScore': compositeScore,
      'accuracy': accuracy,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    if (kIsWeb) {
      await _webUpsert('leaderboard_sim', 'displayName', displayName, map);
    } else {
      final db = await database;
      await db.insert('leaderboard_sim', map, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<List<Map<String, dynamic>>> getLeaderboardEntries() async {
    if (kIsWeb) return _webGetAll('leaderboard_sim');
    final db = await database;
    return db.query('leaderboard_sim', orderBy: 'compositeScore DESC');
  }

  // ── Timetable ─────────────────────────────────────────────────────────────
  Future<void> saveTimetableEntry(Map<String, dynamic> entry) async {
    if (kIsWeb) {
      await _webUpsert('timetable', 'id', entry['id'] as String, entry);
    } else {
      final db = await database;
      await db.insert('timetable', entry, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<List<Map<String, dynamic>>> getTimetable() async {
    if (kIsWeb) return _webGetAll('timetable');
    final db = await database;
    return db.query('timetable', orderBy: 'dayOfWeek, startHour, startMinute');
  }

  Future<void> deleteTimetableEntry(String id) async {
    if (kIsWeb) {
      await _webDelete('timetable', 'id', id);
    } else {
      final db = await database;
      await db.delete('timetable', where: 'id = ?', whereArgs: [id]);
    }
  }

  // ── Notes ─────────────────────────────────────────────────────────────────
  Future<void> saveNote(String id, String topic, String content) async {
    final map = {
      'id': id,
      'topic': topic,
      'content': content,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    if (kIsWeb) {
      await _webUpsert('notes', 'id', id, map);
    } else {
      final db = await database;
      await db.insert('notes', map, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<List<Map<String, dynamic>>> getNotes() async {
    if (kIsWeb) return _webGetAll('notes');
    final db = await database;
    return db.query('notes', orderBy: 'updatedAt DESC');
  }

  // ── Web fallback (JSON in SharedPreferences) ──────────────────────────────
  final Map<String, List<Map<String, dynamic>>> _webCache = {};
  SharedPreferences? _prefs;
  Future<SharedPreferences> get _webPrefs async => _prefs ??= await SharedPreferences.getInstance();

  String _webKey(String table) => 'sj_act_web_$table';

  Future<List<Map<String, dynamic>>> _webGetAll(String table) async {
    if (_webCache.containsKey(table)) return List.from(_webCache[table]!);
    final prefs = await _webPrefs;
    final raw = prefs.getString(_webKey(table));
    if (raw == null) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    _webCache[table] = list;
    return List.from(list);
  }

  Future<void> _webSave(String table, List<Map<String, dynamic>> rows) async {
    _webCache[table] = rows;
    final prefs = await _webPrefs;
    await prefs.setString(_webKey(table), jsonEncode(rows));
  }

  Future<void> _webUpsert(String table, String pk, String pkVal, Map<String, dynamic> row) async {
    final rows = await _webGetAll(table);
    final idx = rows.indexWhere((r) => r[pk]?.toString() == pkVal);
    if (idx >= 0) {
      rows[idx] = row;
    } else {
      rows.add(row);
    }
    await _webSave(table, rows);
  }

  Future<void> _webDelete(String table, String pk, String pkVal) async {
    final rows = await _webGetAll(table);
    rows.removeWhere((r) => r[pk]?.toString() == pkVal);
    await _webSave(table, rows);
  }
}
