import 'package:deepseek_function_call_example/core/config/env.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:injectable/injectable.dart';

/// Raised when the Google Calendar action needs the account to be linked.
class CalendarNotLinkedException implements Exception {
  const CalendarNotLinkedException();

  @override
  String toString() => 'Google Calendar is not linked.';
}

/// Links the app to a Google account and hands out Calendar access tokens.
@lazySingleton
class CalendarAuth {
  static const scopes = ['https://www.googleapis.com/auth/calendar.events'];

  final _signIn = GoogleSignIn.instance;
  Future<void>? _initialization;
  GoogleSignInAccount? _account;

  /// The linked account's email, or null when not linked.
  String? get email => _account?.email;

  bool get isLinked => _account != null;

  Future<void> _ensureInitialized() => _initialization ??= _signIn.initialize(
    serverClientId: Env.googleServerClientId.isEmpty
        ? null
        : Env.googleServerClientId,
  );

  /// Restores a previous link without showing any UI. Returns [isLinked].
  Future<bool> restore() async {
    await _ensureInitialized();
    final account = await _signIn.attemptLightweightAuthentication();
    if (account != null &&
        await account.authorizationClient.authorizationForScopes(scopes) !=
            null) {
      _account = account;
    }
    return isLinked;
  }

  /// Shows Google's sign-in and consent screens. Throws on cancel or failure.
  Future<void> link() async {
    await _ensureInitialized();
    final account = await _signIn.authenticate(scopeHint: scopes);
    await account.authorizationClient.authorizeScopes(scopes);
    _account = account;
  }

  Future<void> unlink() async {
    await _ensureInitialized();
    await _signIn.signOut();
    _account = null;
  }

  /// A valid access token, without prompting the user.
  Future<String> accessToken() async {
    final account = _account;
    if (account == null) throw const CalendarNotLinkedException();
    final authorization = await account.authorizationClient
        .authorizationForScopes(scopes);
    if (authorization == null) throw const CalendarNotLinkedException();
    return authorization.accessToken;
  }
}
