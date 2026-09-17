import 'package:flutter/material.dart';

import '../models/play_plan_models.dart';
import '../services/play_catalog_service.dart';
import '../utils/theme.dart';
import 'act_play_checkout_screen.dart';

/// Step 1 of the in-app purchase flow: build your own plan.
///
/// The buyer can select ANY combination of the three categories at once
/// (Standard, Online Challenge, WiFi Challenge), each at its own
/// independent duration. See PlayBillingService's doc comment for how
/// "pay once" is delivered for a multi-category order.
class ActPlanSelectionScreen extends StatefulWidget {
  const ActPlanSelectionScreen({super.key});

  @override
  State<ActPlanSelectionScreen> createState() => _ActPlanSelectionScreenState();
}

class _ActPlanSelectionScreenState extends State<ActPlanSelectionScreen> {
  bool _loading = true;
  List<PlayPlanCategory> _catalog = [];

  final Map<String, String?> _chosen = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final catalog = await PlayCatalogService.fetchCatalog();
    if (!mounted) return;
    setState(() {
      _catalog = catalog;
      for (final cat in catalog) {
        _chosen.putIfAbsent(cat.category, () => null);
      }
      _loading = false;
    });
  }

  List<PlanSelection> get _selections {
    final result = <PlanSelection>[];
    for (final cat in _catalog) {
      final duration = _chosen[cat.category];
      if (duration == null) continue;
      final option = cat.options.firstWhere((o) => o.duration == duration);
      result.add(PlanSelection(category: cat.category, duration: duration, priceUsd: option.priceUsd));
    }
    return result;
  }

  double get _subtotal => _selections.fold(0.0, (sum, s) => sum + s.priceUsd);
  // NOTE: individual option prices already have ACT's 7.5% platform fee
  // baked in (see act/play_plans.py) — Play Console can only charge the
  // exact price configured there. The breakdown below backs the fee
  // portion OUT of each already-inclusive price purely for transparency.
  double get _baseTotal => _subtotal / 1.075;
  double get _feeTotal => _subtotal - _baseTotal;

  @override
  Widget build(BuildContext context) {
    final hasSelection = _selections.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Choose Your Plan')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _catalog.length,
                      itemBuilder: (context, i) => _CategoryCard(
                        plan: _catalog[i],
                        selectedDuration: _chosen[_catalog[i].category],
                        onChanged: (duration) => setState(() => _chosen[_catalog[i].category] = duration),
                      ),
                    ),
                  ),
                  _SummaryBar(
                    selections: _selections,
                    baseTotal: _baseTotal,
                    feeTotal: _feeTotal,
                    total: _subtotal,
                    enabled: hasSelection,
                    onContinue: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ActPlayCheckoutScreen(selections: _selections),
                      ));
                    },
                  ),
                ],
              ),
            ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final PlayPlanCategory plan;
  final String? selectedDuration;
  final ValueChanged<String?> onChanged;

  const _CategoryCard({required this.plan, required this.selectedDuration, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isSelected = selectedDuration != null;
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isSelected ? primary : context.hairlineColor, width: isSelected ? 2 : 1),
        color: isSelected ? primary.withOpacity(context.isDark ? 0.14 : 0.04) : context.surfaceColor,
        boxShadow: [
          if (isSelected) BoxShadow(color: primary.withOpacity(0.18), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: isSelected,
                  activeColor: primary,
                  onChanged: (checked) {
                    if (checked == true) {
                      onChanged(plan.options.first.duration);
                    } else {
                      onChanged(null);
                    }
                  },
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(plan.label,
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: context.textColor)),
                      Text(plan.tagline, style: TextStyle(fontSize: 12, color: context.mutedTextColor)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...plan.features.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 6, left: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle, size: 16, color: ActColors.success),
                      const SizedBox(width: 8),
                      Expanded(child: Text(f, style: TextStyle(fontSize: 12.5, color: context.textColor))),
                    ],
                  ),
                )),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: plan.options.map((opt) {
                final selected = selectedDuration == opt.duration;
                return ChoiceChip(
                  label: Text(
                    '${opt.durationLabel} · \$${opt.priceUsd.toStringAsFixed(2)}',
                    style: TextStyle(color: selected ? context.textColor : context.mutedTextColor),
                  ),
                  selected: selected,
                  backgroundColor: context.panelColor,
                  selectedColor: primary.withOpacity(context.isDark ? 0.30 : 0.18),
                  side: BorderSide(color: context.hairlineColor),
                  onSelected: (_) => onChanged(opt.duration),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  final List<PlanSelection> selections;
  final double baseTotal;
  final double feeTotal;
  final double total;
  final bool enabled;
  final VoidCallback onContinue;

  const _SummaryBar({
    required this.selections,
    required this.baseTotal,
    required this.feeTotal,
    required this.total,
    required this.enabled,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        boxShadow: [BoxShadow(color: context.shadowColor, blurRadius: 12, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (selections.isEmpty)
              Text('Select at least one plan to continue.',
                  style: TextStyle(color: context.mutedTextColor, fontSize: 12), textAlign: TextAlign.center)
            else ...[
              ...selections.map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${s.categoryLabel} · ${s.durationLabel}',
                            style: TextStyle(fontSize: 12.5, color: context.textColor)),
                        Text('\$${s.priceUsd.toStringAsFixed(2)}',
                            style: TextStyle(fontSize: 12.5, color: context.textColor)),
                      ],
                    ),
                  )),
              Divider(height: 16, color: context.hairlineColor),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Subtotal', style: TextStyle(color: context.mutedTextColor, fontSize: 12)),
                  Text('\$${baseTotal.toStringAsFixed(2)}', style: TextStyle(color: context.mutedTextColor, fontSize: 12)),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Platform fee (7.5%)', style: TextStyle(color: context.mutedTextColor, fontSize: 12)),
                  Text('\$${feeTotal.toStringAsFixed(2)}', style: TextStyle(color: context.mutedTextColor, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: context.textColor)),
                  Text('\$${total.toStringAsFixed(2)}',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: primary)),
                ],
              ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: enabled ? onContinue : null,
              child: Text(selections.length > 1 ? 'Continue (${selections.length} plans)' : 'Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
