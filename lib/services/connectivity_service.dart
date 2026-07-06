import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  final Connectivity _connectivity = Connectivity();

  Stream<List<ConnectivityResult>> get connectivityStream => _connectivity.onConnectivityChanged;

  Future<List<ConnectivityResult>> get currentConnectivity => _connectivity.checkConnectivity();

  /// True when a network interface is up (Wi‑Fi/mobile). Does not prove Firebase
  /// is reachable — use [isLikelyReachable] for background sync decisions.
  Future<bool> isOnline() async {
    final results = await currentConnectivity;
    return results.any((result) => result != ConnectivityResult.none);
  }

  /// Optional probe supplied by the app (e.g. a short Firestore read). Returns
  /// false when offline or when [probe] times out / throws.
  Future<bool> isLikelyReachable({
    required Future<void> Function() probe,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (!await isOnline()) return false;
    try {
      await probe().timeout(timeout);
      return true;
    } catch (_) {
      return false;
    }
  }
}
