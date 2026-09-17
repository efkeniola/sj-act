import 'dart:async';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../models/play_plan_models.dart';
import '../services/activation_service.dart';
import '../services/play_billing_service.dart';
import '../services/user_profile_service.dart';
import '../utils/theme.dart';

/// Step 2 of the in-app purchase flow: contact details + order summary,
/// then "Pay with Google Play". One tap here drives the ENTIRE queue in
/// PlayBillingService — see that file's doc comment for the platform
/// reason a multi-category order still shows more than one Play payment
/// sheet.
class ActPlayCheckoutScreen extends StatefulWidget {
  final List<PlanSelection> selections;
  const ActPlayCheckoutScreen({super.key, required this.selections});

  @override
  State<ActPlayCheckoutScreen> createState() => _ActPlayCheckoutScreenState();
}

enum _Stage { form, paying, done }

class _ActPlayCheckoutScreenState extends State<ActPlayCheckoutScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();

  _Stage _stage = _Stage.form;
  String _progressLabel = '';
  final List<PlayQueueResult> _results = [];
  StreamSubscription<PlayQueueEvent>? _sub;
  String? _formError;

  double get _baseTotal => widget.selections.fold(0.0, (s, x) => s + x.priceUsd) / 1.075;
  double get _feeTotal => widget.selections.fold(0.0, (s, x) => s + x.priceUsd) - _baseTotal;
  double get _total => widget.selections.fold(0.0, (s, x) => s + x.priceUsd);

  @override
  void initState() {
    super.initState();
    PlayBillingService().init();
    _loadSavedProfile();
  }

  Future<void> _loadSavedProfile() async {
    final saved = await UserProfileService.getSavedProfile();
    if (!mounted || saved == null) return;
    setState(() {
      _nameController.text = saved.fullName;
      _emailController.text = saved.email;
      _phoneController.text = saved.phone;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _startPurchase() async {
    final profile = UserProfile(
      fullName: _nameController.text.trim(),
      email: _emailController.text.trim(),
      phone: _phoneController.text.trim(),
    );
    if (!profile.isComplete) {
      setState(() => _formError = 'Please enter your full name, email, and phone number.');
      return;
    }
    if (!UserProfileService.isValidEmail(profile.email)) {
      setState(() => _formError = 'Please enter a valid email address.');
      return;
    }
    if (!UserProfileService.isValidPhone(profile.phone)) {
      setState(() => _formError = 'Please enter a valid phone number.');
      return;
    }
    await UserProfileService.saveProfile(profile);

    setState(() {
      _formError = null;
      _stage = _Stage.paying;
      _progressLabel = 'Starting checkout…';
    });

    _sub = PlayBillingService().events.listen(_onEvent);
    await PlayBillingService().buyMany(
      selections: widget.selections,
      name: profile.fullName,
      email: profile.email,
      phone: profile.phone,
    );
  }

  void _onEvent(PlayQueueEvent event) {
    if (!mounted) return;
    switch (event.phase) {
      case PlayQueuePhase.itemStarted:
        setState(() {
          _progressLabel =
              'Opening Google Play for ${event.selection!.categoryLabel} (${event.selection!.durationLabel})… (${event.position} of ${event.total})';
        });
        break;
      case PlayQueuePhase.itemPending:
        setState(() => _progressLabel = 'Payment pending confirmation…');
        break;
      case PlayQueuePhase.recovering:
        setState(() => _progressLabel = 'Recovering your existing purchase…');
        break;
      case PlayQueuePhase.itemSucceeded:
        setState(() => _progressLabel = '${event.selection!.categoryLabel} activated. Continuing…');
        _activateInBackground(event.code!);
        break;
      case PlayQueuePhase.itemFailed:
        setState(() =>
            _progressLabel = '${event.selection!.categoryLabel} could not be purchased: ${event.message}. Continuing…');
        break;
      case PlayQueuePhase.itemCancelled:
        setState(() => _progressLabel = '${event.selection!.categoryLabel} was cancelled. Continuing…');
        break;
      case PlayQueuePhase.allDone:
        setState(() {
          _results
            ..clear()
            ..addAll(event.results!);
          _stage = _Stage.done;
        });
        break;
      case PlayQueuePhase.error:
        setState(() {
          _stage = _Stage.form;
          _formError = event.message;
        });
        break;
    }
  }

  /// Feeds a freshly-issued code through the EXISTING, already-tested
  /// /activate/ flow (device binding, contact storage, expiry) instead of
  /// duplicating that logic here. ACT's redeem() doesn't even need a
  /// category argument — the server determines it from the code alone.
  Future<void> _activateInBackground(String code) async {
    final profile = UserProfile(
      fullName: _nameController.text.trim(),
      email: _emailController.text.trim(),
      phone: _phoneController.text.trim(),
    );
    await ActivationService.redeem(code: code, profile: profile);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: SafeArea(
        child: switch (_stage) {
          _Stage.form => _buildForm(),
          _Stage.paying => _buildProgress(),
          _Stage.done => _buildDone(),
        },
      ),
    );
  }

  Widget _buildForm() {
    final primary = Theme.of(context).colorScheme.primary;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Your Details', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 4),
          Text('Used for your receipt and to retrieve your activation code later if needed.',
              style: TextStyle(fontSize: 12, color: context.mutedTextColor)),
          const SizedBox(height: 14),
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Full name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email address', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone number', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 24),
          const Text('Order Summary', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.panelColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.hairlineColor),
            ),
            child: Column(
              children: [
                ...widget.selections.map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                              child: Text('${s.categoryLabel} — ${s.durationLabel}',
                                  style: TextStyle(color: context.textColor))),
                          Text('\$${s.priceUsd.toStringAsFixed(2)}', style: TextStyle(color: context.textColor)),
                        ],
                      ),
                    )),
                Divider(color: context.hairlineColor),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Subtotal', style: TextStyle(color: context.mutedTextColor)),
                    Text('\$${_baseTotal.toStringAsFixed(2)}', style: TextStyle(color: context.mutedTextColor)),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Platform fee (7.5%)', style: TextStyle(color: context.mutedTextColor)),
                    Text('\$${_feeTotal.toStringAsFixed(2)}', style: TextStyle(color: context.mutedTextColor)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total to pay',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: context.textColor)),
                    Text('\$${_total.toStringAsFixed(2)}',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: primary)),
                  ],
                ),
              ],
            ),
          ),
          if (widget.selections.length > 1) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: ActColors.warning.withOpacity(context.isDark ? 0.18 : 0.08),
                  borderRadius: BorderRadius.circular(10)),
              child: Text(
                'You picked ${widget.selections.length} plans. Google Play bills subscriptions one at a time, so you\'ll '
                'see ${widget.selections.length} quick payment confirmations in a row — this screen walks you through '
                'all of them automatically after one tap below.',
                style: TextStyle(fontSize: 11.5, color: context.isDark ? const Color(0xFFE0B84D) : ActColors.accentDark),
              ),
            ),
          ],
          if (_formError != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: ActColors.danger.withOpacity(context.isDark ? 0.22 : 0.1), borderRadius: BorderRadius.circular(10)),
              child: Text(_formError!,
                  style: TextStyle(color: context.isDark ? const Color(0xFFFF8A80) : ActColors.danger)),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              onPressed: _startPurchase,
              icon: const Icon(Icons.shopping_cart_checkout),
              label: Text('Pay \$${_total.toStringAsFixed(2)} with Google Play'),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Payment is handled entirely by Google Play — SmartJAMB never sees your card details.',
            style: TextStyle(fontSize: 11, color: context.mutedTextColor),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildProgress() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(_progressLabel,
                textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: context.textColor)),
          ],
        ),
      ),
    );
  }

  Widget _buildDone() {
    final succeeded = _results.where((r) => r.success).toList();
    final failed = _results.where((r) => !r.success).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(succeeded.isNotEmpty ? Icons.check_circle : Icons.error_outline,
              size: 56, color: succeeded.isNotEmpty ? ActColors.success : ActColors.danger),
          const SizedBox(height: 12),
          Text(
            succeeded.length == _results.length
                ? 'All set — your plan is active!'
                : succeeded.isEmpty
                    ? 'Purchase could not be completed'
                    : 'Partially completed',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: context.textColor),
          ),
          const SizedBox(height: 16),
          ...succeeded.map((r) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: ActColors.success.withOpacity(context.isDark ? 0.18 : 0.08),
                    borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${r.selection.categoryLabel} — ${r.selection.durationLabel}',
                        style: TextStyle(fontWeight: FontWeight.w700, color: context.textColor)),
                    const SizedBox(height: 4),
                    SelectableText(r.code ?? '',
                        style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: context.textColor)),
                  ],
                ),
              )),
          ...failed.map((r) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: ActColors.danger.withOpacity(context.isDark ? 0.18 : 0.08),
                    borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${r.selection.categoryLabel} — ${r.selection.durationLabel}',
                        style: TextStyle(fontWeight: FontWeight.w700, color: context.textColor)),
                    const SizedBox(height: 4),
                    Text(r.message ?? 'Could not be completed.',
                        style: TextStyle(
                            color: context.isDark ? const Color(0xFFFF8A80) : ActColors.danger, fontSize: 12)),
                  ],
                ),
              )),
          if (succeeded.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Save these codes — you can also retrieve them any time from smartjamb.com using the '
              'same email and phone number, in case you ever need to reinstall.',
              style: TextStyle(fontSize: 12, color: context.mutedTextColor),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
