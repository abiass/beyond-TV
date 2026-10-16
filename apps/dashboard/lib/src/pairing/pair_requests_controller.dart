import 'dart:async';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../auth/auth_controller.dart';
import '../devices/devices_controller.dart';
import '../realtime/admin_events.dart';

/// TVs aguardando aprovação, mantidas em dia pelos eventos do
/// `WS /ws/admin`.
final pairRequestsProvider = AsyncNotifierProvider.autoDispose<
    PairRequestsController, List<PendingPairRequest>>(
  PairRequestsController.new,
);

class PairRequestsController extends AsyncNotifier<List<PendingPairRequest>> {
  /// De quanto em quanto tempo tira da lista os pedidos vencidos (o
  /// servidor não avisa quando um pedido vence).
  static const expiryCheck = Duration(seconds: 15);

  @override
  Future<List<PendingPairRequest>> build() async {
    final events = ref.watch(adminEventsProvider);
    final eventsSub = events.events.listen(_onEvent);
    final connectedSub = events.connected.where((c) => c).listen((_) {
      if (state.hasValue) unawaited(_reload());
    });
    final expiry = Timer.periodic(expiryCheck, (_) => _dropExpired());
    ref.onDispose(() {
      eventsSub.cancel();
      connectedSub.cancel();
      expiry.cancel();
    });
    return _open(await ref.read(apiClientProvider).listPairRequests());
  }

  Future<void> _reload() async {
    try {
      state = AsyncData(
        _open(await ref.read(apiClientProvider).listPairRequests()),
      );
    } on Object {
      // Mantém a lista; o próximo evento ou reconexão tenta de novo.
    }
  }

  static List<PendingPairRequest> _open(List<PendingPairRequest> list) {
    final now = clock.now();
    return [
      for (final r in list)
        if (r.expiresAt.isAfter(now)) r,
    ];
  }

  void _dropExpired() {
    final list = state.value;
    if (list == null) return;
    final open = _open(list);
    if (open.length != list.length) state = AsyncData(open);
  }

  void _onEvent(Envelope event) {
    final list = state.value;
    if (list == null) return;
    switch (event.type) {
      case MessageTypes.pairRequestCreated:
        final PendingPairRequest request;
        try {
          request = PendingPairRequest.fromJson(event.payload);
        } on ProtocolException {
          return;
        }
        state = AsyncData([
          for (final r in list)
            if (r.id != request.id) r,
          request,
        ]);
      case MessageTypes.pairRequestClosed:
        _remove(event.payload['id']);
    }
  }

  void _remove(Object? id) {
    final list = state.value;
    if (list == null || !list.any((r) => r.id == id)) return;
    state = AsyncData([
      for (final r in list)
        if (r.id != id) r,
    ]);
  }

  /// Aprova o pedido [id] e põe a TV na lista. Lança [ApiException] em caso
  /// de erro; se o pedido já não existe, ele também sai da lista.
  Future<DeviceSummary> approve(String id) async {
    try {
      final device = await ref.read(apiClientProvider).approvePairRequest(id);
      _remove(id);
      ref.read(devicesProvider.notifier).upsert(device);
      return device;
    } on ApiException catch (e) {
      if (e.status == 404) _remove(id);
      rethrow;
    }
  }

  /// Recusa o pedido [id]. Lança [ApiException] em caso de erro.
  Future<void> reject(String id) async {
    try {
      await ref.read(apiClientProvider).rejectPairRequest(id);
    } on ApiException catch (e) {
      if (e.status != 404) rethrow;
    }
    _remove(id);
  }
}
