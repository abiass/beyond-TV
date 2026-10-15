import 'dart:convert';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:flutter/services.dart';

/// Player que aceita o controle remoto do painel (só o de sites).
abstract interface class RemoteInputTarget {
  /// Executa [input] no site aberto. Lança [RemoteInputException] se não
  /// conseguiu.
  Future<void> input(RemoteInput input);
}

class RemoteInputException implements Exception {
  const RemoteInputException(this.message);

  final String message;

  @override
  String toString() => 'RemoteInputException: $message';
}

/// Roda JavaScript na página e devolve o resultado.
typedef JavaScriptRunner = Future<Object> Function(String script);

/// Leva o [RemoteInput] para a WebView nativa [webViewId].
///
/// Toque, teclas e rolagem viram eventos de toque e de teclado do Android,
/// como se alguém usasse a tela: o site recebe foco, clique e digitação de
/// verdade. O texto entra pelo `insertText` do navegador, que funciona com
/// acentos e dispara os eventos `input` que os sites esperam.
class RemoteInputDriver {
  RemoteInputDriver({
    required this.webViewId,
    required this.runJavaScript,
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'beyond_tv/remote_input';

  final int webViewId;
  final JavaScriptRunner runJavaScript;
  final MethodChannel _channel;

  Future<void> send(RemoteInput input) async {
    try {
      switch (input.kind) {
        case RemoteInputKind.tap:
          await _channel.invokeMethod<void>('tap', {
            'webViewId': webViewId,
            'x': input.x,
            'y': input.y,
          });
        case RemoteInputKind.key:
          await _channel.invokeMethod<void>('key', {
            'webViewId': webViewId,
            'key': input.key,
          });
        case RemoteInputKind.scroll:
          await _channel.invokeMethod<void>('scroll', {
            'webViewId': webViewId,
            'x': input.x,
            'y': input.y,
            'dy': input.dy,
          });
        case RemoteInputKind.text:
          await _insertText(input.text!);
      }
    } on PlatformException catch (e) {
      throw RemoteInputException(e.message ?? e.code);
    } on MissingPluginException {
      throw const RemoteInputException('Controle remoto indisponível.');
    }
  }

  Future<void> _insertText(String text) async {
    final result = await runJavaScript(insertTextScript(text));
    if ('$result' != 'true' && '$result' != '1') {
      throw const RemoteInputException(
        'Nenhum campo de texto selecionado. Clique no campo primeiro.',
      );
    }
  }

  /// Insere [text] no campo com foco. Devolve `true` se havia um campo.
  static String insertTextScript(String text) => '''
(function (t) {
  var e = document.activeElement;
  while (e && e.shadowRoot && e.shadowRoot.activeElement) {
    e = e.shadowRoot.activeElement;
  }
  if (!e || e === document.body) return false;
  if (document.execCommand && document.execCommand('insertText', false, t)) {
    return true;
  }
  if ('value' in e) {
    var s = e.selectionStart == null ? e.value.length : e.selectionStart;
    var f = e.selectionEnd == null ? s : e.selectionEnd;
    var setter = Object.getOwnPropertyDescriptor(
      Object.getPrototypeOf(e), 'value');
    var value = e.value.slice(0, s) + t + e.value.slice(f);
    if (setter && setter.set) { setter.set.call(e, value); } else { e.value = value; }
    e.dispatchEvent(new Event('input', { bubbles: true }));
    return true;
  }
  return false;
})(${jsonEncode(text)});
''';
}
