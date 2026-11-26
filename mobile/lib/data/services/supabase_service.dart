import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/app_constants.dart';
import '../models/emergency_model.dart';
import '../models/user_profile.dart';

class SupabaseService {
  bool _isConfigured = false;
  bool get isConfigured => _isConfigured;

  String _configuredUrl = '';
  String get configuredUrl => _configuredUrl;

  SupabaseClient? get client {
    if (!_isConfigured) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Initialize Supabase with environment variables or AppConstants
  Future<void> initialize({
    String? url,
    String? anonKey,
  }) async {
    final targetUrl = (url != null && url.isNotEmpty)
        ? url
        : (const String.fromEnvironment('SUPABASE_URL', defaultValue: '')
                .isNotEmpty
            ? const String.fromEnvironment('SUPABASE_URL')
            : AppConstants.defaultSupabaseUrl);

    final targetKey = (anonKey != null && anonKey.isNotEmpty)
        ? anonKey
        : (const String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '')
                .isNotEmpty
            ? const String.fromEnvironment('SUPABASE_ANON_KEY')
            : AppConstants.defaultSupabaseAnonKey);

    final cleanUrl = targetUrl.trim();
    final cleanKey = targetKey.trim();

    if (cleanUrl.isEmpty || cleanKey.isEmpty) {
      debugPrint(
          '[SupabaseService] SUPABASE_URL ($cleanUrl) or publishable key is not configured. Cloud sync will operate in unconfigured offline mode.');
      _isConfigured = false;
      return;
    }

    try {
      await Supabase.initialize(
        url: cleanUrl,
        publishableKey: cleanKey,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
        ),
      );
      _isConfigured = true;
      _configuredUrl = cleanUrl;
      debugPrint('[SupabaseService] Connected to Supabase project: $cleanUrl');
    } catch (e) {
      debugPrint(
          '[SupabaseService] Initialization failed: $e. Operating in fallback mode.');
      _isConfigured = false;
    }
  }

  /// Check if Supabase endpoint is actually reachable over network
  Future<bool> checkSupabaseReachable() async {
    if (!_isConfigured || client == null) return false;
    try {
      // Lightweight call to verify connection
      await client!.from('emergencies').select('id').limit(1).timeout(
            const Duration(seconds: 4),
          );
      return true;
    } catch (e) {
      debugPrint('[SupabaseService] Endpoint check failed: $e');
      // If error is permission or empty table, the server is still reachable
      if (e.toString().contains('PGRST') ||
          e.toString().contains('401') ||
          e.toString().contains('403')) {
        return true;
      }
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // AUTHENTICATION
  // ---------------------------------------------------------------------------

  User? get currentUser => client?.auth.currentUser;
  Stream<AuthState>? get authStateChanges => client?.auth.onAuthStateChange;

  Future<AuthResponse?> signIn({
    required String email,
    required String password,
  }) async {
    if (!_isConfigured || client == null) {
      throw Exception('Supabase backend is not configured.');
    }
    return await client!.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<AuthResponse?> signUp({
    required String email,
    required String password,
    required String fullName,
    String? phone,
    String? emailRedirectTo,
  }) async {
    if (!_isConfigured || client == null) {
      throw Exception('Supabase backend is not configured.');
    }

    final res = await client!.auth.signUp(
      email: email.trim(),
      password: password,
      data: {
        'full_name': fullName,
        'phone_number': phone,
      },
      emailRedirectTo: emailRedirectTo ?? 'io.supabase.sorynth://login-callback',
    );

    if (res.user != null && res.session != null) {
      await saveInitialProfile(
        id: res.user!.id,
        fullName: fullName,
        email: email,
        phone: phone,
      );
    }
    return res;
  }

  Future<void> signOut() async {
    if (_isConfigured && client != null) {
      await client!.auth.signOut();
    }
  }

  Future<void> sendPasswordReset(String email) async {
    if (!_isConfigured || client == null) {
      throw Exception('Supabase backend is not configured.');
    }
    await client!.auth.resetPasswordForEmail(email.trim());
  }

  Future<void> resendConfirmationEmail(
    String email, {
    String? emailRedirectTo,
  }) async {
    if (!_isConfigured || client == null) {
      throw Exception('Supabase backend is not configured.');
    }
    await client!.auth.resend(
      type: OtpType.signup,
      email: email.trim(),
      emailRedirectTo: emailRedirectTo ?? 'io.supabase.sorynth://login-callback',
    );
  }

  /// Initiates Google OAuth authentication using Supabase Flutter.
  /// Launches the external authentication browser and redirects back to the app via deep link.
  Future<bool> signInWithGoogle({String? redirectTo}) async {
    if (!_isConfigured || client == null) {
      throw Exception('Supabase backend is not configured.');
    }
    return await client!.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: redirectTo ?? 'io.supabase.sorynth://login-callback',
    );
  }

  /// Synchronizes a newly authenticated OAuth user (e.g. from Google) into the public profiles table.
  Future<void> syncOAuthProfile(User user) async {
    if (!_isConfigured || client == null) return;
    try {
      final existing = await fetchProfile(user.id);
      if (existing == null) {
        final meta = user.userMetadata ?? {};
        final fullName = (meta['full_name'] as String?) ??
            (meta['name'] as String?) ??
            (user.email?.split('@').first ?? 'Civilian Responder');
        final phone = (meta['phone_number'] as String?) ??
            (meta['phone'] as String?);
        await saveInitialProfile(
          id: user.id,
          fullName: fullName,
          email: user.email,
          phone: phone,
        );
      }
    } catch (e) {
      debugPrint('[SupabaseService] Error syncing OAuth profile: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // USER PROFILES
  // ---------------------------------------------------------------------------

  Future<void> saveInitialProfile({
    required String id,
    required String fullName,
    String? email,
    String? phone,
  }) async {
    if (!_isConfigured || client == null) return;
    try {
      await client!.from('profiles').upsert({
        'id': id,
        'full_name': fullName,
        'email': email,
        'phone_number': phone,
      });
    } catch (e) {
      debugPrint('[SupabaseService] Error creating initial profile: $e');
    }
  }

  Future<UserProfile?> fetchProfile(String userId) async {
    if (!_isConfigured || client == null) return null;
    try {
      final res = await client!
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (res != null) {
        return UserProfile.fromJson(res);
      }
    } catch (e) {
      debugPrint('[SupabaseService] Error fetching profile: $e');
    }
    return null;
  }

  Future<void> updateProfile(UserProfile profile) async {
    if (!_isConfigured || client == null) return;
    await client!
        .from('profiles')
        .update(profile.toJson())
        .eq('id', profile.id);
  }

  // ---------------------------------------------------------------------------
  // SOS EMERGENCY SUBMISSION (ONLINE WORKFLOW)
  // ---------------------------------------------------------------------------

  /// Submits SOS via Supabase RPC `submit_sos_alert`.
  /// Handles both Guest SOS and Authenticated SOS safely.
  Future<Map<String, dynamic>> submitSosAlert(EmergencyModel emergency) async {
    if (!_isConfigured || client == null) {
      throw Exception('Supabase backend is not configured.');
    }

    try {
      final response = await client!.rpc(
        'submit_sos_alert',
        params: {
          'p_emergency_code': emergency.emergencyId,
          'p_sender_name': emergency.personName,
          'p_sender_phone': emergency.phone,
          'p_emergency_type': emergency.emergencyType.code,
          'p_custom_message': emergency.message,
          'p_latitude': emergency.latitude,
          'p_longitude': emergency.longitude,
          'p_accuracy_meters': emergency.accuracy,
          'p_communication_method': emergency.communicationMethod.code,
          'p_hop_count': emergency.hopCount,
          'p_relay_path': emergency.relayPath,
        },
      ).timeout(const Duration(seconds: 12));

      debugPrint('[SupabaseService] submit_sos_alert response: $response');
      if (response is! Map) {
        throw Exception(
          'Invalid response format from SORYNTH server.',
        );
      }

      final map = Map<String, dynamic>.from(response);

      if (map['success'] != true) {
        throw Exception(
          map['error'] ?? 'Server rejected alert submission.',
        );
      }

      return map;
    } catch (e) {
      debugPrint('[SupabaseService] submit_sos_alert error: $e');
      rethrow;
    }
  }

  /// Query emergency status by unique code
  Future<EmergencyModel?> getEmergencyStatus(String emergencyCode) async {
    if (!_isConfigured || client == null) return null;
    try {
      final res = await client!.rpc('get_emergency_status', params: {
        'p_emergency_code': emergencyCode,
      }).timeout(const Duration(seconds: 8));

      if (res is Map && res['found'] == true) {
        return EmergencyModel.fromJson(Map<String, dynamic>.from(res));
      }
    } catch (e) {
      debugPrint('[SupabaseService] getEmergencyStatus error: $e');
    }
    return null;
  }

  /// Cancel emergency alert
  Future<bool> cancelEmergency(String emergencyCode,
      {String reason = 'User requested cancellation'}) async {
    if (!_isConfigured || client == null) return false;
    try {
      final res = await client!.rpc('cancel_emergency', params: {
        'p_emergency_code': emergencyCode,
        'p_reason': reason,
      }).timeout(const Duration(seconds: 8));
      return res is Map && res['success'] == true;
    } catch (e) {
      debugPrint('[SupabaseService] cancelEmergency error: $e');
      return false;
    }
  }

  /// Realtime stream for an emergency code
  RealtimeChannel? subscribeToEmergencyUpdates(
    String emergencyCode,
    void Function(EmergencyStatus newStatus) onStatusChange,
  ) {
    if (!_isConfigured || client == null) return null;

    final channel = client!.channel('emergency:$emergencyCode');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'emergencies',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'emergency_code',
            value: emergencyCode,
          ),
          callback: (payload) {
            final newRecord = payload.newRecord;
            if (newRecord.containsKey('status')) {
              final status =
                  EmergencyStatus.fromCode(newRecord['status'].toString());
              onStatusChange(status);
            }
          },
        )
        .subscribe();

    return channel;
  }
}
