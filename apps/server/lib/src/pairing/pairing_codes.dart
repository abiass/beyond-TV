import 'dart:math';

import 'package:beyond_protocol/beyond_protocol.dart';

import '../clock.dart';

/// Situação de um código de pareamento.
enum PairingCodeStatus { pending, paired, expired }

/// Código de pareamento emitido pelo dashboard.
class PairingCodeEntry {
  PairingCodeEntry(this.code, this.expiresAt);

  final String code;
  final DateTime expiresAt;

  /// TV que usou o código, depois do pareamento.
  String? deviceId;
}

/// Resultado de [PairingCodeStore.redeem].
enum RedeemResult { ok, invalid, expired }

/// Códigos de pareamento ativos.
///
/// Ficam **só em memória**: são de uso único, valem 10 minutos e não fazem
/// falta se o servidor reiniciar. Depois de vencer, cada código continua
/// consultável por mais um período igual, para o dashboard mostrar
/// "expirado" ou "pareado", e então é esquecido.
class PairingCodeStore {
  PairingCodeStore({
    Clock clock = DateTime.now,
    Random? random,
    this.ttl = pairingCodeTtl,
  }) : _clock = clock,
       _random = random ?? Random.secure();

  final Clock _clock;
  final Random _random;

  /// Validade de cada código.
  final Duration ttl;

  final _entries = <String, PairingCodeEntry>{};

  /// Gera um código novo, diferente dos que ainda estão guardados.
  PairingCode generate() {
    _purge();
    String code;
    do {
      code = String.fromCharCodes(
        List.generate(
          pairingCodeLength,
          (_) => pairingCodeAlphabet.codeUnitAt(
            _random.nextInt(pairingCodeAlphabet.length),
          ),
        ),
      );
    } while (_entries.containsKey(code));

    final expiresAt = _clock().toUtc().add(ttl);
    _entries[code] = PairingCodeEntry(code, expiresAt);
    return PairingCode(code: code, expiresAt: expiresAt);
  }

  /// Código [code] e sua situação, ou `null` se não existe (ou já foi
  /// esquecido).
  (PairingCodeEntry, PairingCodeStatus)? lookup(String code) {
    _purge();
    final entry = _entries[normalizePairingCode(code)];
    if (entry == null) return null;
    return (entry, _statusOf(entry));
  }

  /// Consome [code] para a TV [deviceId].
  ///
  /// Só funciona uma vez e dentro da validade. Um código já usado responde
  /// [RedeemResult.invalid], como se não existisse.
  RedeemResult redeem(String code, {required String deviceId}) {
    _purge();
    final entry = _entries[normalizePairingCode(code)];
    if (entry == null) return RedeemResult.invalid;
    switch (_statusOf(entry)) {
      case PairingCodeStatus.paired:
        return RedeemResult.invalid;
      case PairingCodeStatus.expired:
        return RedeemResult.expired;
      case PairingCodeStatus.pending:
        entry.deviceId = deviceId;
        return RedeemResult.ok;
    }
  }

  PairingCodeStatus _statusOf(PairingCodeEntry entry) {
    if (entry.deviceId != null) return PairingCodeStatus.paired;
    if (!_clock().isBefore(entry.expiresAt)) return PairingCodeStatus.expired;
    return PairingCodeStatus.pending;
  }

  void _purge() {
    final forgetBefore = _clock().subtract(ttl);
    _entries.removeWhere((_, entry) => entry.expiresAt.isBefore(forgetBefore));
  }
}
