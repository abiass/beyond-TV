import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../auth/auth_controller.dart';
import '../theme.dart';

/// Tela exibida enquanto o dashboard consulta o servidor, ou quando ele não
/// responde.
class StartupPage extends ConsumerWidget {
  const StartupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.tv, size: 64, color: brandAccent),
              const SizedBox(height: 16),
              Text('Beyond TV', style: textTheme.headlineMedium),
              const SizedBox(height: 24),
              if (auth case AsyncError(:final error)) ...[
                Text(
                  error is ApiException
                      ? error.message
                      : 'Não foi possível carregar o painel.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(authProvider),
                  child: const Text('Tentar de novo'),
                ),
              ] else
                const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
