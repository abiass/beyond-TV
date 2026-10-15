import 'dart:convert';
import 'dart:io';

import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:path_provider/path_provider.dart';

/// Onde o último manifesto fica guardado, para a TV exibir o conteúdo
/// mesmo com o servidor fora do ar.
abstract interface class ManifestStore {
  /// Manifesto salvo, ou `null` se não há ou está corrompido.
  Future<ContentManifest?> load();

  Future<void> save(ContentManifest manifest);

  Future<void> clear();
}

/// Guarda o manifesto em `manifest.json` no diretório de suporte do app.
class FileManifestStore implements ManifestStore {
  FileManifestStore({Future<Directory> Function()? directory})
      : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  Future<File> _file([String name = 'manifest.json']) async =>
      File('${(await _directory()).path}/$name');

  @override
  Future<ContentManifest?> load() async {
    final file = await _file();
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(await file.readAsString());
      return ContentManifest.fromJson(json as Map<String, Object?>);
    } on Object {
      // Arquivo corrompido: apaga e segue sem manifesto.
      await clear();
      return null;
    }
  }

  @override
  Future<void> save(ContentManifest manifest) async {
    final tmp = await _file('manifest.json.tmp');
    await tmp.parent.create(recursive: true);
    await tmp.writeAsString(jsonEncode(manifest.toJson()), flush: true);
    await tmp.rename((await _file()).path);
  }

  @override
  Future<void> clear() async {
    for (final file in [await _file(), await _file('manifest.json.tmp')]) {
      if (await file.exists()) await file.delete();
    }
  }
}

/// Armazenamento em memória, para testes.
class MemoryManifestStore implements ManifestStore {
  MemoryManifestStore([this.saved]);

  ContentManifest? saved;

  @override
  Future<ContentManifest?> load() async => saved;

  @override
  Future<void> save(ContentManifest manifest) async => saved = manifest;

  @override
  Future<void> clear() async => saved = null;
}
