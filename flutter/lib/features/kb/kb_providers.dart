// flutter/lib/features/kb/kb_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../treatment/providers.dart';
import 'kb_store.dart';

final kbStoreProvider = Provider<KbStore>(
    (ref) => KbStore(ref.read(treatmentAuthProvider)));
