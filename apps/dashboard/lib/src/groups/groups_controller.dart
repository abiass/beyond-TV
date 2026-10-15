import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/groups.dart';
import '../auth/auth_controller.dart';
import '../devices/devices_controller.dart';

/// Grupos de TVs, por nome.
final groupsProvider =
    AsyncNotifierProvider.autoDispose<GroupsController, List<Group>>(
  GroupsController.new,
);

class GroupsController extends AsyncNotifier<List<Group>> {
  @override
  Future<List<Group>> build() => ref.read(apiClientProvider).listGroups();

  List<Group> get _current => state.value ?? const [];

  static List<Group> _sorted(List<Group> list) => [...list]..sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );

  void _put(Group group) {
    final exists = _current.any((g) => g.id == group.id);
    state = AsyncData(
      _sorted(
        exists
            ? [for (final g in _current) g.id == group.id ? group : g]
            : [..._current, group],
      ),
    );
  }

  /// Cria o grupo. Lança `ApiException` em caso de erro.
  Future<Group> create(String name) async {
    final group = await ref.read(apiClientProvider).createGroup(name);
    _put(group);
    return group;
  }

  Future<void> rename(int id, String name) async =>
      _put(await ref.read(apiClientProvider).renameGroup(id, name));

  Future<void> delete(int id) async {
    await ref.read(apiClientProvider).deleteGroup(id);
    state = AsyncData([
      for (final g in _current)
        if (g.id != id) g,
    ]);
    // As TVs do grupo ficaram sem grupo.
    ref.invalidate(devicesProvider);
  }

  Future<void> setMembers(int id, List<String> deviceIds) async {
    _put(await ref.read(apiClientProvider).setGroupMembers(id, deviceIds));
    // Quem entrou ou saiu de um grupo muda de `groupId`; outros grupos
    // perdem membros.
    ref.invalidateSelf();
    ref.invalidate(devicesProvider);
  }

  /// Troca o conteúdo padrão do grupo pela versão devolvida pela API.
  void replace(Group group) => _put(group);
}
