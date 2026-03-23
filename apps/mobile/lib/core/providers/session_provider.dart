import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_flags.dart';
import '../storage/session_storage.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw StateError('SharedPreferences must be overridden in main()');
});

final sessionStorageProvider = Provider<SessionStorage>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SessionStorage(prefs);
});

class SessionState {
  const SessionState({
    this.token,
    this.userId,
    this.role,
  });

  final String? token;
  final String? userId;
  final String? role;

  bool get isLoggedIn {
    if (AppFlags.useFirebaseAuth) {
      try {
        return FirebaseAuth.instance.currentUser != null &&
            userId != null &&
            userId!.isNotEmpty;
      } catch (_) {
        // Test environments may not initialize Firebase.
        return false;
      }
    }
    return token != null && token!.isNotEmpty;
  }
  bool get isGuide => role == 'guide';
  bool get isAdmin => role == 'admin';
  bool get isTraveler => role == null || role == 'traveler';
}

class SessionNotifier extends Notifier<SessionState> {
  @override
  SessionState build() {
    final storage = ref.watch(sessionStorageProvider);
    return SessionState(
      token: storage.token,
      userId: storage.userId,
      role: storage.role,
    );
  }

  Future<void> setSession({
    required String token,
    required String userId,
    required String role,
  }) async {
    final storage = ref.read(sessionStorageProvider);
    await storage.saveSession(token: token, userId: userId, role: role);
    state = SessionState(token: token, userId: userId, role: role);
  }

  Future<void> signOut() async {
    if (AppFlags.useFirebaseAuth) {
      await FirebaseAuth.instance.signOut();
    }
    final storage = ref.read(sessionStorageProvider);
    await storage.clear();
    state = const SessionState();
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(
  SessionNotifier.new,
);
