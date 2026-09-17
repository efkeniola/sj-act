import '../utils/constants.dart';

/// One buyable (category, duration) option — e.g. "WiFi Challenge, 6
/// Months, $13.99". Built locally from AppConstants by default;
/// PlayCatalogService overwrites the prices with live server values when
/// it can reach /payments/play-catalog/, so Play Console price changes
/// never require an app update to be reflected correctly.
class PlayPlanOption {
  final String category;
  final String duration;
  final String productId;
  double priceUsd;

  PlayPlanOption({
    required this.category,
    required this.duration,
    required this.productId,
    required this.priceUsd,
  });

  String get categoryLabel => AppConstants.categoryLabels[category] ?? category;
  String get durationLabel => AppConstants.durationLabels[duration] ?? duration;
}

/// Everything about one category card on the plan-selection screen: its
/// label, tagline, feature bullets, and the list of duration options.
class PlayPlanCategory {
  final String category;
  final String tagline;
  final List<String> features;
  final List<PlayPlanOption> options;

  PlayPlanCategory({
    required this.category,
    required this.tagline,
    required this.features,
    required this.options,
  });

  String get label => AppConstants.categoryLabels[category] ?? category;
}

/// One line the buyer has picked — a category + the duration they chose
/// for it. Feeds both the order-summary screen and the sequence of Google
/// Play purchases that get launched to fulfil it.
class PlanSelection {
  final String category;
  final String duration;
  final double priceUsd;

  PlanSelection({required this.category, required this.duration, required this.priceUsd});

  String get productId => AppConstants.playProductId(category, duration);
  String get categoryLabel => AppConstants.categoryLabels[category] ?? category;
  String get durationLabel => AppConstants.durationLabels[duration] ?? duration;
}

/// Builds the default (offline-safe) catalog straight from AppConstants —
/// used immediately on screen open, then refined by PlayCatalogService.
List<PlayPlanCategory> buildDefaultCatalog() {
  const categories = [
    AppConstants.catStandard,
    AppConstants.catOnlineChallenge,
    AppConstants.catWifiChallenge,
  ];
  const taglines = {
    AppConstants.catStandard: 'The core ACT prep engine — everything you need to study.',
    AppConstants.catOnlineChallenge: 'Test yourself against a simulated opponent, any time.',
    AppConstants.catWifiChallenge: 'Go head-to-head with a friend, real-time, unlimited.',
  };

  return categories.map((cat) {
    final durations = AppConstants.catPlayDurations[cat] ?? const [];
    final options = durations.map((d) {
      final price = AppConstants.playPriceUsd[cat]?[d] ?? 0.0;
      return PlayPlanOption(
        category: cat,
        duration: d,
        productId: AppConstants.playProductId(cat, d),
        priceUsd: price,
      );
    }).toList();
    return PlayPlanCategory(
      category: cat,
      tagline: taglines[cat] ?? '',
      features: AppConstants.categoryFeatures[cat] ?? const [],
      options: options,
    );
  }).toList();
}
