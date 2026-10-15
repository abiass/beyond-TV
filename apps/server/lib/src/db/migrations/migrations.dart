import '../migrator.dart';
import 'm0001_init.dart';
import 'm0002_media.dart';
import 'm0003_playlists.dart';

/// Todas as migrações do esquema, em ordem.
///
/// Cada migração fica no próprio arquivo (`mNNNN_nome.dart`) como SQL
/// embutido, para que o executável compilado não dependa de arquivos externos.
const migrations = <Migration>[migration0001, migration0002, migration0003];
