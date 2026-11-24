abstract final class Routes {
  static const stores = '/stores';
  static String storePrices(int storeId) => '/stores/$storeId/prices';

  /// Price comparison of one product; opened from the search and from a store's prices.
  static String productPrices(int productId) => '/products/$productId/prices';

  /// Price history of one product in one store; opened from the comparison.
  static String priceHistory(int productId, int storeId) =>
      '/products/$productId/stores/$storeId/history';
  static const search = '/search';
  static const account = '/account';
  static const settings = '/account/settings';
  static const login = '/account/login';
  static const register = '/account/register';
  static const forgotPassword = '/account/forgot-password';
  static const resetPassword = '/account/reset-password';
}
