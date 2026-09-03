// ─────────────────────────────────────────────────────────────────────────────
// syllabus_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';

import '../data/syllabus_data.dart';
import '../models/models.dart';
import '../utils/theme.dart';

class SyllabusScreen extends StatefulWidget {
  const SyllabusScreen({super.key});

  @override
  State<SyllabusScreen> createState() => _SyllabusScreenState();
}

class _SyllabusScreenState extends State<SyllabusScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _sections = ActSection.values;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _sections.length, vsync: this);
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Syllabus'),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          indicatorColor: Colors.white,
          tabs: _sections.map((s) => Tab(text: actSectionDisplayName(s))).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: _sections.map((section) {
          final topics = topicsForSection(section);
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: topics.length,
            itemBuilder: (_, i) => _TopicCard(topic: topics[i]),
          );
        }).toList(),
      ),
    );
  }
}

class _TopicCard extends StatefulWidget {
  final SyllabusTopic topic;
  const _TopicCard({required this.topic});

  @override
  State<_TopicCard> createState() => _TopicCardState();
}

class _TopicCardState extends State<_TopicCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? ActColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? ActColors.darkBorder : ActColors.lightBorder),
      ),
      child: Column(
        children: [
          ListTile(
            title: Text(widget.topic.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            subtitle: Text(widget.topic.skillArea, style: TextStyle(fontSize: 11, color: ActColors.midGray)),
            trailing: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.topic.summary, style: const TextStyle(fontSize: 13, height: 1.45)),
                  const SizedBox(height: 12),
                  _SyllCard(title: 'Topic Tip', body: widget.topic.tip, color: ActColors.accent),
                  const SizedBox(height: 8),
                  _SyllCard(title: 'Improvement Advice', body: widget.topic.advice, color: ActColors.info),
                  const SizedBox(height: 8),
                  const Text('Key Points', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                  const SizedBox(height: 6),
                  ...widget.topic.keyPoints.map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(width: 5, height: 5, margin: const EdgeInsets.only(top: 6, right: 8),
                            decoration: BoxDecoration(shape: BoxShape.circle, color: ActColors.primary)),
                        Expanded(child: Text(p, style: const TextStyle(fontSize: 12, height: 1.4))),
                      ],
                    ),
                  )),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SyllCard extends StatelessWidget {
  final String title, body;
  final Color color;
  const _SyllCard({required this.title, required this.body, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withOpacity(0.07),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withOpacity(0.20)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: color)),
        const SizedBox(height: 6),
        Text(body, style: const TextStyle(fontSize: 12, height: 1.45)),
      ],
    ),
  );
}
