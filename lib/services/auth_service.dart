import 'dart:convert';
import 'package:amazon_cognito_identity_dart_2/cognito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import '../models/user.dart';

class _SharedPrefsStorage extends CognitoStorage {
  SharedPreferences? _prefs;

  Future<SharedPreferences> get _p async => _prefs ??= await SharedPreferences.getInstance();

  @override
  Future setItem(String key, value) async {
    final p = await _p;
    await p.setString(key, json.encode(value));
    return value;
  }

  @override
  Future getItem(String key) async {
    final p = await _p;
    final v = p.getString(key);
    return v != null ? json.decode(v) : null;
  }

  @override
  Future removeItem(String key) async {
    final p = await _p;
    await p.remove(key);
  }

  @override
  Future<void> clear() async {
    final p = await _p;
    final keys = p.getKeys().where((k) => k.startsWith('CognitoIdentityServiceProvider'));
    for (final k in keys) { await p.remove(k); }
  }
}

class AuthService {
  late final CognitoUserPool _pool;
  late final _SharedPrefsStorage _storage;
  CognitoUser? _cognitoUser;
  CognitoUserSession? _session;
  User? _user;

  AuthService() {
    _storage = _SharedPrefsStorage();
    _pool = CognitoUserPool(
      ApiConstants.cognitoUserPoolId,
      ApiConstants.cognitoClientId,
      storage: _storage,
    );
  }

  User? get user => _user;
  bool get isAuthenticated => _session?.isValid() ?? false;

  Future<bool> signIn(String email, String password, {bool rememberMe = true}) async {
    _cognitoUser = CognitoUser(email, _pool, storage: _storage);
    try {
      _session = await _cognitoUser!.authenticateUser(
        AuthenticationDetails(username: email, password: password),
      );
      if (_session == null || !_session!.isValid()) return false;
      final attrs = await _cognitoUser!.getUserAttributes() ?? [];
      final sub = _session!.idToken.getSub();
      final name = attrs.where((a) => a.name == 'name').firstOrNull?.value;
      final groups = _session!.idToken.payload?['cognito:groups'] as List<dynamic>?;
      final group = groups?.isNotEmpty == true ? groups!.first as String : null;
      _user = User(id: sub ?? '', email: email, name: name, role: group);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('remember_me', rememberMe);
      if (rememberMe) {
        await _persist();
      } else {
        await prefs.remove('cognito_email');
        await prefs.remove('user_json');
      }
      return true;
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> signUp(String email, String password, String name) async {
    try {
      await _pool.signUp(email, password, userAttributes: [
        AttributeArg(name: 'email', value: email),
        if (name.isNotEmpty) AttributeArg(name: 'name', value: name),
      ]);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> confirmUser(String email, String code) async {
    final user = CognitoUser(email, _pool);
    try {
      return await user.confirmRegistration(code);
    } catch (_) {
      return false;
    }
  }

  Future<void> forgotPassword(String email) async {
    final user = CognitoUser(email, _pool);
    await user.forgotPassword();
  }

  Future<bool> confirmForgotPassword(String email, String code, String newPassword) async {
    final user = CognitoUser(email, _pool);
    return await user.confirmPassword(code, newPassword);
  }

  Future<void> signOut() async {
    _cognitoUser?.signOut();
    _session = null;
    _user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cognito_email');
    await prefs.remove('user_json');
  }

  Future<String?> getIdToken() async {
    if (_session != null && _session!.isValid()) {
      return _session!.idToken.jwtToken;
    }
    await _restore();
    return _session?.idToken.jwtToken;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (_user != null) {
      await prefs.setString('cognito_email', _user!.email);
      await prefs.setString('user_json', jsonEncode({
        'id': _user!.id, 'email': _user!.email, 'name': _user!.name, 'role': _user!.role,
      }));
    }
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('remember_me') ?? false)) return;
    try {
      _cognitoUser = await _pool.getCurrentUser();
      if (_cognitoUser == null) return;
      _session = await _cognitoUser!.getSession();
      if (_session == null || !_session!.isValid()) { _session = null; return; }
      final userStr = prefs.getString('user_json');
      if (userStr != null) _user = User.fromJson(jsonDecode(userStr));
    } catch (_) {
      _session = null;
    }
  }
}
