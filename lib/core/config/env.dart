abstract class Env {
  static const String apiKey = String.fromEnvironment('apiKey');

  /// OAuth *web* client ID of the Google Cloud project. Android needs it to
  /// sign in with Google.
  static const String googleServerClientId = String.fromEnvironment(
    'googleServerClientId',
  );
}
