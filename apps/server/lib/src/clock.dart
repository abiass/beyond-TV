/// Fonte do horário atual. Os testes trocam por um relógio controlado.
typedef Clock = DateTime Function();

/// Horário atual em UTC no formato gravado no banco (ISO 8601).
String isoUtc(DateTime time) => time.toUtc().toIso8601String();
