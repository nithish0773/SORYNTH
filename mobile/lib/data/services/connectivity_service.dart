import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  final _connectionStatusController = StreamController<bool>.broadcast();

  bool _isOnline = false;
  bool get isOnline => _isOnline;
  Stream<bool> get onConnectivityChanged => _connectionStatusController.stream;

  StreamSubscription<List<ConnectivityResult>>? _subscription;

 ConnectivityService({bool initialize = true}) {
  if (initialize) {
    _init();
  }
}

  void _init() {
    _checkInitialStatus();
    _subscription = _connectivity.onConnectivityChanged.listen((results) async {
      await _evaluateInternetAccess(results);
    });
  }

  Future<void> _checkInitialStatus() async {
    try {
      final results = await _connectivity.checkConnectivity();
      debugPrint('[SORYNTH-NET] Network results: $results');
      await _evaluateInternetAccess(results);
    } catch (e) {
      debugPrint('[ConnectivityService] Initial check error: $e');
      _isOnline = false;
      _connectionStatusController.add(false);
    }
  }

  Future<bool> checkActualInternetReachability() async {
    debugPrint('[SORYNTH-NET] Reachability check started');
    try {
      final results = await _connectivity.checkConnectivity();
      debugPrint('[SORYNTH-NET] Network results: $results');
      final hasNetworkInterface = results.any((r) =>
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet);

      if (!hasNetworkInterface) {
        _isOnline = false;
        _connectionStatusController.add(false);
        return false;
      }

      // Fast DNS lookup probe
      final lookup = await InternetAddress.lookup('dns.google')
          .timeout(const Duration(seconds: 3));
      final hasInternet = lookup.isNotEmpty && lookup[0].rawAddress.isNotEmpty;
      debugPrint('[SORYNTH-NET] DNS result: $hasInternet');

      if (_isOnline != hasInternet) {
        _isOnline = hasInternet;
        _connectionStatusController.add(hasInternet);
      }
      return hasInternet;
    } catch (e) {
      debugPrint('[ConnectivityService] Internet check failed: $e');
      _isOnline = false;
      _connectionStatusController.add(false);
      return false;
    }
  }

  Future<void> _evaluateInternetAccess(List<ConnectivityResult> results) async {
    final hasInterface = results.any((r) =>
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.ethernet);

    if (!hasInterface) {
      _isOnline = false;
      _connectionStatusController.add(false);
      return;
    }

    // Network interface is active, verify reachability
    await checkActualInternetReachability();
  }

  void dispose() {
    _subscription?.cancel();
    _connectionStatusController.close();
  }
}


