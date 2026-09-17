import '../models/play_plan_models.dart';
import 'api_service.dart';

/// Fetches GET /payments/play-catalog/ (act/payments_views.py's
/// `play_catalog` view) and merges live prices/features into the local
/// default catalog (built from AppConstants). If the request fails, the
/// local defaults are used as-is.
class PlayCatalogService {
  static Future<List<PlayPlanCategory>> fetchCatalog() async {
    final local = buildDefaultCatalog();
    try {
      final result = await ApiService.get('/payments/play-catalog/');
      if (!result.success || result.data == null) return local;

      final plans = (result.data!['plans'] as List?) ?? const [];
      final byCategory = {for (final p in plans) (p as Map)['category'] as String: p};

      for (final cat in local) {
        final remote = byCategory[cat.category];
        if (remote == null) continue;
        final options = (remote['options'] as List?) ?? const [];
        final byDuration = {for (final o in options) (o as Map)['duration'] as String: o};
        for (final opt in cat.options) {
          final remoteOpt = byDuration[opt.duration];
          final price = remoteOpt?['play_price_usd'];
          if (price is num) opt.priceUsd = price.toDouble();
        }
      }
      return local;
    } catch (_) {
      return local;
    }
  }
}
