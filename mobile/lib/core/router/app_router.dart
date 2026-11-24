import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/account/account_screen.dart';
import '../../features/add_product/add_product_models.dart';
import '../../features/add_product/add_product_screen.dart';
import '../../features/compare/compare_screen.dart';
import '../../features/compare/open_comparison.dart';
import '../../features/history/history_screen.dart';
import '../../features/history/open_history.dart';
import '../../features/submit_price/submit_price_models.dart';
import '../../features/submit_price/submit_price_screen.dart';
import '../../features/account/settings_screen.dart';
import '../../features/auth/forgot_password_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/auth/reset_password_screen.dart';
import '../../features/report/report_models.dart';
import '../../features/report/report_screen.dart';
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
        // Outside the tab shell, so the same screen can be opened from the
        // search tab and from the stores tab and always has a way back.
        GoRoute(
          path: '/products/:id/prices',
          redirect: (context, state) =>
              int.tryParse(state.pathParameters['id'] ?? '') == null ? Routes.search : null,
          builder: (context, state) {
            final hint = state.extra is ProductHint ? state.extra as ProductHint : null;
            return ProductCompareScreen(
              productId: int.parse(state.pathParameters['id']!),
              productName: hint?.name,
              volumeMl: hint?.volumeMl,
            );
          },
        ),
        GoRoute(
          path: Routes.signIn,
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: '/products/:productId/stores/:storeId/price',
          // Opened from a price row, which supplies what the form shows.
          redirect: (context, state) => state.extra is SubmitPriceTarget ? null : Routes.stores,
          builder: (context, state) =>
              SubmitPriceScreen(target: state.extra! as SubmitPriceTarget),
        ),
        GoRoute(
          path: '/prices/:priceEntryId/report',
          // Opened from a price row, which supplies what the form shows.
          redirect: (context, state) => state.extra is ReportTarget ? null : Routes.stores,
          builder: (context, state) => ReportScreen(target: state.extra! as ReportTarget),
          path: '/stores/:storeId/add-product',
          // Opened from a store's prices, which supplies the store the form shows.
          redirect: (context, state) => state.extra is AddProductTarget ? null : Routes.stores,
          builder: (context, state) =>
              AddProductScreen(target: state.extra! as AddProductTarget),
        ),
        GoRoute(
          path: '/products/:productId/stores/:storeId/history',
          redirect: (context, state) =>
              int.tryParse(state.pathParameters['productId'] ?? '') == null ||
                      int.tryParse(state.pathParameters['storeId'] ?? '') == null
                  ? Routes.search
                  : null,
          builder: (context, state) {
            final hint = state.extra is HistoryHint ? state.extra as HistoryHint : null;
            return PriceHistoryScreen(
              productId: int.parse(state.pathParameters['productId']!),
              storeId: int.parse(state.pathParameters['storeId']!),
              productName: hint?.productName,
              volumeMl: hint?.volumeMl,
              storeName: hint?.storeName,
            );
          },
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
