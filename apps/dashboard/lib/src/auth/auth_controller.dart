import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';

/// Situação do administrador no dashboard.
sealed class AuthState {
  const AuthState();
}

/// O servidor ainda não tem administrador: mostra a configuração inicial.
final class NeedsSetup extends AuthState {
  const NeedsSetup();
}

/// Há administrador, mas ninguém logado neste navegador.
final class SignedOut extends AuthState {
  const SignedOut();
}

final class SignedIn extends AuthState {
  const SignedIn(this.username);

  final String username;
}

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

/// Estado de autenticação. Enquanto carrega, o dashboard mostra a tela
/// inicial; se o servidor não responder, mostra o erro com "Tentar de novo".
final authProvider = AsyncNotifierProvider<AuthController, AuthState>(
  AuthController.new,
  // O erro aparece na tela com um botão para tentar de novo.
  retry: (_, __) => null,
);

class AuthController extends AsyncNotifier<AuthState> {
  ApiClient get _api => ref.read(apiClientProvider);

  @override
  Future<AuthState> build() async {
    final api = ref.watch(apiClientProvider);
    if (!await api.isConfigured()) return const NeedsSetup();
    final username = await api.currentUser();
    return username == null ? const SignedOut() : SignedIn(username);
  }

  /// Cria o administrador. Lança [ApiException] em caso de erro.
  Future<void> setup(String username, String password) async {
    final name = await _api.setup(username: username, password: password);
    state = AsyncData(SignedIn(name));
  }

  /// Faz login. Lança [ApiException] em caso de erro.
  Future<void> login(String username, String password) async {
    final name = await _api.login(username: username, password: password);
    state = AsyncData(SignedIn(name));
  }

  Future<void> logout() async {
    await _api.logout();
    state = const AsyncData(SignedOut());
  }

  /// A sessão expirou no servidor (uma chamada respondeu 401).
  void sessionExpired() => state = const AsyncData(SignedOut());
}
