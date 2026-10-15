import 'dart:async';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:flutter/foundation.dart';

/// Item em exibição. [generation] muda quando o mesmo item recomeça.
final class RotationEntry {
  const RotationEntry(this.item, this.index, this.generation);

  final ContentItem item;
  final int index;
  final int generation;

  /// Identifica a "exibição" para o `AnimatedSwitcher`.
  String get key => '$index/${item.mediaId}/$generation';
}

/// Decide qual item da playlist está na tela e quando passa ao próximo.
///
/// Só lógica: quem desenha é a página. Itens sem arquivo pronto são pulados.
class PlaylistRotation extends ChangeNotifier {
  PlaylistRotation({required this.isReady});

  /// Diz se o item já pode ser exibido (site, ou arquivo em cache).
  final bool Function(ContentItem item) isReady;

  List<ContentItem> _items = const [];
  RotationEntry? _current;
  Timer? _timer;
  int _generation = 0;
  bool _disposed = false;

  /// Item em exibição; `null` se nenhum está pronto.
  RotationEntry? get current => _current;

  /// Troca a lista (manifesto novo) e recomeça do índice 0.
  void setItems(List<ContentItem> items) {
    _items = List.unmodifiable(items);
    _current = null;
    start();
  }

  /// Começa pelo primeiro item pronto.
  void start() {
    _timer?.cancel();
    final index = _nextReady(-1);
    _show(index);
  }

  /// Um arquivo ficou pronto (ou deixou de estar): se nada estava na tela,
  /// começa; senão só reavalia o tempo do item atual.
  void readinessChanged() {
    if (_current == null) {
      start();
    } else {
      _arm();
    }
  }

  /// Passa ao próximo item pronto.
  void next() {
    final current = _current;
    if (current == null) return;
    final index = _nextReady(current.index);
    if (index == current.index && current.item.kind != MediaKinds.video) {
      // Só ele está pronto: não precisa trocar (nem piscar).
      _arm();
      return;
    }
    _show(index, sameItemAgain: index == current.index);
  }

  /// O vídeo em exibição terminou.
  void onVideoCompleted() {
    if (_current?.item.kind == MediaKinds.video) next();
  }

  /// Recomeça o item atual (por exemplo, no `cmd.reload`).
  void restartCurrent() {
    final current = _current;
    if (current == null) return;
    _show(current.index, sameItemAgain: true);
  }

  // Primeiro índice pronto depois de [from], dando a volta; pode ser o próprio.
  int? _nextReady(int from) {
    for (var step = 1; step <= _items.length; step++) {
      final index = (from + step) % _items.length;
      if (isReady(_items[index])) return index;
    }
    return null;
  }

  void _show(int? index, {bool sameItemAgain = false}) {
    if (index == null) {
      _timer?.cancel();
      _current = null;
    } else {
      if (sameItemAgain) _generation++;
      _current = RotationEntry(_items[index], index, _generation);
      _arm();
    }
    if (!_disposed) notifyListeners();
  }

  void _arm() {
    _timer?.cancel();
    final item = _current?.item;
    if (item == null) return;
    var seconds = item.durationSeconds;
    if (seconds == null) {
      // Vídeo sem duração toca até o fim; o resto para se estiver sozinho.
      if (item.kind == MediaKinds.video) return;
      final readyCount = _items.where(isReady).length;
      if (readyCount <= 1) return;
      seconds = defaultItemDurationSeconds;
    }
    _timer = Timer(Duration(seconds: seconds), next);
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
