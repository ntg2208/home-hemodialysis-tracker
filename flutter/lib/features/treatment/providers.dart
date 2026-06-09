import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../api/inventory_api.dart';
import '../../app/providers.dart';
import '../../flavor.dart';
import '../../test_mode/synthetic_repos.dart';
import 'hive_treatment_repo.dart';
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

final inventoryApiProvider = Provider<InventoryApi>((ref) {
  if (ref.watch(testModeProvider)) return SyntheticInventoryApi();
  return InventoryApi(ref.read(restClientProvider));
});
