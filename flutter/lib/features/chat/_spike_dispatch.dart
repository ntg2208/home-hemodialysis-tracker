import 'package:flutter_riverpod/flutter_riverpod.dart';

class _SpikeNavNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setRoute(String? route) {
    state = route;
  }
}

final spikeNavigationProvider =
    NotifierProvider<_SpikeNavNotifier, String?>(_SpikeNavNotifier.new);
