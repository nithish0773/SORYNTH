import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/emergency_model.dart';
import '../../data/models/user_profile.dart';
import '../../data/repositories/emergency_repository.dart';
import '../../data/services/bluetooth_service.dart';
import '../../data/services/connectivity_service.dart';
import '../../data/services/gps_service.dart';
import '../../data/services/offline_storage_service.dart';
import '../../data/services/supabase_service.dart';

// -----------------------------------------------------------------------------
// CORE SERVICE PROVIDERS
// -----------------------------------------------------------------------------

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be initialized in main()');
});

final offlineStorageServiceProvider = Provider<OfflineStorageService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return OfflineStorageService(prefs);
});

final gpsServiceProvider = Provider<GpsService>((ref) {
  return GpsService();
});

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  final service = ConnectivityService();
  ref.onDispose(() => service.dispose());
  return service;
});

final isOnlineStreamProvider = StreamProvider<bool>((ref) {
  debugPrint('[isOnlineStreamProvider] Provider evaluated / factory called');
  final connectivity = ref.watch(connectivityServiceProvider);

  return Stream<bool>.multi((controller) {
    debugPrint('[isOnlineStreamProvider] Stream.multi subscription started');
    final subscription =
        connectivity.onConnectivityChanged.listen((isOnline) {
      debugPrint(
          '[isOnlineStreamProvider] onConnectivityChanged received: $isOnline');
      controller.add(isOnline);
    });

    debugPrint(
        '[isOnlineStreamProvider] current connectivity.isOnline before emit: ${connectivity.isOnline}');
    controller.add(connectivity.isOnline);

    controller.onCancel = () {
      debugPrint('[isOnlineStreamProvider] Stream subscription cancelled');
      subscription.cancel();
    };
  });
});

final supabaseServiceProvider = Provider<SupabaseService>((ref) {
  return SupabaseService();
});

// -----------------------------------------------------------------------------
// HARDWARE BLUETOOTH LOW ENERGY SERVICE (GENUINE HARDWARE DRIVER)
// -----------------------------------------------------------------------------

final bluetoothServiceProvider = Provider<BluetoothService>((ref) {
  final BluetoothService service = FlutterBluePlusBluetoothService();
  ref.onDispose(() => service.dispose());
  return service;
});

final bluetoothTelemetryStreamProvider = StreamProvider<BleTelemetry>((ref) {
  final ble = ref.watch(bluetoothServiceProvider);
  return ble.telemetryStream;
});

// -----------------------------------------------------------------------------
// REPOSITORY PROVIDER
// -----------------------------------------------------------------------------

final emergencyRepositoryProvider = Provider<EmergencyRepository>((ref) {
  final supabase = ref.watch(supabaseServiceProvider);
  final bluetooth = ref.watch(bluetoothServiceProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  final storage = ref.watch(offlineStorageServiceProvider);

  final repo = EmergencyRepository(
    supabaseService: supabase,
    bluetoothService: bluetooth,
    connectivityService: connectivity,
    storageService: storage,
  );
  ref.onDispose(() => repo.dispose());
  return repo;
});

// -----------------------------------------------------------------------------
// GPS LIVE STATE
// -----------------------------------------------------------------------------

class GpsNotifier extends StateNotifier<AsyncValue<GpsResult>> {
  final GpsService _gpsService;

  GpsNotifier(this._gpsService) : super(const AsyncValue.loading()) {
    refreshLocation();
  }

  Future<void> refreshLocation() async {
    state = const AsyncValue.loading();
    try {
      final result = await _gpsService.getCurrentLocation();
      state = AsyncValue.data(result);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final gpsNotifierProvider =
    StateNotifierProvider<GpsNotifier, AsyncValue<GpsResult>>((ref) {
  final gps = ref.watch(gpsServiceProvider);
  return GpsNotifier(gps);
});

// -----------------------------------------------------------------------------
// ACTIVE EMERGENCY & HISTORY NOTIFIERS
// -----------------------------------------------------------------------------

class ActiveEmergencyNotifier extends StateNotifier<EmergencyModel?> {
  final EmergencyRepository _repo;
  StreamSubscription<EmergencyModel>? _subscription;

  ActiveEmergencyNotifier(this._repo) : super(null) {
    _loadInitial();
    _subscription = _repo.emergencyUpdatesStream.listen((updated) {
      final currentId = state?.emergencyId ?? _repo.getActiveEmergencyId();
      if (currentId == updated.emergencyId) {
        if (updated.isGenuinelyActive) {
          state = updated;
        } else {
          state = null;
        }
      }
    });
  }

  void _loadInitial() {
    final activeId = _repo.getActiveEmergencyId();
    if (activeId != null) {
      final em = _repo.getEmergency(activeId);
      if (em != null && em.isGenuinelyActive) {
        state = em;
      } else {
        // Clear stale ID from storage so it does not persist across restarts
        _repo.clearActiveEmergency();
        state = null;
      }
    } else {
      state = null;
    }
  }

  void refresh() {
    _loadInitial();
  }

  void setActive(EmergencyModel emergency) {
    if (emergency.isGenuinelyActive) {
      state = emergency;
      _repo.saveActiveEmergencyId(emergency.emergencyId);
    } else {
      state = null;
      _repo.clearActiveEmergency();
    }
  }

  Future<void> cancelActive() async {
    final id = state?.emergencyId ?? _repo.getActiveEmergencyId();
    if (id != null) {
      await _repo.cancelEmergency(id);
    }
    state = null;
  }

  Future<void> clearActive() async {
    await _repo.clearActiveEmergency();
    state = null;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final activeEmergencyProvider =
    StateNotifierProvider<ActiveEmergencyNotifier, EmergencyModel?>((ref) {
  final repo = ref.watch(emergencyRepositoryProvider);
  return ActiveEmergencyNotifier(repo);
});

class EmergencyHistoryNotifier extends StateNotifier<List<EmergencyModel>> {
  final EmergencyRepository _repo;
  StreamSubscription<EmergencyModel>? _subscription;

  EmergencyHistoryNotifier(this._repo) : super([]) {
    refresh();
    _subscription = _repo.emergencyUpdatesStream.listen((_) {
      refresh();
    });
  }

  void refresh() {
    state = _repo.getAllEmergencies();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final emergencyHistoryProvider =
    StateNotifierProvider<EmergencyHistoryNotifier, List<EmergencyModel>>((ref) {
  final repo = ref.watch(emergencyRepositoryProvider);
  return EmergencyHistoryNotifier(repo);
});

// -----------------------------------------------------------------------------
// USER PROFILE NOTIFIER
// -----------------------------------------------------------------------------

class UserProfileNotifier extends StateNotifier<UserProfile?> {
  final SupabaseService _supabase;

  UserProfileNotifier(this._supabase) : super(null) {
    loadProfile();
  }

  Future<void> loadProfile() async {
    final user = _supabase.currentUser;
    if (user != null) {
      final p = await _supabase.fetchProfile(user.id);
      if (p != null) {
        state = p;
      } else {
        final initial = UserProfile(
          id: user.id,
          fullName: user.userMetadata?['full_name']?.toString() ??
              (user.email?.split('@').first ?? 'Civilian Responder'),
          email: user.email,
          phoneNumber:
              user.userMetadata?['phone_number']?.toString() ?? user.phone,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        state = initial;
        // Persist initial profile into Supabase now that user is authenticated under RLS
        await _supabase.saveInitialProfile(
          id: initial.id,
          fullName: initial.fullName,
          email: initial.email,
          phone: initial.phoneNumber,
        );
      }
    } else {
      state = null;
    }
  }

  Future<void> updateProfile(UserProfile updated) async {
    state = updated;
    await _supabase.updateProfile(updated);
  }

  void clear() {
    state = null;
  }
}

final userProfileProvider =
    StateNotifierProvider<UserProfileNotifier, UserProfile?>((ref) {
  final supabase = ref.watch(supabaseServiceProvider);
  return UserProfileNotifier(supabase);
});

