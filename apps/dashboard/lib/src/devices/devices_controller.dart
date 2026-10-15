import 'dart:async';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../realtime/admin_events.dart';

/// Lista de TVs, mantida em dia pelos eventos do `WS /ws/admin`.
final devicesProvider =
    AsyncNotifierProvider.autoDispose<DevicesController, List<DeviceSummary>>(
  DevicesController.new,
);

class DevicesController extends AsyncNotifier<List<DeviceSummary>> {
  @override
  Future<List<DeviceSummary>> build() async {
    final events = ref.watch(adminEventsProvider);
    final eventsSub = events.events.listen(_onEvent);
    final connectedSub = events.connected.where((c) => c).listen((_) {
      // A cada (re)conexão recarrega, para não perder eventos.
      if (state.hasValue) unawaited(_reload());
    });
    ref.onDispose(() {
      eventsSub.cancel();
      connectedSub.cancel();
    });
    return ref.read(apiClientProvider).listDevices();
  }

  Future<void> _reload() async {
    try {
      state = AsyncData(await ref.read(apiClientProvider).listDevices());
    } on Object {
      // Mantém a lista atual; o próximo evento ou reconexão tenta de novo.
    }
  }

  List<DeviceSummary>? get _current => state.value;

  void _onEvent(Envelope event) {
    final list = _current;
    if (list == null) return;
    final payload = event.payload;

    if (event.type == MessageTypes.devicePaired ||
        event.type == MessageTypes.deviceState) {
      final DeviceSummary device;
      try {
        device = DeviceSummary.fromJson(payload);
      } on ProtocolException {
        return;
      }
      final exists = list.any((d) => d.id == device.id);
      state = AsyncData(
        exists
            ? [for (final d in list) d.id == device.id ? device : d]
            : [device, ...list],
      );
      return;
    }

    final id = payload['deviceId'];
    if (id is! String) return;
    final known = list.any((d) => d.id == id);

    switch (event.type) {
      case MessageTypes.deviceRemoved:
        if (known) state = AsyncData([...list.where((d) => d.id != id)]);
      case MessageTypes.deviceOnline when known:
        _update(id, (d) => d.copyWith(online: true));
      case MessageTypes.deviceOffline when known:
        final seen = DateTime.tryParse('${payload['lastSeenAt']}');
        _update(id, (d) => d.copyWith(online: false, lastSeenAt: seen));
      case MessageTypes.deviceOnline || MessageTypes.deviceOffline:
        unawaited(_reload());
    }
  }

  void _update(String id, DeviceSummary Function(DeviceSummary) change) {
    state = AsyncData([
      for (final d in _current!) d.id == id ? change(d) : d,
    ]);
  }

  /// Renomeia a TV. Lança [ApiException] em caso de erro.
  Future<void> rename(String id, String name) async {
    final updated = await ref.read(apiClientProvider).renameDevice(id, name);
    state = AsyncData([
      for (final d in _current ?? const <DeviceSummary>[])
        d.id == id ? updated : d,
    ]);
  }

  /// Remove a TV. Lança [ApiException] em caso de erro.
  Future<void> remove(String id) async {
    await ref.read(apiClientProvider).removeDevice(id);
    state = AsyncData([
      for (final d in _current ?? const <DeviceSummary>[])
        if (d.id != id) d,
    ]);
  }

  /// Troca a TV pela versão devolvida pela API (ex.: após mudar o conteúdo).
  void replace(DeviceSummary device) {
    state = AsyncData([
      for (final d in _current ?? const <DeviceSummary>[])
        d.id == device.id ? device : d,
    ]);
  }
}
