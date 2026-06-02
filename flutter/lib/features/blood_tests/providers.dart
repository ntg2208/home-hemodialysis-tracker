import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../app/providers.dart';
import 'blood_tests_api.dart';
import 'bt_store.dart';

final bloodTestsApiProvider =
    Provider<BloodTestsApi>((ref) => BloodTestsApi(ref.read(restClientProvider)));

final btStoreProvider =
    Provider<BtStore>((_) => BtStore(Hive.box(cacheBoxName)));
