/// The signed-in account as returned by the server.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: (json['id'] as num).toInt(),
        email: json['email'] as String,
        displayName: json['displayName'] as String,
        role: json['role'] as String,
      );

  final int id;
  final String email;
  final String displayName;

  /// `Guest`, `User` or `Admin`. For display only; permissions are enforced by the server.
  final String role;
}

enum AuthStatus {
  /// Checking the stored token at app start.
  loading,
  signedOut,
  signedIn,
}

class AuthState {
  const AuthState._(this.status, this.user, this.sessionExpired);

  const AuthState.loading() : this._(AuthStatus.loading, null, false);

  /// [sessionExpired] is true when the server rejected the token of a signed-in
  /// user (not for an explicit sign-out).
  const AuthState.signedOut({bool sessionExpired = false})
      : this._(AuthStatus.signedOut, null, sessionExpired);

  const AuthState.signedIn(AuthUser user) : this._(AuthStatus.signedIn, user, false);

  final AuthStatus status;
  final AuthUser? user;
  final bool sessionExpired;

  bool get isSignedIn => status == AuthStatus.signedIn;
}
