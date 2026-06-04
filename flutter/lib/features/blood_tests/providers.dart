import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../app/providers.dart';
import '../../test_mode/synthetic_repos.dart';
import 'blood_tests_api.dart';
import 'bt_store.dart';

final bloodTestsApiProvider = Provider<BloodTestsApi>((ref) {
  if (ref.watch(testModeProvider)) return SyntheticBloodTestsApi();
  return BloodTestsApi(ref.read(restClientProvider));
});

final btStoreProvider = Provider<BtStore>((ref) {
  final box = Hive.box(cacheBoxName);
  if (ref.watch(testModeProvider)) return SyntheticBtStore(box);
  return BtStore(box);
});
