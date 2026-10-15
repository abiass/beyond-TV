import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../auth/auth_controller.dart';
import '../widgets/auth_card.dart';

/// Configuração inicial: cria o administrador do servidor.
///
/// Não existe senha padrão. Quem abre o dashboard pela primeira vez escolhe
/// o usuário e a senha.
class SetupPage extends ConsumerStatefulWidget {
  const SetupPage({super.key});

  @override
  ConsumerState<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends ConsumerState<SetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController(text: 'admin');
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authProvider.notifier)
          .setup(_username.text.trim(), _password.text);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthCard(
      title: 'Bem-vindo ao Beyond TV',
      subtitle: 'Crie o administrador deste servidor. Guarde a senha: ela é '
          'pedida sempre que alguém abrir o painel.',
      child: Form(
        key: _formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error case final error?) FormError(error),
              TextFormField(
                controller: _username,
                decoration: const InputDecoration(labelText: 'Usuário'),
                autofillHints: const [AutofillHints.newUsername],
                textInputAction: TextInputAction.next,
                validator: (value) =>
                    _usernamePattern.hasMatch(value?.trim() ?? '')
                        ? null
                        : 'Use de 3 a 32 letras sem acento, números, ponto, '
                            'hífen ou sublinhado.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _password,
                decoration: const InputDecoration(labelText: 'Senha'),
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.next,
                validator: (value) => (value?.length ?? 0) < 8
                    ? 'A senha deve ter pelo menos 8 caracteres.'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmation,
                decoration: const InputDecoration(labelText: 'Repita a senha'),
                obscureText: true,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                validator: (value) =>
                    value != _password.text ? 'As senhas não conferem.' : null,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(_busy ? 'Criando…' : 'Criar administrador'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mesma regra do servidor; ele valida de novo e tem a palavra final.
final _usernamePattern = RegExp(r'^[A-Za-z0-9._-]{3,32}$');
