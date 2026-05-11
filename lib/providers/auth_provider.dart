import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final _auth = AuthService();
  bool _loading = false;
  String? _error;

  User? get user => _auth.user;
  bool get isAuthenticated => _auth.isAuthenticated;
  bool get loading => _loading;
  String? get error => _error;

  Future<String?> getIdToken() => _auth.getIdToken();

  Future<bool> signIn(String email, String password, {bool rememberMe = true}) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final ok = await _auth.signIn(email, password, rememberMe: rememberMe);
      if (!ok) _error = 'Invalid email or password';
      return ok;
    } catch (e) {
      _error = _friendlyError(e.toString());
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> signUp(String email, String password, String name) =>
      _auth.signUp(email, password, name);

  void clearError() {
    _error = null;
    notifyListeners();
  }

  static String _friendlyError(String raw) {
    final s = raw.toLowerCase();
    if (s.contains('incorrect username or password') || s.contains('not authorized')) {
      return 'Incorrect email or password';
    }
    if (s.contains('user does not exist')) return 'Account not found';
    if (s.contains('user is not confirmed')) return 'Please verify your email first';
    if (s.contains('password attempts exceeded') || s.contains('too many')) {
      return 'Too many attempts, please try again later';
    }
    if (s.contains('network') || s.contains('socket') || s.contains('timeout')) {
      return 'Network error, please check your connection';
    }
    if (s.contains('invalid parameter') || s.contains('invalid email')) {
      return 'Please enter a valid email address';
    }
    return 'Login failed, please try again';
  }

  Future<bool> confirmUser(String email, String code) =>
      _auth.confirmUser(email, code);

  Future<bool> forgotPassword(String email) async {
    _loading = true; _error = null; notifyListeners();
    try { await _auth.forgotPassword(email); return true; }
    catch (e) { _error = e.toString(); return false; }
    finally { _loading = false; notifyListeners(); }
  }

  Future<bool> confirmForgotPassword(String email, String code, String newPassword) async {
    _loading = true; _error = null; notifyListeners();
    try { return await _auth.confirmForgotPassword(email, code, newPassword); }
    catch (e) { _error = e.toString(); return false; }
    finally { _loading = false; notifyListeners(); }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    notifyListeners();
  }

  /// Restore session from SharedPreferences on app start
  Future<void> tryRestore() async {
    await _auth.getIdToken(); // triggers _restore internally
    notifyListeners();
  }
}
