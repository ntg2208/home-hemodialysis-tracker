import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../api/rest_client.dart';
import '../../app/providers.dart';
import '../../flavor.dart';
import '../../test_mode/synthetic_repos.dart';
import 'blood_tests_api.dart';
import 'bt_store.dart';
import 'hive_bt_store.dart';
import 'models.dart';

final bloodTestsApiProvider = Provider<BloodTestsApi>((ref) {
  if (kCommunity) return _NoopBloodTestsApi();
  if (ref.watch(testModeProvider)) return SyntheticBloodTestsApi();
  return BloodTestsApi(ref.read(restClientProvider));
});

final btStoreProvider = Provider<BtStore>((ref) {
  if (kCommunity) return HiveBtStore(Hive.box(communityBtBox));
  final box = Hive.box(cacheBoxName);
  if (ref.watch(testModeProvider)) return SyntheticBtStore(box);
  return BtStore(box);
});

class _NoopBloodTestsApi extends BloodTestsApi {
  _NoopBloodTestsApi() : super(RestClient(mainKey: () => ''));
  @override
  Future<List<BloodTestRow>> fetchRange({String? from, String? to}) async => [];
}
