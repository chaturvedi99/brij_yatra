import 'package:shared_preferences/shared_preferences.dart';

class SessionStorage {
  SessionStorage(this._prefs);

  final SharedPreferences _prefs;

  static const _kToken = 'bearer_token';
  static const _kUserId = 'user_id';
  static const _kRole = 'user_role';

  String? get token => _prefs.getString(_kToken);
  String? get userId => _prefs.getString(_kUserId);
  String? get role => _prefs.getString(_kRole);

  Future<void> saveSession({
    required String token,
    required String userId,
    required String role,
  }) async {
    await _prefs.setString(_kToken, token);
    await _prefs.setString(_kUserId, userId);
    await _prefs.setString(_kRole, role);
  }

  Future<void> clear() async {
    await _prefs.remove(_kToken);
    await _prefs.remove(_kUserId);
    await _prefs.remove(_kRole);
  }
}
