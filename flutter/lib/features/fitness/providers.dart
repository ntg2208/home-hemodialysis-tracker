import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'fitness_api.dart';

final fitnessApiProvider =
    Provider<FitnessApi>((ref) => FitnessApi(ref.read(restClientProvider)));
