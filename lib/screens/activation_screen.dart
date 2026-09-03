import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/activation_service.dart';
import '../services/user_profile_service.dart';
import '../utils/constants.dart';
import '../utils/theme.dart';

class ActivationScreen extends StatefulWidget {
  final String initialCategory;
  const ActivationScreen({super.key, this.initialCategory = AppConstants.catStandard});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final _codeCtrl  = TextEditingController();
  final _nameCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  bool _submitting = false;
  String? _statusMsg;
  bool _statusIsError = false;

  // Activation records for all three categories
  ActivationRecord? _standardRecord;
  ActivationRecord? _onlineRecord;
  ActivationRecord? _wifiRecord;
  bool _loadingStatus = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loadingStatus = true);
    final profile = await UserProfileService.getSavedProfile();
    if (profile != null) {
      _nameCtrl.text = profile.fullName;
      _emailCtrl.text = profile.email;
      _phoneCtrl.text = profile.phone;
    }
    final statuses = await ActivationService.getAllStatuses();
    if (!mounted) return;
    setState(() {
      _standardRecord = statuses[AppConstants.catStandard];
      _onlineRecord   = statuses[AppConstants.catOnlineChallenge];
      _wifiRecord     = statuses[AppConstants.catWifiChallenge];
      _loadingStatus  = false;
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() { _submitting = true; _statusMsg = null; });

    final profile = UserProfile(
      fullName: _nameCtrl.text,
      email: _emailCtrl.text,
      phone: _phoneCtrl.text,
    );
    final result = await ActivationService.redeem(
      code: _codeCtrl.text,
      profile: profile,
    );

    if (!mounted) return;
    setState(() {
      _submitting = false;
      _statusIsError = result.outcome != ActivationOutcome.success &&
          result.outcome != ActivationOutcome.offlineGraceValid;
      _statusMsg = result.message;
    });

    if (!_statusIsError) {
      _codeCtrl.clear();
      _loadAll();
    }
  }

  Future<void> _openStore() async {
    final uri = Uri.parse(AppConstants.codeStoreUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activation'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.open_in_new, size: 16, color: Colors.white),
            label: const Text('Get Now', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
            onPressed: _openStore,
          ),
        ],
      ),
      body: _loadingStatus
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Current status cards ──────────────────────────────
                  _buildStatusCard('Standard', AppConstants.catStandard, _standardRecord,
                      'Full ACT practice across all sections, analytics, syllabus, calculator, timetable.'),
                  const SizedBox(height: 10),
                  _buildStatusCard('Online Challenge', AppConstants.catOnlineChallenge, _onlineRecord,
                      'Compete against a simulated opponent. USA Room and Foreign Room available.'),
                  const SizedBox(height: 10),
                  _buildStatusCard('WiFi Challenge', AppConstants.catWifiChallenge, _wifiRecord,
                      'Real-time 1v1 with a friend. Place bets, in-match chat, and real rankings.'),

                  const SizedBox(height: 28),
                  const Divider(),
                  const SizedBox(height: 20),

                  // ── Get code banner ──────────────────────────────────
                  _GetCodeBanner(onTap: _openStore),
                  const SizedBox(height: 24),

                  // ── Activation form ───────────────────────────────────
                  const Text(
                    'Enter Activation Code',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'One code can unlock Standard, Online Challenge, WiFi Challenge, or all three at once — depending on the code type you purchased.',
                    style: TextStyle(fontSize: 12, color: ActColors.midGray, height: 1.4),
                  ),
                  const SizedBox(height: 18),

                  // Code field
                  TextField(
                    controller: _codeCtrl,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 1.2),
                    decoration: InputDecoration(
                      labelText: 'Activation Code',
                      hintText: 'SJACTS-260A7K-92PL-A1',
                      prefixIcon: const Icon(Icons.vpn_key_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Profile fields
                  TextField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Full Name',
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email Address',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Phone Number',
                      prefixIcon: const Icon(Icons.phone_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Status message
                  if (_statusMsg != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: (_statusIsError ? ActColors.danger : ActColors.success).withOpacity(0.09),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: (_statusIsError ? ActColors.danger : ActColors.success).withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        _statusMsg!,
                        style: TextStyle(
                          color: _statusIsError ? ActColors.danger : ActColors.success,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),

                  // Submit button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: ActColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(height: 20, width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                          : const Text('Activate', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),


                ],
              ),
            ),
    );
  }

  Widget _buildStatusCard(String label, String category, ActivationRecord? record, String desc) {
    final active = record?.isFullyActive ?? false;
    final inGrace = record?.isInGrace ?? false;
    final expired = record?.isExpired ?? false;

    Color statusColor = ActColors.midGray;
    String statusText = 'Not activated';
    IconData statusIcon = Icons.lock_outline;

    if (active && !inGrace) {
      statusColor = ActColors.success;
      statusText = 'Active — expires ${_formatDate(record!.expiresAt)}';
      statusIcon = Icons.check_circle_outline;
    } else if (inGrace) {
      statusColor = ActColors.warning;
      statusText = 'Grace period — ends ${_formatDate(record!.graceEndsAt)}';
      statusIcon = Icons.timer_outlined;
    } else if (expired) {
      statusColor = ActColors.danger;
      statusText = 'Expired';
      statusIcon = Icons.cancel_outlined;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: statusColor.withOpacity(0.25)),
        borderRadius: BorderRadius.circular(10),
        color: statusColor.withOpacity(0.04),
      ),
      child: Row(
        children: [
          Icon(statusIcon, color: statusColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                Text(statusText, style: TextStyle(fontSize: 11, color: statusColor)),
                if (!active)
                  Text(desc, style: TextStyle(fontSize: 10, color: ActColors.midGray, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }
}

class _GetCodeBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _GetCodeBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [ActColors.primaryDark, ActColors.primary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: ActColors.primary.withOpacity(0.35),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.verified_outlined, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Get Activation Code',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
              SizedBox(height: 4),
              Text('Unlock all sections, challenges & tools.',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('Get Now',
              style: TextStyle(
                color: ActColors.primary,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              )),
          ),
        ]),
      ),
    );
  }
}
