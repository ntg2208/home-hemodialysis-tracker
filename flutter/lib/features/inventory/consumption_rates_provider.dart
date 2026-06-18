import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../app/providers.dart' show cacheBoxName;
import 'rate_overrides.dart';

const _supplyRatesKey = 'supply_rates';

final consumptionRatesProvider =
    NotifierProvider<ConsumptionRatesNotifier, Map<String, RateOverride>>(
        ConsumptionRatesNotifier.new);

class ConsumptionRatesNotifier extends Notifier<Map<String, RateOverride>> {
  @override
  Map<String, RateOverride> build() {
    final raw = Hive.box(cacheBoxName).get(_supplyRatesKey) as Map? ?? {};
    return {
      for (final e in raw.entries)
        e.key as String: RateOverride.fromJson(e.value as Map),
    };
  }

  Future<void> save(Map<String, RateOverride> overrides) async {
    await Hive.box(cacheBoxName).put(
      _supplyRatesKey,
      {for (final e in overrides.entries) e.key: e.value.toJson()},
    );
    state = Map.unmodifiable(overrides);
  }

  Future<void> reset() async {
    await Hive.box(cacheBoxName).delete(_supplyRatesKey);
    state = const {};
  }
}
