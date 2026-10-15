import 'dart:async';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:flutter/foundation.dart';

/// Resolve a agenda do manifesto no relógio local da TV, sem servidor.
///
/// Expõe os itens "ativos agora" e notifica só quando eles mudam. Um timer
/// acorda no próximo início ou fim de faixa; outro reavalia a cada
/// [recheckEvery], para pegar ajuste do relógio da TV.
class ActiveContent extends ChangeNotifier {
  ActiveContent({
    DateTime Function()? now,
    this.recheckEvery = const Duration(minutes: 1),
  }) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Duration recheckEvery;

  ContentManifest _manifest = ContentManifest.empty;
  List<ContentItem> _items = const [];
  String? _ruleId;
  Timer? _boundary;
  Timer? _recheck;
  int _version = 0;
  bool _disposed = false;

  /// Itens que devem estar na tela agora.
  List<ContentItem> get items => _items;

  /// Muda sempre que [items] precisa ser reiniciado (manifesto novo ou troca
  /// de faixa).
  int get version => _version;

  /// Troca o manifesto: recalcula e reagenda os timers. Não notifica; quem
  /// chama já sabe que o manifesto mudou.
  void setManifest(ContentManifest manifest) {
    _manifest = manifest;
    _apply(manifest.activeScheduleAt(_now()));
    _version++;
    _schedule();
  }

  void _apply(ScheduleRule? rule) {
    _ruleId = rule?.id;
    _items = List.unmodifiable(rule?.items ?? _manifest.items);
  }

  void _schedule() {
    _boundary?.cancel();
    _recheck?.cancel();
    _boundary = null;
    _recheck = null;
    if (_disposed || _manifest.schedules.isEmpty) return;
    final now = _now();
    final next = _manifest.nextChangeAfter(now);
    if (next != null) {
      final wait = next.difference(now);
      _boundary = Timer(wait.isNegative ? Duration.zero : wait, _onBoundary);
    }
    _recheck = Timer.periodic(recheckEvery, (_) => _evaluate());
  }

  void _onBoundary() {
    _evaluate();
    _schedule();
  }

  void _evaluate() {
    if (_disposed) return;
    final rule = _manifest.activeScheduleAt(_now());
    if (rule?.id == _ruleId) return;
    _apply(rule);
    _version++;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _boundary?.cancel();
    _recheck?.cancel();
    super.dispose();
  }
}
