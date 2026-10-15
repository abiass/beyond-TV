import 'package:beyond_protocol/beyond_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/api_client.dart';
import '../auth/auth_controller.dart';
import '../router.dart';
import 'describe_audit.dart';

const _pageSize = 100;

/// Log de auditoria: quem mudou o quê, da ação mais nova para a mais antiga.
class AuditPage extends ConsumerStatefulWidget {
  const AuditPage({super.key});

  @override
  ConsumerState<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends ConsumerState<AuditPage> {
  final _entries = <AuditEntry>[];
  bool _loading = true;
  bool _hasMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref.read(apiClientProvider).listAudit(
            limit: _pageSize,
            before: _entries.isEmpty ? null : _entries.last.id,
          );
      if (!mounted) return;
      setState(() {
        _entries.addAll(page);
        _hasMore = page.length >= _pageSize;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => context.go(Routes.home)),
          title: const Text('Auditoria'),
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final entry in _entries) _AuditTile(entry),
                if (!_loading && _error == null && _entries.isEmpty)
                  const Text('Nenhuma ação registrada.'),
                if (_error case final error?) Text(error),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (_error != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton(
                      onPressed: _load,
                      child: const Text('Tentar de novo'),
                    ),
                  )
                else if (_hasMore)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      onPressed: _load,
                      child: const Text('Carregar mais'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
}

String _two(int n) => n.toString().padLeft(2, '0');

String _formatDateTime(DateTime utc) {
  final t = utc.toLocal();
  return '${_two(t.day)}/${_two(t.month)}/${t.year} '
      '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';
}

class _AuditTile extends StatelessWidget {
  const _AuditTile(this.entry);

  final AuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = entry.status >= 400;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(describeAudit(entry)),
      subtitle: Text(
        [
          _formatDateTime(entry.at),
          entry.adminName ?? '—',
          if (entry.ip != null) entry.ip!,
        ].join(' · '),
      ),
      trailing: Text(
        '${entry.status}',
        style: TextStyle(
          color: failed ? theme.colorScheme.error : null,
          fontWeight: failed ? FontWeight.bold : null,
        ),
      ),
    );
  }
}
