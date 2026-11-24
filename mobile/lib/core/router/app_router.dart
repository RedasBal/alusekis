import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/account/account_screen.dart';
import '../../features/account/settings_screen.dart';
import '../../features/auth/forgot_password_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/auth/reset_password_screen.dart';
import '../../features/search/search_screen.dart';
import '../../features/shell/home_shell.dart';
import '../../features/stores/store_prices_screen.dart';
import '../../features/stores/stores_screen.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';
import 'routes.dart';

GoRouter buildRouter() => GoRouter(
      initialLocation: Routes.stores,
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              HomeShell(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: Routes.stores,
                  builder: (context, state) => const StoresScreen(),
                  routes: [
                    GoRoute(
                      path: ':id/prices',
                      redirect: (context, state) =>
                          int.tryParse(state.pathParameters['id'] ?? '') == null
                              ? Routes.stores
                              : null,
                      builder: (context, state) => StorePricesScreen(
                        storeId: int.parse(state.pathParameters['id']!),
                        storeName: state.extra as String?,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: Routes.search,
                  builder: (context, state) => const SearchScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: Routes.account,
                  builder: (context, state) => const AccountScreen(),
                  routes: [
                    GoRoute(
                      path: 'settings',
                      builder: (context, state) => const SettingsScreen(),
                    ),
                    GoRoute(
                      path: 'login',
                      builder: (context, state) => const LoginScreen(),
                    ),
                    GoRoute(
                      path: 'register',
                      builder: (context, state) => const RegisterScreen(),
                    ),
                    GoRoute(
                      path: 'forgot-password',
                      builder: (context, state) =>
                          const ForgotPasswordScreen(),
                    ),
                    GoRoute(
                      path: 'reset-password',
                      builder: (context, state) => const ResetPasswordScreen(),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );

final routerProvider = Provider<GoRouter>((ref) {
  final router = buildRouter();

  // The server rejected our token (401): the session is over, go to sign-in.
  ref.listen<AuthState>(authControllerProvider, (previous, next) {
    if (next.sessionExpired && !(previous?.sessionExpired ?? false)) {
      router.go(Routes.login);
    }
  });

  ref.onDispose(router.dispose);
  return router;
});
