import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'file_picker.dart';

/// Seletor de arquivos do navegador.
FilePicker createFilePicker() => const _WebFilePicker();

class _WebFilePicker implements FilePicker {
  const _WebFilePicker();

  @override
  Future<PickedFile?> pick({required List<String> acceptedMimes}) {
    final done = Completer<PickedFile?>();
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = acceptedMimes.join(',');

    Future<void> read() async {
      final file = input.files?.item(0);
      if (file == null) {
        if (!done.isCompleted) done.complete(null);
        return;
      }
      try {
        final buffer = await file.arrayBuffer().toDart;
        done.complete(
          PickedFile(
            name: file.name,
            mime: file.type,
            bytes: buffer.toDart.asUint8List(),
          ),
        );
      } on Object catch (e, s) {
        done.completeError(e, s);
      }
    }

    input.onchange = ((web.Event _) => unawaited(read())).toJS;
    // Disparado quando o usuário fecha o seletor sem escolher nada.
    input.oncancel = ((web.Event _) {
      if (!done.isCompleted) done.complete(null);
    }).toJS;

    input.click();
    return done.future;
  }
}
