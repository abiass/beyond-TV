import 'json_fields.dart';

/// Duração mínima de um item de playlist, em segundos.
const minItemDurationSeconds = 5;

/// Duração máxima de um item de playlist (24 h), em segundos.
const maxItemDurationSeconds = 24 * 60 * 60;

/// Duração usada pela TV para site ou imagem sem duração numa playlist com
/// mais de um item.
const defaultItemDurationSeconds = 10;

/// Quantidade máxima de itens numa playlist.
const maxPlaylistItems = 200;

/// Indica se [seconds] é uma duração de item aceita (`null` também é).
bool isValidItemDuration(int? seconds) =>
    seconds == null ||
    (seconds >= minItemDurationSeconds && seconds <= maxItemDurationSeconds);

/// Referência curta a uma playlist, usada no [DeviceSummary].
final class PlaylistRef {
  const PlaylistRef({required this.id, required this.name});

  factory PlaylistRef.fromJson(Map<String, Object?> json) => PlaylistRef(
        id: json.field<String>('id'),
        name: json.field<String>('name'),
      );

  final String id;
  final String name;

  Map<String, Object?> toJson() => {'id': id, 'name': name};

  @override
  bool operator ==(Object other) =>
      other is PlaylistRef && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}
