import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/database_service.dart';
import '../utils/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PROGRESS SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  List<ExamAttempt> _attempts = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final a = await DatabaseService.instance.getAllAttempts();
    if (mounted) setState(() { _attempts = a; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final total = _attempts.fold<int>(0, (p, a) => p + a.totalCount);
    final correct = _attempts.fold<int>(0, (p, a) => p + a.correctCount);
    final overallAcc = total == 0 ? 0.0 : correct / total;
    final avgScore = _attempts.isEmpty ? 0.0 : _attempts.map((a) => a.actScaledScore).reduce((a, b) => a + b) / _attempts.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _attempts.isEmpty
              ? const Center(child: Text('Complete your first session to see progress here.'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Summary cards
                      Row(children: [
                        _StatBox(label: 'Sessions', value: '${_attempts.length}', isDark: isDark),
                        const SizedBox(width: 10),
                        _StatBox(label: 'Avg ACT Score', value: avgScore.toStringAsFixed(1), isDark: isDark),
                        const SizedBox(width: 10),
                        _StatBox(label: 'Overall Accuracy', value: '${(overallAcc * 100).toStringAsFixed(0)}%', isDark: isDark),
                      ]),

                      const SizedBox(height: 24),
                      const Text('Recent Sessions', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 12),

                      ..._attempts.take(20).map((a) {
                        final scoreColor = ActColors.scoreColor(a.actScaledScore);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isDark ? ActColors.darkCard : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: isDark ? ActColors.darkBorder : ActColors.lightBorder),
                          ),
                          child: Row(children: [
                            Container(
                              width: 52, height: 52,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: scoreColor.withOpacity(0.12),
                                border: Border.all(color: scoreColor.withOpacity(0.3), width: 2),
                              ),
                              child: Center(child: Text(
                                a.actScaledScore.toStringAsFixed(1),
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: scoreColor),
                              )),
                            ),
                            const SizedBox(width: 14),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  a.section != null ? actSectionDisplayName(a.section!) : 'Full Practice',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                ),
                                Text(
                                  '${a.correctCount}/${a.totalCount} correct  ·  ${(a.accuracy * 100).toStringAsFixed(0)}% accuracy',
                                  style: TextStyle(fontSize: 11, color: ActColors.midGray),
                                ),
                                Text(
                                  _formatDate(a.startedAt),
                                  style: TextStyle(fontSize: 10, color: ActColors.midGray),
                                ),
                              ],
                            )),
                          ]),
                        );
                      }),
                    ],
                  ),
                ),
    );
  }

  String _formatDate(DateTime dt) {
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _StatBox extends StatelessWidget {
  final String label, value;
  final bool isDark;
  const _StatBox({required this.label, required this.value, required this.isDark});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: isDark ? ActColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? ActColors.darkBorder : ActColors.lightBorder),
      ),
      child: Column(children: [
        Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: ActColors.primary)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 10, color: ActColors.midGray), textAlign: TextAlign.center),
      ]),
    ),
  );
}


// ─────────────────────────────────────────────────────────────────────────────
// NOTES SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  List<Map<String, dynamic>> _notes = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final n = await DatabaseService.instance.getNotes();
    if (mounted) setState(() { _notes = n; _loading = false; });
  }

  void _openNote({Map<String, dynamic>? existing}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NoteEditor(existing: existing, onSave: (id, topic, content) async {
        await DatabaseService.instance.saveNote(id, topic, content);
        Navigator.pop(context);
        _load();
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Study Notes')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: ActColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () => _openNote(),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notes.isEmpty
              ? const Center(child: Text('No notes yet. Tap + to add one.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _notes.length,
                  itemBuilder: (_, i) {
                    final n = _notes[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: const Icon(Icons.note_alt_outlined),
                        title: Text(n['topic'] as String? ?? 'Note', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        subtitle: Text(n['content'] as String? ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                        onTap: () => _openNote(existing: n),
                      ),
                    );
                  },
                ),
    );
  }
}

class _NoteEditor extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final Future<void> Function(String id, String topic, String content) onSave;
  const _NoteEditor({this.existing, required this.onSave});

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late TextEditingController _topicCtrl, _contentCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _topicCtrl = TextEditingController(text: widget.existing?['topic'] as String? ?? '');
    _contentCtrl = TextEditingController(text: widget.existing?['content'] as String? ?? '');
  }

  @override
  void dispose() { _topicCtrl.dispose(); _contentCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Note', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 14),
            TextField(
              controller: _topicCtrl,
              decoration: InputDecoration(labelText: 'Topic', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _contentCtrl,
              maxLines: 5,
              decoration: InputDecoration(labelText: 'Content', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: ActColors.primary),
                onPressed: _saving ? null : () async {
                  setState(() => _saving = true);
                  final id = widget.existing?['id'] as String? ?? DateTime.now().toIso8601String();
                  await widget.onSave(id, _topicCtrl.text.trim(), _contentCtrl.text.trim());
                },
                child: Text(_saving ? 'Saving...' : 'Save Note'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// TIMETABLE SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;

  final _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final e = await DatabaseService.instance.getTimetable();
    if (mounted) setState(() { _entries = e; _loading = false; });
  }

  void _addEntry() async {
    ActSection section = ActSection.english;
    int dayOfWeek = 1, startHour = 9, startMinute = 0, duration = 60;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add Study Slot'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<ActSection>(
                  value: section,
                  decoration: const InputDecoration(labelText: 'Section', border: OutlineInputBorder()),
                  items: ActSection.values.map((s) => DropdownMenuItem(value: s, child: Text(actSectionDisplayName(s)))).toList(),
                  onChanged: (s) { if (s != null) setLocal(() => section = s); },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  value: dayOfWeek,
                  decoration: const InputDecoration(labelText: 'Day', border: OutlineInputBorder()),
                  items: List.generate(7, (i) => DropdownMenuItem(value: i + 1, child: Text(_days[i]))).toList(),
                  onChanged: (d) { if (d != null) setLocal(() => dayOfWeek = d); },
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: DropdownButtonFormField<int>(
                    value: startHour,
                    decoration: const InputDecoration(labelText: 'Hour', border: OutlineInputBorder()),
                    items: List.generate(24, (h) => DropdownMenuItem(value: h, child: Text('${h.toString().padLeft(2, '0')}:00'))).toList(),
                    onChanged: (h) { if (h != null) setLocal(() => startHour = h); },
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: DropdownButtonFormField<int>(
                    value: duration,
                    decoration: const InputDecoration(labelText: 'Duration (min)', border: OutlineInputBorder()),
                    items: [30, 45, 60, 90, 120].map((d) => DropdownMenuItem(value: d, child: Text('$d min'))).toList(),
                    onChanged: (d) { if (d != null) setLocal(() => duration = d); },
                  )),
                ]),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: ActColors.primary),
              onPressed: () async {
                final entry = {
                  'id': DateTime.now().toIso8601String(),
                  'section': actSectionToString(section),
                  'dayOfWeek': dayOfWeek,
                  'startHour': startHour,
                  'startMinute': startMinute,
                  'durationMinutes': duration,
                  'label': actSectionDisplayName(section),
                };
                await DatabaseService.instance.saveTimetableEntry(entry);
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Study Timetable')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: ActColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: _addEntry,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? const Center(child: Text('No schedule yet. Tap + to add a study slot.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _entries.length,
                  itemBuilder: (_, i) {
                    final e = _entries[i];
                    final dayIdx = (e['dayOfWeek'] as int? ?? 1) - 1;
                    final day = dayIdx >= 0 && dayIdx < _days.length ? _days[dayIdx] : 'Day';
                    final h = e['startHour'] as int? ?? 9;
                    final dur = e['durationMinutes'] as int? ?? 60;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: ActColors.primary.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.calendar_today_outlined, color: ActColors.primary, size: 18),
                        ),
                        title: Text('${e['label'] ?? 'Session'}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        subtitle: Text('$day  ·  ${h.toString().padLeft(2, '0')}:00  ·  $dur min', style: const TextStyle(fontSize: 12)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () async {
                            await DatabaseService.instance.deleteTimetableEntry(e['id'] as String);
                            _load();
                          },
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
