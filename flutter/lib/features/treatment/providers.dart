import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../api/hive_inventory_api.dart';
import '../../api/inventory_api.dart';
import '../../app/providers.dart';
import '../../flavor.dart';
import '../../test_mode/synthetic_repos.dart';
import 'hive_treatment_repo.dart';
import 'notification_prefs.dart';
import 'store.dart';
import 'treatment_auth.dart';
import 'treatment_repo.dart';

/// Hive box opened in main() before runApp.
const treatmentBoxName = 'treatment';

final treatmentStoreProvider =
    Provider<TreatmentStore>((_) => TreatmentStore(Hive.box(treatmentBoxName)));

final treatmentRepoProvider = Provider<TreatmentRepo>((ref) {
  if (kCommunity) return HiveTreatmentRepo();
  if (ref.watch(testModeProvider)) return SyntheticTreatmentRepo();
  return TreatmentRepo();
});

final treatmentAuthProvider = Provider<TreatmentAuth>((ref) => TreatmentAuth(
      ref.read(restClientProvider),
      ref.read(authControllerProvider),
    ));

final notificationPrefsStoreProvider = Provider<NotificationPrefsStore>(
  (_) => NotificationPrefsStore(Hive.box(treatmentBoxName)),
);

final notificationPrefsProvider =
    NotifierProvider<_NotificationPrefsNotifier, NotificationPrefs>(
        _NotificationPrefsNotifier.new);

class _NotificationPrefsNotifier extends Notifier<NotificationPrefs> {
  @override
  NotificationPrefs build() =>
      ref.read(notificationPrefsStoreProvider).read();

  Future<void> update(NotificationPrefs p) async {
    await ref.read(notificationPrefsStoreProvider).write(p);
    state = p;
  }
}

final inventoryApiProvider = Provider<InventoryApi>((ref) {
  if (kCommunity) return HiveInventoryApi();
  if (ref.watch(testModeProvider)) return SyntheticInventoryApi();
  return InventoryApi(ref.read(restClientProvider));
});
