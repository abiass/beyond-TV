import 'dart:async';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:flutter/material.dart';

import '../device/device_info_source.dart';
import '../remote/app_log.dart';
import '../server/server_address.dart';
import '../server/tv_api.dart';
import '../theme.dart';
import '../widgets/tv_button.dart';

/// Pareamento sem digitar nada: a TV pede e o administrador aprova no
/// painel, conferindo o código de 4 dígitos que aparece aqui.
///
/// Se o servidor não conhece esse fluxo (versão anterior à 1.1), chama
/// [onUseCode] para cair no código digitado.
class ApprovalPage extends StatefulWidget {
  const ApprovalPage({
    super.key,
    required this.server,
    required this.api,
    required this.deviceInfo,
    required this.onPaired,
    required this.onUseCode,
    required this.onChangeServer,
    this.pollInterval = pairRequestPollInterval,
    this.retryDelay = const Duration(seconds: 5),
  });

  final ServerAddress server;
  final TvApi api;
  final DeviceInfoSource deviceInfo;
  final ValueChanged<PairResponse> onPaired;

  /// Troca para o pareamento com código digitado.
  final VoidCallback onUseCode;
  final VoidCallback onChangeServer;

  final Duration pollInterval;

  /// Espera antes de tentar abrir o pedido de novo depois de uma falha.
  final Duration retryDelay;

  @override
  State<ApprovalPage> createState() => _ApprovalPageState();
}

enum _Phase { requesting, waiting, rejected }

class _ApprovalPageState extends State<ApprovalPage> {
  _Phase _phase = _Phase.requesting;
  PairRequestTicket? _ticket;
  String? _deviceName;
  String? _error;
  Timer? _timer;
  bool _polling = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    unawaited(_request());
  }

  @override
  void dispose() {
    _timer?.cancel();
    final ticket = _ticket;
    if (ticket != null && !_done) {
      // Saiu da tela sem parear: libera o pedido no painel.
      unawaited(
        widget.api.cancelApproval(widget.server, ticket).catchError((_) {}),
      );
    }
    super.dispose();
  }

  Future<void> _request() async {
    _timer?.cancel();
    if (_phase != _Phase.requesting || _ticket != null) {
      setState(() {
        _phase = _Phase.requesting;
        _ticket = null;
      });
    }
    try {
      final info = await widget.deviceInfo.read();
      final ticket = await widget.api.requestApproval(widget.server, info);
      if (!mounted) return;
      setState(() {
        _ticket = ticket;
        _deviceName = info.suggestedName;
        _phase = _Phase.waiting;
        _error = null;
      });
      _timer = Timer.periodic(widget.pollInterval, (_) => _poll());
    } on TvApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'not_found') {
        appLog('Servidor sem aprovação no painel; usando código digitado');
        widget.onUseCode();
        return;
      }
      setState(() => _error = e.message);
      _timer = Timer(widget.retryDelay, () => unawaited(_request()));
    }
  }

  Future<void> _poll() async {
    final ticket = _ticket;
    if (_polling || ticket == null) return;
    _polling = true;
    try {
      final result = await widget.api.pollApproval(widget.server, ticket);
      if (!mounted) return;
      if (_error != null) setState(() => _error = null);
      switch (result.status) {
        case PairRequestStatus.pending:
          break;
        case PairRequestStatus.approved:
          _timer?.cancel();
          _done = true;
          widget.onPaired(result.credentials!);
        case PairRequestStatus.rejected:
          _timer?.cancel();
          _ticket = null;
          setState(() => _phase = _Phase.rejected);
        case PairRequestStatus.expired:
          // Venceu sem ninguém aprovar: pede de novo, com outro código.
          unawaited(_request());
      }
    } on TvApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'not_found') {
        // O servidor esqueceu o pedido (ex.: reiniciou).
        unawaited(_request());
      } else {
        // Sem resposta: segue tentando no próximo intervalo.
        setState(() => _error = e.message);
      }
    } finally {
      _polling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final server = widget.server;
    final ticket = _ticket;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.tv, color: brandAccent, size: 32),
                          SizedBox(width: 12),
                          Text('Beyond TV', style: TextStyle(fontSize: 24)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text('Parear esta TV', style: textTheme.displaySmall),
                      const SizedBox(height: 8),
                      Text(
                        switch (_phase) {
                          _Phase.rejected => 'O pedido foi recusado no painel.',
                          _ =>
                            'No painel do PC, esta TV aparece em "Aguardando '
                                'aprovação". Confira o código e clique em '
                                'Aprovar.',
                        },
                        style: textTheme.titleMedium?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 120,
                        child: switch (_phase) {
                          _Phase.waiting when ticket != null => _ConfirmCode(
                              code: ticket.confirmCode,
                            ),
                          _Phase.requesting => const Align(
                              alignment: Alignment.centerLeft,
                              child: CircularProgressIndicator(),
                            ),
                          _ => const SizedBox.shrink(),
                        },
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 36,
                        child: _error != null
                            ? Text(
                                _error!,
                                style: TextStyle(
                                  color: colors.error,
                                  fontSize: 20,
                                ),
                              )
                            : _phase == _Phase.waiting
                                ? const Row(
                                    children: [
                                      SizedBox.square(
                                        dimension: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 3,
                                        ),
                                      ),
                                      SizedBox(width: 12),
                                      Text(
                                        'Aguardando aprovação…',
                                        style: TextStyle(fontSize: 20),
                                      ),
                                    ],
                                  )
                                : null,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        [
                          if (_deviceName != null) 'TV: $_deviceName',
                          'Servidor: ${server.name ?? server.host} · '
                              '${server.hostPort}',
                        ].join('   ·   '),
                        style: textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 48),
              SizedBox(
                width: 300,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_phase == _Phase.rejected) ...[
                      TvButton(
                        icon: Icons.refresh,
                        label: 'Pedir de novo',
                        autofocus: true,
                        onPressed: () => unawaited(_request()),
                      ),
                      const SizedBox(height: 16),
                    ],
                    TvButton(
                      icon: Icons.dialpad,
                      label: 'Digitar código',
                      subtitle: 'Gerado em "Adicionar TV"',
                      autofocus: _phase != _Phase.rejected,
                      onPressed: widget.onUseCode,
                    ),
                    const SizedBox(height: 16),
                    TvButton(
                      icon: Icons.swap_horiz,
                      label: 'Trocar servidor',
                      onPressed: widget.onChangeServer,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// O código de conferência em dígitos grandes.
class _ConfirmCode extends StatelessWidget {
  const _ConfirmCode({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Código de conferência: $code',
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final digit in code.split(''))
              Container(
                width: 84,
                height: 112,
                margin: const EdgeInsets.only(right: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: brandAccent, width: 3),
                ),
                child: Text(
                  digit,
                  style: const TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
