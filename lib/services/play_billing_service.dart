import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'api_service.dart';
import 'device_service.dart';
import '../models/play_plan_models.dart';

/// Wraps Google Play Billing for ACT's in-app checkout.
///
/// IMPORTANT PLATFORM LIMIT — read before changing this file:
/// Google Play Billing has no "cart" concept. A single purchase flow is
/// always for ONE product. There is no way to charge one card once for
/// "Standard 1 Year + WiFi Challenge 6 Months + Online Challenge 3 Months"
/// in a single Play transaction — Play itself would bill each
/// subscription separately even if our own UI presented them together.
///
/// So when someone picks several categories at once (fully supported —
/// see ActPlayCheckoutScreen), this service delivers the closest possible
/// thing to "pay once": ONE tap on "Pay with Google Play" starts a QUEUE
/// that walks through each selected product's own Play purchase sheet
/// automatically, one after another, with no extra taps from the person
/// in between. It is not literally one charge — Play issues one receipt
/// per subscription — but it is one continuous checkout experience from
/// the buyer's point of view, and the order-summary screen shows the
/// combined total up front so there's no surprise.
///
/// Flow per item in the queue:
///  1. buyMany() starts a Play purchase for that item's product id.
///  2. Google Play shows its own native payment sheet.
///  3. On success, purchaseStream fires a PurchaseDetails with a
///     verificationData.serverVerificationData (the purchase token).
///  4. We POST that token to /payments/verify-play/, which calls the
///     Google Play Developer API server-side to confirm it's real, then
///     mints an ActivationCode (see act/payment_adapter.py). The client
///     NEVER decides success on its own — see the security note there.
///  5. We call completePurchase() so Play doesn't refund/void the order.
///  6. The queue automatically starts the next item, if any.
///
/// If an item in the middle of the queue fails or is cancelled, whatever
/// already succeeded stays fully paid-for and activated — the events
/// stream reports exactly which items succeeded/failed so the checkout
/// screen can show a clear per-item result instead of one all-or-nothing
/// outcome.
class PlayBillingService {
  static final PlayBillingService _i = PlayBillingService._();
  factory PlayBillingService() => _i;
  PlayBillingService._();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  final _statusController = StreamController<PlayQueueEvent>.broadcast();
  Stream<PlayQueueEvent> get events => _statusController.stream;

  bool _pendingRegistered = false;

  String _name = '';
  String _email = '';
  String _phone = '';
  List<PlanSelection> _queue = [];
  int _queueIndex = 0;
  final List<PlayQueueResult> _results = [];

  bool get _supportsPlayBilling => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> get isAvailable async {
    if (!_supportsPlayBilling) return false;
    try {
      return await _iap.isAvailable();
    } catch (_) {
      return false;
    }
  }

  void init() {
    if (!_supportsPlayBilling || _pendingRegistered) return;
    _pendingRegistered = true;
    _sub = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: () => _sub?.cancel(),
      onError: (e) => _statusController.add(PlayQueueEvent.error('Billing stream error: $e')),
    );
  }

  void dispose() {
    _sub?.cancel();
    _pendingRegistered = false;
  }

  Future<ProductDetailsResponse> queryProducts(Set<String> productIds) {
    if (!_supportsPlayBilling) {
      return Future.value(ProductDetailsResponse(productDetails: const [], notFoundIDs: productIds.toList()));
    }
    return _iap.queryProductDetails(productIds);
  }

  /// Starts a "pay once" checkout for one or more [selections]. Buyer
  /// details are collected first in the UI (ActPlayCheckoutScreen) and
  /// passed in here once for the whole queue.
  Future<void> buyMany({
    required List<PlanSelection> selections,
    required String name,
    required String email,
    required String phone,
  }) async {
    if (!_supportsPlayBilling) {
      _statusController.add(PlayQueueEvent.error('Google Play Billing is only available on Android.'));
      return;
    }
    if (selections.isEmpty) return;

    _name = name;
    _email = email;
    _phone = phone;
    _queue = List.of(selections);
    _queueIndex = 0;
    _results.clear();

    final productIds = _queue.map((s) => s.productId).toSet();
    final response = await queryProducts(productIds);
    if (response.productDetails.isEmpty) {
      _statusController.add(PlayQueueEvent.error(
          'These plans are not available on the Play Store right now. Please try again shortly or contact support.'));
      return;
    }
    _productsById = {for (final p in response.productDetails) p.id: p};

    await _launchCurrent();
  }

  Map<String, ProductDetails> _productsById = {};

  Future<void> _launchCurrent() async {
    if (_queueIndex >= _queue.length) {
      _statusController.add(PlayQueueEvent.allDone(List.unmodifiable(_results)));
      return;
    }
    final selection = _queue[_queueIndex];
    final product = _productsById[selection.productId];
    if (product == null) {
      _results.add(PlayQueueResult(selection: selection, success: false, message: 'Plan not found on Play Store.'));
      _statusController.add(PlayQueueEvent.itemFailed(selection, 'Plan not found on Play Store.'));
      _queueIndex++;
      await _launchCurrent();
      return;
    }

    _statusController.add(PlayQueueEvent.itemStarted(selection, _queueIndex + 1, _queue.length));

    PurchaseParam param;
    if (product is GooglePlayProductDetails && product.offerToken != null) {
      param = GooglePlayPurchaseParam(productDetails: product, offerToken: product.offerToken);
    } else {
      param = PurchaseParam(productDetails: product);
    }
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      final selection = _queue.isNotEmpty && _queueIndex < _queue.length ? _queue[_queueIndex] : null;

      switch (p.status) {
        case PurchaseStatus.pending:
          _statusController.add(PlayQueueEvent.pendingItem(selection));
          break;

        case PurchaseStatus.error:
          final msg = p.error?.message ?? '';
          final code = p.error?.code ?? '';
          final normalized = '$msg $code'.toLowerCase().replaceAll('_', ' ');
          final alreadyOwned = normalized.contains('already own');
          if (p.pendingCompletePurchase) await _iap.completePurchase(p);

          if (alreadyOwned) {
            _statusController.add(PlayQueueEvent.recovering(selection));
            await restore();
          } else if (selection != null) {
            _results.add(PlayQueueResult(selection: selection, success: false, message: msg.isEmpty ? 'Purchase failed.' : msg));
            _statusController.add(PlayQueueEvent.itemFailed(selection, msg.isEmpty ? 'Purchase failed.' : msg));
            _queueIndex++;
            await _launchCurrent();
          }
          break;

        case PurchaseStatus.canceled:
          if (p.pendingCompletePurchase) await _iap.completePurchase(p);
          if (selection != null) {
            _results.add(PlayQueueResult(selection: selection, success: false, message: 'Cancelled.'));
            _statusController.add(PlayQueueEvent.itemCancelled(selection));
            _queueIndex++;
            await _launchCurrent();
          }
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verifyAndAdvance(p, selection);
          break;
      }
    }
  }

  Future<void> _verifyAndAdvance(PurchaseDetails p, PlanSelection? selection) async {
    final token = p.verificationData.serverVerificationData;
    final deviceId = await DeviceService.getDeviceId();

    final resp = await ApiService.post('/payments/verify-play/', {
      'product_id': p.productID,
      'purchase_token': token,
      'device_id': deviceId,
      'full_name': _name,
      'email': _email,
      'phone': _phone,
    });

    if (p.pendingCompletePurchase) {
      await _iap.completePurchase(p);
    }

    final matched = selection ?? _queue.firstWhere(
      (s) => s.productId == p.productID,
      orElse: () => PlanSelection(category: '', duration: '', priceUsd: 0),
    );

    if (!resp.success || resp.data?['code'] == null) {
      final message = resp.errorMessage ?? 'Could not verify purchase.';
      _results.add(PlayQueueResult(selection: matched, success: false, message: message));
      _statusController.add(PlayQueueEvent.itemFailed(matched, message));
    } else {
      final code = resp.data!['code'] as String;
      _results.add(PlayQueueResult(selection: matched, success: true, code: code));
      _statusController.add(PlayQueueEvent.itemSucceeded(matched, code));
    }

    _queueIndex++;
    await _launchCurrent();
  }

  Future<void> restore() async {
    if (!_supportsPlayBilling) return;
    await _iap.restorePurchases();
  }
}

class PlayQueueResult {
  final PlanSelection selection;
  final bool success;
  final String? code;
  final String? message;
  PlayQueueResult({required this.selection, required this.success, this.code, this.message});
}

enum PlayQueuePhase {
  itemStarted,
  itemPending,
  itemSucceeded,
  itemFailed,
  itemCancelled,
  recovering,
  allDone,
  error,
}

class PlayQueueEvent {
  final PlayQueuePhase phase;
  final PlanSelection? selection;
  final int? position;
  final int? total;
  final String? code;
  final String? message;
  final List<PlayQueueResult>? results;

  PlayQueueEvent._(this.phase, {this.selection, this.position, this.total, this.code, this.message, this.results});

  factory PlayQueueEvent.itemStarted(PlanSelection s, int position, int total) =>
      PlayQueueEvent._(PlayQueuePhase.itemStarted, selection: s, position: position, total: total);
  factory PlayQueueEvent.pendingItem(PlanSelection? s) => PlayQueueEvent._(PlayQueuePhase.itemPending, selection: s);
  factory PlayQueueEvent.itemSucceeded(PlanSelection s, String code) =>
      PlayQueueEvent._(PlayQueuePhase.itemSucceeded, selection: s, code: code);
  factory PlayQueueEvent.itemFailed(PlanSelection s, String message) =>
      PlayQueueEvent._(PlayQueuePhase.itemFailed, selection: s, message: message);
  factory PlayQueueEvent.itemCancelled(PlanSelection s) => PlayQueueEvent._(PlayQueuePhase.itemCancelled, selection: s);
  factory PlayQueueEvent.recovering(PlanSelection? s) =>
      PlayQueueEvent._(PlayQueuePhase.recovering, selection: s, message: 'Recovering your existing purchase…');
  factory PlayQueueEvent.allDone(List<PlayQueueResult> results) => PlayQueueEvent._(PlayQueuePhase.allDone, results: results);
  factory PlayQueueEvent.error(String message) => PlayQueueEvent._(PlayQueuePhase.error, message: message);
}
