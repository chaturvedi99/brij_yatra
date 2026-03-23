/// Compile-time flags for release pipelines.
class AppFlags {
  /// When true: initialize Firebase, use Firebase Auth JWT for API calls, show prod sign-in.
  static const useFirebaseAuth = bool.fromEnvironment(
    'USE_FIREBASE_AUTH',
    defaultValue: false,
  );
}
