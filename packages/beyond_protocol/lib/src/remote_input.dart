import 'json_fields.dart';
import 'protocol_exception.dart';

/// Códigos de `error` da TV para o `cmd.input`.
const remoteInputErrors = {'no_web_content', 'input_failed'};

/// Tamanho máximo do texto de um `cmd.input` do tipo `text`.
const maxRemoteTextLength = 500;

/// Teclas aceitas no `cmd.input` do tipo `key`.
abstract final class RemoteKeys {
  static const enter = 'enter';
  static const tab = 'tab';
  static const shiftTab = 'shiftTab';
  static const backspace = 'backspace';
  static const delete = 'delete';
  static const escape = 'escape';
  static const up = 'up';
  static const down = 'down';
  static const left = 'left';
  static const right = 'right';
  static const pageUp = 'pageUp';
  static const pageDown = 'pageDown';
  static const home = 'home';
  static const end = 'end';

  /// Volta a página anterior do site.
  static const back = 'back';

  static const all = {
    enter,
    tab,
    shiftTab,
    backspace,
    delete,
    escape,
    up,
    down,
    left,
    right,
    pageUp,
    pageDown,
    home,
    end,
    back,
  };
}

/// Tipo de entrada do controle remoto.
enum RemoteInputKind { tap, key, text, scroll }

/// Payload do `cmd.input`: o painel controla o site aberto na TV.
///
/// Coordenadas são frações da tela (0 a 1, a partir do canto superior
/// esquerdo), para não depender da resolução da captura.
final class RemoteInput {
  const RemoteInput._(
    this.kind, {
    this.x,
    this.y,
    this.key,
    this.text,
    this.dy,
  });

  /// Toque no ponto ([x], [y]).
  const RemoteInput.tap(double x, double y)
      : this._(RemoteInputKind.tap, x: x, y: y);

  /// Uma das [RemoteKeys].
  const RemoteInput.key(String key) : this._(RemoteInputKind.key, key: key);

  /// Texto digitado no campo com foco.
  const RemoteInput.text(String text)
      : this._(RemoteInputKind.text, text: text);

  /// Rolagem de [dy] telas (negativo sobe), no ponto ([x], [y]).
  const RemoteInput.scroll(double dy, {double x = 0.5, double y = 0.5})
      : this._(RemoteInputKind.scroll, dy: dy, x: x, y: y);

  /// Lança [ProtocolException] se o payload é inválido.
  factory RemoteInput.fromJson(Map<String, Object?> json) {
    final name = json.field<String>('kind');
    final kind =
        RemoteInputKind.values.where((k) => k.name == name).firstOrNull;
    double fraction(String field) {
      final value = json.field<num>(field).toDouble();
      if (value.isNaN || value < 0 || value > 1) {
        throw ProtocolException('campo "$field" fora de 0 a 1');
      }
      return value;
    }

    switch (kind) {
      case RemoteInputKind.tap:
        return RemoteInput.tap(fraction('x'), fraction('y'));
      case RemoteInputKind.key:
        final key = json.field<String>('key');
        if (!RemoteKeys.all.contains(key)) {
          throw ProtocolException('tecla desconhecida: "$key"');
        }
        return RemoteInput.key(key);
      case RemoteInputKind.text:
        final text = json.field<String>('text');
        if (text.isEmpty || text.length > maxRemoteTextLength) {
          throw const ProtocolException(
            'campo "text" vazio ou com mais de $maxRemoteTextLength caracteres',
          );
        }
        return RemoteInput.text(text);
      case RemoteInputKind.scroll:
        final dy = json.field<num>('dy').toDouble();
        if (dy.isNaN || dy < -5 || dy > 5) {
          throw const ProtocolException('campo "dy" fora de -5 a 5');
        }
        return RemoteInput.scroll(dy, x: fraction('x'), y: fraction('y'));
      case null:
        throw ProtocolException('campo "kind" inválido: "$name"');
    }
  }

  final RemoteInputKind kind;
  final double? x;
  final double? y;
  final String? key;
  final String? text;
  final double? dy;

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        if (x != null) 'x': x,
        if (y != null) 'y': y,
        if (key != null) 'key': key,
        if (text != null) 'text': text,
        if (dy != null) 'dy': dy,
      };

  /// Sem o texto: pode ser senha, e isto vai para logs.
  @override
  String toString() => switch (kind) {
        RemoteInputKind.text => 'RemoteInput(text, ${text!.length} chars)',
        _ => 'RemoteInput(${toJson()})',
      };
}
