abstract final class Routes {
  static const stores = '/stores';
  static String storePrices(int storeId) => '/stores/$storeId/prices';

  /// Price comparison of one product; opened from the search and from a store's prices.
  static String productPrices(int productId) => '/products/$productId/prices';

  /// Sign-in outside the tabs, so any screen can send the user there and get
  /// them back afterwards (e.g. before submitting a price).
  static const signIn = '/login';

  /// "Atnaujinti kainą" for one product in one store.
  static String submitPrice(int productId, int storeId) =>
      '/products/$productId/stores/$storeId/price';

  /// "Pranešti apie klaidą" for one price entry.
  static String reportPrice(int priceEntryId) => '/prices/$priceEntryId/report';

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
