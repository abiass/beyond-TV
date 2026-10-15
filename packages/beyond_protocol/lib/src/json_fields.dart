import 'protocol_exception.dart';

/// Leitura tipada de campos de um objeto JSON, com erro claro.
extension JsonFields on Map<String, Object?> {
  /// Campo obrigatório [key] do tipo [T].
  T field<T extends Object>(String key) {
    final value = this[key];
    if (value is! T) {
      throw ProtocolException('campo "$key" ausente ou inválido');
    }
    return value;
  }

  /// Campo opcional [key] do tipo [T]; `null` se ausente.
  T? optionalField<T extends Object>(String key) {
    final value = this[key];
    if (value == null) return null;
    if (value is! T) throw ProtocolException('campo "$key" inválido');
    return value;
  }

  /// Campo obrigatório [key] com uma data ISO 8601, convertida para UTC.
  DateTime dateField(String key) {
    final parsed = DateTime.tryParse(field<String>(key));
    if (parsed == null) {
      throw ProtocolException('campo "$key" não é uma data ISO 8601');
    }
    return parsed.toUtc();
  }
}
