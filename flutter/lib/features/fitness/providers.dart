import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../test_mode/synthetic_repos.dart';
import 'fitness_api.dart';

final fitnessApiProvider = Provider<FitnessApi>((ref) {
  if (ref.watch(testModeProvider)) return SyntheticFitnessApi();
  return FitnessApi(ref.read(restClientProvider));
});
