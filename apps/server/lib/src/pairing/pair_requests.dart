import 'dart:math';

import 'package:beyond_protocol/beyond_protocol.dart';

import '../auth/tokens.dart';
import '../clock.dart';

/// Pedido de aprovação feito por uma TV.
class PairRequestEntry {
  PairRequestEntry({
    required this.id,
    required this.secretHash,
    required this.confirmCode,
    required this.deviceInfo,
    required this.ip,
    required this.createdAt,
    required this.expiresAt,
  });

  final String id;
  final String secretHash;
  final String confirmCode;
  final DeviceInfo deviceInfo;
  final String ip;
  final DateTime createdAt;
  final DateTime expiresAt;

  /// `pending`, `approved` ou `rejected`. Vencido é calculado pelo relógio.
  PairRequestStatus status = PairRequestStatus.pending;

  /// Credenciais da TV depois da aprovação, até a TV buscá-las.
  PairResponse? credentials;

  PendingPairRequest toPending() => PendingPairRequest(
    id: id,
    confirmCode: confirmCode,
    deviceInfo: deviceInfo,
    ip: ip,
    createdAt: createdAt,
    expiresAt: expiresAt,
  );
}

/// Muitos pedidos abertos ao mesmo tempo.
class TooManyPairRequests implements Exception {
  const TooManyPairRequests();
}

/// Pedidos de aprovação das TVs.
///
/// Ficam **só em memória**, como os códigos de pareamento: valem 10
/// minutos e um reinício do servidor só obriga a TV a pedir de novo. Cada
/// IP tem no máximo um pedido aberto; um pedido novo substitui o anterior.
class PairRequestStore {
  PairRequestStore({
    Clock clock = DateTime.now,
    Random? random,
    this.ttl = pairRequestTtl,
    this.maxPending = 20,
  }) : _clock = clock,
       _random = random ?? Random.secure();

  final Clock _clock;
  final Random _random;

  /// Validade de cada pedido.
  final Duration ttl;

  /// Limite de pedidos abertos, contra uma rede inundando o painel.
  final int maxPending;

  final _entries = <String, PairRequestEntry>{};

  /// Abre um pedido para a TV em [ip].
  ///
  /// Devolve o bilhete da TV (com o segredo, que não fica guardado) e o id
  /// do pedido anterior do mesmo IP, se houver, que deixa de existir.
  /// Lança [TooManyPairRequests] acima de [maxPending].
  (PairRequestTicket, PairRequestEntry, String? replaced) create(
    DeviceInfo deviceInfo,
    String ip,
  ) {
    _purge();
    final previous = _open().where((e) => e.ip == ip).firstOrNull;
    if (previous != null) _entries.remove(previous.id);
    if (_open().length >= maxPending) throw const TooManyPairRequests();

    final codesInUse = {for (final e in _open()) e.confirmCode};
    String code;
    do {
      code = '${_random.nextInt(10000)}'.padLeft(confirmCodeLength, '0');
    } while (codesInUse.contains(code));

    final now = _clock().toUtc();
    final secret = generateToken();
    final entry = PairRequestEntry(
      id: generateId(),
      secretHash: hashToken(secret),
      confirmCode: code,
      deviceInfo: deviceInfo,
      ip: ip,
      createdAt: now,
      expiresAt: now.add(ttl),
    );
    _entries[entry.id] = entry;
    final ticket = PairRequestTicket(
      id: entry.id,
      secret: secret,
      confirmCode: code,
      expiresAt: entry.expiresAt,
    );
    return (ticket, entry, previous?.id);
  }

  /// Pedidos aguardando aprovação, do mais antigo para o mais novo.
  List<PendingPairRequest> pending() {
    _purge();
    return [for (final e in _open()) e.toPending()]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  /// Pedido [id] aberto (pendente e na validade), para o painel decidir.
  PairRequestEntry? findOpen(String id) {
    _purge();
    final entry = _entries[id];
    return entry != null && _isOpen(entry) ? entry : null;
  }

  /// Pedido [id], se [secret] é o da TV que o abriu.
  PairRequestEntry? findForTv(String id, String secret) {
    _purge();
    final entry = _entries[id];
    if (entry == null || entry.secretHash != hashToken(secret)) return null;
    return entry;
  }

  /// Situação de [entry] para a TV. Entregar as credenciais de um pedido
  /// aprovado o apaga: a TV só as recebe uma vez.
  PairRequestPoll poll(PairRequestEntry entry) {
    switch (entry.status) {
      case PairRequestStatus.approved:
        _entries.remove(entry.id);
        return PairRequestPoll(
          PairRequestStatus.approved,
          credentials: entry.credentials,
        );
      case PairRequestStatus.rejected:
        return const PairRequestPoll(PairRequestStatus.rejected);
      case PairRequestStatus.pending || PairRequestStatus.expired:
        return PairRequestPoll(
          _isOpen(entry)
              ? PairRequestStatus.pending
              : PairRequestStatus.expired,
        );
    }
  }

  void approve(PairRequestEntry entry, PairResponse credentials) {
    entry
      ..status = PairRequestStatus.approved
      ..credentials = credentials;
  }

  void reject(PairRequestEntry entry) =>
      entry.status = PairRequestStatus.rejected;

  /// Apaga o pedido (a TV desistiu). Devolve se ele ainda estava aberto.
  bool remove(PairRequestEntry entry) {
    _entries.remove(entry.id);
    return _isOpen(entry);
  }

  bool _isOpen(PairRequestEntry entry) =>
      entry.status == PairRequestStatus.pending &&
      _clock().isBefore(entry.expiresAt);

  Iterable<PairRequestEntry> _open() => _entries.values.where(_isOpen);

  /// Esquece pedidos vencidos há mais de [ttl] (aprovados que a TV nunca
  /// buscou também: a TV já existe no painel e pode ser removida lá).
  void _purge() {
    final forgetBefore = _clock().subtract(ttl);
    _entries.removeWhere((_, e) => e.expiresAt.isBefore(forgetBefore));
  }
}
