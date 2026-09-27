import 'package:flutter/material.dart';

import '../data/questions_data.dart';
import '../utils/theme.dart';

/// Full-screen picker for the 100 ACT practice sets (ACT 1 – ACT 100).
///
/// Replaces the old inline set-picker popups (a 3-chip Row inside an
/// AlertDialog, and a SimpleDialog with 3 options) that only ever worked
/// because there were only 3 sets to show. A dedicated screen — instead of
/// a dialog — is what makes 100 options actually usable: a proper AppBar,
/// full height to grow into, a responsive grid that re-flows its column
/// count to the device width (so it never gets cramped on a phone or
/// sparse on a tablet), and a jump-to-number search box so finding e.g.
/// "ACT 73" never means scrolling through a long list by hand.
///
/// Returns the chosen set number via `Navigator.pop(context, setNumber)`,
/// or `null` if the person backs out without choosing. Locked sets never
/// pop a value — tapping one calls [onLockedTap] (or shows a default
/// message) so the caller can route to an upgrade/activation flow.
class ActSetSelectionScreen extends StatefulWidget {
  /// The set to highlight as currently selected, if any.
  final int? initialSet;

  /// Whether [setNumber] is locked (e.g. needs Standard activation).
  final bool Function(int setNumber) isLocked;

  /// Called when the person taps a locked set. If omitted, a SnackBar
  /// with a generic activation hint is shown instead.
  final void Function(int setNumber)? onLockedTap;

  /// Short line shown under the search box (e.g. free-plan/trial status).
  /// Omit for no subtitle.
  final String? subtitle;

  final String title;

  const ActSetSelectionScreen({
    super.key,
    this.initialSet,
    required this.isLocked,
    this.onLockedTap,
    this.subtitle,
    this.title = 'Choose a Practice Set',
  });

  @override
  State<ActSetSelectionScreen> createState() => _ActSetSelectionScreenState();
}

class _ActSetSelectionScreenState extends State<ActSetSelectionScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _handleTap(int setNumber, bool locked) {
    if (locked) {
      if (widget.onLockedTap != null) {
        widget.onLockedTap!(setNumber);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('ACT $setNumber needs Standard activation. ACT 1 is free.'),
        ));
      }
      return;
    }
    Navigator.of(context).pop(setNumber);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;

    // Fall back to a plain 1..100 list if the question bank somehow
    // hasn't finished loading yet (it always should have, by the time any
    // screen can reach this picker — see splash_screen.dart) so the
    // picker still renders something sensible instead of an empty grid.
    final all = availableSetNumbers.isNotEmpty
        ? availableSetNumbers
        : List<int>.generate(100, (i) => i + 1);

    // If the question bank actually failed to load, every tile here would
    // otherwise look perfectly normal and only fail once the person taps
    // "Start Exam" — surface the real problem right here instead, before
    // they pick a set and hit a dead end.
    final bankError = QuestionBank.loadError;

    final query = _query.trim();
    final filtered = query.isEmpty
        ? all
        : all.where((n) => n.toString().contains(query)).toList();

    return Scaffold(
      backgroundColor: isDark ? ActColors.darkBg : ActColors.lightBg,
      appBar: AppBar(
        title: Text(widget.title),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (bankError != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(isDark ? 0.16 : 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withOpacity(0.4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline, size: 18, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Question data failed to load, so sets shown below won\'t '
                        'actually have questions yet:\n$bankError',
                        style: const TextStyle(fontSize: 12, color: Colors.red, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _searchCtrl,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.search,
                style: TextStyle(color: context.textColor),
                decoration: InputDecoration(
                  hintText: 'Jump to a set — e.g. 73',
                  hintStyle: TextStyle(color: context.mutedTextColor, fontSize: 13.5),
                  prefixIcon: Icon(Icons.search, size: 20, color: context.mutedTextColor),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(Icons.close, size: 18, color: context.mutedTextColor),
                          onPressed: () => setState(() {
                            _searchCtrl.clear();
                            _query = '';
                          }),
                        ),
                  isDense: true,
                  filled: true,
                  fillColor: context.surfaceColor,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.hairlineColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.hairlineColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: ActColors.primary, width: 1.4),
                  ),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            if (widget.subtitle != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.subtitle!,
                    style: TextStyle(fontSize: 11.5, color: context.mutedTextColor, height: 1.3),
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No set matches "$query"',
                        style: TextStyle(color: context.mutedTextColor, fontSize: 13),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        // Responsive column count: aim for tiles roughly
                        // 84-104 logical pixels wide so the grid neither
                        // crams on a narrow phone nor leaves huge gaps on
                        // a wide tablet — this is what avoids the
                        // width/scrolling issues a fixed 3-wide Row hit
                        // the moment there were 100 sets instead of 3.
                        final width = constraints.maxWidth;
                        final crossAxisCount = (width / 92).floor().clamp(3, 8);
                        return GridView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 1,
                          ),
                          itemCount: filtered.length,
                          itemBuilder: (context, i) {
                            final n = filtered[i];
                            return _SetTile(
                              setNumber: n,
                              locked: widget.isLocked(n),
                              selected: n == widget.initialSet,
                              onTap: () => _handleTap(n, widget.isLocked(n)),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetTile extends StatelessWidget {
  final int setNumber;
  final bool locked;
  final bool selected;
  final VoidCallback onTap;

  const _SetTile({
    required this.setNumber,
    required this.locked,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;

    final Color bg = selected
        ? ActColors.primary
        : (isDark ? ActColors.darkCard : Colors.white);
    final Color border = selected
        ? ActColors.primary
        : (locked ? context.hairlineColor : context.hairlineColor);
    final Color fg = selected
        ? Colors.white
        : (locked ? context.mutedTextColor : context.textColor);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: selected ? 1.6 : 1),
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'ACT',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: fg.withOpacity(0.75),
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '$setNumber',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: fg,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (locked)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(Icons.lock_outline, size: 13, color: fg.withOpacity(0.8)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
