import 'file_picker.dart';

/// Fora do navegador não há seletor de arquivos.
FilePicker createFilePicker() => const _UnsupportedFilePicker();

class _UnsupportedFilePicker implements FilePicker {
  const _UnsupportedFilePicker();

  @override
  Future<PickedFile?> pick({required List<String> acceptedMimes}) async => null;
}
