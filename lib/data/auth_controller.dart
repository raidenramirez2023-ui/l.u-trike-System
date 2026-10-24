import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/env.dart';
import 'models.dart';

/// Holds the current session + profile and drives router redirects.
class AuthController extends ChangeNotifier {
  AuthController._();
  static final instance = AuthController._();

  StreamSubscription<AuthState>? _sub;
  Session? session;
  Profile? profile;
  bool loading = true;
  bool passwordRecovery = false;
  Object? profileError;

  bool get signedIn => session != null;

  Future<void> init() async {
    session = sb.auth.currentSession;
    await _loadProfile();
    _sub = sb.auth.onAuthStateChange.listen((s) async {
      if (s.event == AuthChangeEvent.passwordRecovery) passwordRecovery = true;
      final changedUser = s.session?.user.id != session?.user.id;
      session = s.session;
      if (s.event == AuthChangeEvent.signedOut) {
        profile = null;
        passwordRecovery = false;
      }
      if (changedUser || s.event == AuthChangeEvent.userUpdated) await _loadProfile();
      notifyListeners();
    });
  }

  Future<void> _loadProfile() async {
    loading = true;
    profileError = null;
    notifyListeners();
    try {
      final uid = session?.user.id;
      profile = uid == null ? null : await _fetchProfile(uid);
    } catch (e) {
      profileError = e;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<Profile?> _fetchProfile(String uid) async {
    final row = await sb.from('profiles').select().eq('id', uid).maybeSingle();
    return row == null ? null : Profile.fromJson(row);
  }

  Future<void> refreshProfile() => _loadProfile();

  /// Signs in and verifies the account belongs to the portal being used.
  Future<void> signIn(String email, String password, UserRole portal) async {
    final res = await sb.auth.signInWithPassword(email: email.trim(), password: password);
    final p = await _fetchProfile(res.user!.id);
    if (p == null || p.role != portal) {
      await sb.auth.signOut();
      throw const AuthException('This account cannot sign in here. Please use the correct login portal.');
    }
    session = res.session;
    profile = p;
    notifyListeners();
  }

  /// Returns true when email confirmation is required before first login.
  Future<bool> signUpStudent({
    required String fullName,
    required String studentNumber,
    required String email,
    required String password,
    String? contactNo,
  }) async {
    final problem = await sb.rpc('check_registration', params: {
      'p_role': 'student',
      'p_student_number': studentNumber.trim(),
      'p_email': email.trim(),
    });
    if (problem != null) throw AuthException(problem as String);
    final res = await sb.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: kIsWeb ? Uri.base.origin : null,
      data: {
        'role': 'student',
        'full_name': fullName.trim(),
        'student_number': studentNumber.trim(),
        'institutional_email': email.trim(),
        'contact_no': contactNo?.trim(),
      },
    );
    return res.session == null;
  }

  Future<bool> signUpDriver({
    required String fullName,
    required String email,
    required String password,
    required String contactNo,
    required String plateNo,
    required int capacity,
    required String terminalId,
    String? licenseNo,
  }) async {
    final problem = await sb.rpc('check_registration', params: {'p_role': 'driver', 'p_plate_no': plateNo.trim()});
    if (problem != null) throw AuthException(problem as String);
    final res = await sb.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: kIsWeb ? Uri.base.origin : null,
      data: {
        'role': 'driver',
        'full_name': fullName.trim(),
        'contact_no': contactNo.trim(),
        'plate_no': plateNo.trim(),
        'capacity': capacity.toString(),
        'terminal_id': terminalId,
        'license_no': licenseNo?.trim(),
      },
    );
    return res.session == null;
  }

  Future<void> sendPasswordReset(String email) =>
      sb.auth.resetPasswordForEmail(email.trim(), redirectTo: kIsWeb ? Uri.base.origin : null);

  Future<void> verifyRecoveryOtp({required String email, required String token}) async {
    final res = await sb.auth.verifyOTP(
      email: email.trim(),
      token: token.trim(),
      type: OtpType.recovery,
    );
    session = res.session;
    notifyListeners();
  }

  Future<void> updatePassword(String newPassword) async {
    await sb.auth.updateUser(UserAttributes(password: newPassword));
    passwordRecovery = false;
    notifyListeners();
  }

  Future<void> signOut() async {
    await sb.auth.signOut();
    session = null;
    profile = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
