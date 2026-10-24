import 'package:supabase_flutter/supabase_flutter.dart';

/// Build-time configuration. Provide via:
///   flutter run -d chrome --dart-define-from-file=env.json
/// Only the PUBLIC anon key belongs here – never the service-role key.
class Env {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://zsmkqhgjecprqfebfhmi.supabase.co',
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpzbWtxaGdqZWNwcnFmZWJmaG1pIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI3Mzg3NzIsImV4cCI6MjEwODMxNDc3Mn0.MJgpAkWj62bxF1vzXLlYYQrTfQlJm8MRKOvpuTpr_M8',
  );
  static const demoMode = bool.fromEnvironment('DEMO_MODE', defaultValue: true);
  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}

SupabaseClient get sb => Supabase.instance.client;

/// Converts backend/network errors into safe, user-friendly text.
String friendlyError(Object e) {
  if (e is PostgrestException) {
    if (e.message.isNotEmpty) return e.message;
    if (e.code == '23505') return 'This record already exists.';
    if (e.code == '23514') return 'The value is outside the allowed range.';
    if (e.code == '42501') return 'You do not have permission to do that.';
    return 'Database error (${e.code}). Please try again.';
  }
  if (e is AuthException) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login')) return 'Incorrect email or password.';
    if (m.contains('email not confirmed')) return 'Please confirm your email address first (check your inbox).';
    if (m.contains('already registered')) return 'An account with this email already exists.';
    if (m.contains('database error')) return 'Registration could not be completed. Please check your details.';
    return e.message;
  }
  final s = e.toString().toLowerCase();
  if (s.contains('socket') || s.contains('network') || s.contains('failed host lookup') || s.contains('clientexception')) {
    return 'Connection problem. Check your internet and try again.';
  }
  return 'Something went wrong. Please try again.';
}
