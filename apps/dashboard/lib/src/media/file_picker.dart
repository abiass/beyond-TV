import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'file_picker_stub.dart'
    if (dart.library.js_interop) 'file_picker_web.dart';

/// Arquivo escolhido pelo usuário.
class PickedFile {
  const PickedFile({
    required this.name,
    required this.mime,
    required this.bytes,
  });

  final String name;

  /// MIME informado pelo navegador (pode vir vazio).
  final String mime;
  final Uint8List bytes;
}

/// Abre o seletor de arquivos do sistema.
abstract interface class FilePicker {
  /// O arquivo escolhido, ou `null` se o usuário cancelou.
  Future<PickedFile?> pick({required List<String> acceptedMimes});
}

/// No navegador usa o `<input type=file>`; os testes trocam por um falso.
final filePickerProvider = Provider<FilePicker>((ref) => createFilePicker());
