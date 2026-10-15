import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/api_client.dart';
import '../api/groups.dart';
import '../router.dart';
import '../widgets/name_dialog.dart';
import 'groups_controller.dart';

enum _Action { rename, delete }

/// Confirma e apaga o grupo [group]. Devolve `true` se apagou.
Future<bool> deleteGroupWithConfirm(
  BuildContext context,
  WidgetRef ref,
  Group group,
) async {
  final controller = ref.read(groupsProvider.notifier);
  final messenger = ScaffoldMessenger.of(context);
  final ok = await confirmDialog(
    context,
    title: 'Apagar grupo',
    message: '"${group.name}" será apagado. As TVs ficam sem grupo e os '
        'agendamentos do grupo são apagados.',
    confirmLabel: 'Apagar',
  );
  if (!ok) return false;
  try {
    await controller.delete(group.id);
    return true;
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  }
}

/// Renomeia o grupo [group] num diálogo.
Future<bool> renameGroupDialog(
  BuildContext context,
  WidgetRef ref,
  Group group,
) =>
    showNameDialog(
      context,
      title: 'Renomear grupo',
      confirmLabel: 'Salvar',
      initial: group.name,
      onSave: (name) =>
          ref.read(groupsProvider.notifier).rename(group.id, name),
    );

/// Lista de grupos: criar, renomear, apagar e abrir o detalhe.
class GroupsPage extends ConsumerWidget {
  const GroupsPage({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(groupsProvider.notifier);
    final router = GoRouter.of(context);
    int? createdId;
    final ok = await showNameDialog(
      context,
      title: 'Novo grupo',
      confirmLabel: 'Criar',
      onSave: (name) async => createdId = (await controller.create(name)).id,
    );
    if (ok && createdId != null) router.go(Routes.group(createdId!));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(groupsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go(Routes.home)),
        title: const Text('Grupos'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Novo grupo'),
      ),
      body: switch (groups) {
        AsyncData(:final value) when value.isEmpty => const Center(
            child: Text('Nenhum grupo ainda.'),
          ),
        AsyncData(:final value) => Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                itemCount: value.length,
                itemBuilder: (context, i) {
                  final g = value[i];
                  final count = g.deviceIds.length;
                  return Card(
                    child: ListTile(
                      onTap: () => context.go(Routes.group(g.id)),
                      leading: const Icon(Icons.workspaces_outline),
                      title: Text(
                        g.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        [
                          count == 1 ? '1 TV' : '$count TVs',
                          g.contentLabel ?? 'Sem conteúdo padrão',
                        ].join(' · '),
                      ),
                      trailing: PopupMenuButton<_Action>(
                        tooltip: 'Ações',
                        onSelected: (action) => switch (action) {
                          _Action.rename => renameGroupDialog(context, ref, g),
                          _Action.delete =>
                            deleteGroupWithConfirm(context, ref, g),
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: _Action.rename,
                            child: Text('Renomear'),
                          ),
                          PopupMenuItem(
                            value: _Action.delete,
                            child: Text('Apagar'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        AsyncError(:final error) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  error is ApiException
                      ? error.message
                      : 'Não foi possível carregar os grupos.',
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(groupsProvider),
                  child: const Text('Tentar de novo'),
                ),
              ],
            ),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
