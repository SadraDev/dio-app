import 'dart:async';

import '../models/strategy_state.dart';
import '../models/backtest_result.dart';
import 'api_client.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// REST surface for the strategies app (config / start / control / backtest).
/// ─────────────────────────────────────────────────────────────────────────

class StrategySnapshot {
  final List<WorkerState> workers;
  final List<Map<String, dynamic>> logs;

  StrategySnapshot({required this.workers, required this.logs});
}

class StrategyApi {
  static Future<StrategySnapshot> getSnapshot() async {
    try {
      final response = await ApiClient.get('/strategies/workers/');

      final workers = (response.data['workers'] as List)
          .map((w) => WorkerState.fromJson(w))
          .toList();

      final logs = List<Map<String, dynamic>>.from(response.data['logs'] ?? []);

      return StrategySnapshot(workers: workers, logs: logs);
    } catch (e) {
      throw Exception('Failed to fetch snapshot: $e');
    }
  }

  static Future<Map<String, dynamic>> getConfig() async {
    final res = await ApiClient.get('/strategies/twohunters/config/');
    return Map<String, dynamic>.from(res['config'] ?? {});
  }

  static Future<Map<String, dynamic>> updateConfig(
      Map<String, dynamic> config) async {
    final res = await ApiClient.dio
        .put('/strategies/twohunters/config/', data: {'config': config});
    return Map<String, dynamic>.from(res.data['config'] ?? {});
  }

  static Future<WorkerState> startProcess(
    String symbol, {
    Map<String, dynamic>? config,
  }) async {
    final res = await ApiClient.post('/strategies/twohunters/start/', body: {
      'symbol': symbol,
      'config': ?config,
    });
    return WorkerState.fromJson(Map<String, dynamic>.from(res));
  }

  /// action: pause | resume | kill
  static Future<void> control(String key, String action) async {
    await ApiClient.post('/strategies/workers/control/',
        body: {'key': key, 'action': action});
  }

  static Future<List<WorkerState>> snapshot() async {
    final res = await ApiClient.get('/strategies/workers/');
    final list = (res['workers'] as List?) ?? [];
    return list
        .map((e) => WorkerState.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<BacktestRun> backtest({
    required List<String> symbols,
    required String startDate, // yyyy-MM-dd
    required String endDate,
    Map<String, dynamic>? config,
  }) async {
    final res = await ApiClient.post('/strategies/twohunters/backtest/', body: {
      'symbols': symbols,
      'start_date': startDate,
      'end_date': endDate,
      'config': ?config,
    });
    return BacktestRun.fromJson(Map<String, dynamic>.from(res));
  }

  static Future<BacktestRun> getBacktest(int id) async {
    final res = await ApiClient.get('/strategies/backtests/$id/');
    return BacktestRun.fromJson(Map<String, dynamic>.from(res));
  }

  static Future<WorkerState> updateWorkerConfig(String workerId, Map<String, dynamic> config) async {
    try {
      final response = await ApiClient.post(
        '/strategies/workers/update_config/',
        body: {
          'id': workerId,
          'config': config,
        },
      );

      // Since it's already the bare object, just pass it directly to fromJson
      return WorkerState.fromJson(response.data as Map<String, dynamic>);

    } catch (e) {
      throw Exception('Failed to update worker config: $e');
    }
  }

}

/// ─────────────────────────────────────────────────────────────────────────
/// Streaming contract the home / strategy screens depend on.
/// ─────────────────────────────────────────────────────────────────────────
abstract class StrategyService {
  Stream<List<WorkerState>> get states;
  Stream<StrategyEvent> get events;
  List<WorkerState> get snapshot;

  Future<void> start(String workerKey);
  Future<void> stop(String workerKey);
  Future<void> pause(String workerKey);
  Future<void> resume(String workerKey);
  Future<void> kill(String workerKey);

  void dispose();
}

/// ─────────────────────────────────────────────────────────────────────────
/// Live service: pure REST polling (every 2.5s). No websockets.
/// The home / strategy screens just listen to `states`.
/// ─────────────────────────────────────────────────────────────────────────
class PollingStrategyService implements StrategyService {
  final _statesCtrl = StreamController<List<WorkerState>>.broadcast();
  final _eventsCtrl = StreamController<StrategyEvent>.broadcast();

  List<WorkerState> _workers = [];
  final Map<String, String> _lastMessage = {}; // key -> last narration
  Timer? _poll;
  bool _disposed = false;

  PollingStrategyService({Duration interval = const Duration(milliseconds: 2500)}) {
    _pollOnce(); // immediate
    _poll = Timer.periodic(interval, (_) => _pollOnce());
  }

  Future<void> _pollOnce() async {
    if (_disposed) return;
    try {
      final next = await StrategyApi.snapshot();
      _applySnapshot(next);
    } catch (_) {
      // backend unreachable; keep last known state silently
    }
  }

  /// Emit the latest states and derive activity-feed events from message changes.
  void _applySnapshot(List<WorkerState> next) {
    for (final w in next) {
      if (_lastMessage[w.key] != w.message) {
        _lastMessage[w.key] = w.message;
        if (!_eventsCtrl.isClosed) {
          _eventsCtrl.add(StrategyEvent(
            symbol: w.symbol,
            strategy: w.strategy,
            message: w.message,
            time: DateTime.now(),
          ));
        }
      }
    }
    _workers = next;
    if (!_statesCtrl.isClosed) _statesCtrl.add(_workers);
  }

  @override
  Stream<List<WorkerState>> get states => _statesCtrl.stream;
  @override
  Stream<StrategyEvent> get events => _eventsCtrl.stream;
  @override
  List<WorkerState> get snapshot => _workers;

  // Optimistic local update so controls feel instant; the next poll reconciles.
  void _optimistic(String key, WorkerState Function(WorkerState) f) {
    final idx = _workers.indexWhere((w) => w.key == key);
    if (idx == -1) return;
    final next = List<WorkerState>.from(_workers);
    next[idx] = f(next[idx]);
    _applySnapshot(next);
  }

  @override
  Future<void> start(String workerKey) async {
    _optimistic(workerKey, (w) => w.copyWith(paused: false));
    await StrategyApi.control(workerKey, 'resume');
    _pollOnce();
  }

  @override
  Future<void> stop(String workerKey) => kill(workerKey);

  @override
  Future<void> pause(String workerKey) async {
    _optimistic(workerKey, (w) => w.copyWith(paused: true, phase: WorkerPhase.paused));
    await StrategyApi.control(workerKey, 'pause');
    _pollOnce();
  }

  @override
  Future<void> resume(String workerKey) async {
    _optimistic(workerKey, (w) => w.copyWith(paused: false));
    await StrategyApi.control(workerKey, 'resume');
    _pollOnce();
  }

  @override
  Future<void> kill(String workerKey) async {
    _workers = _workers.where((w) => w.key != workerKey).toList();
    if (!_statesCtrl.isClosed) _statesCtrl.add(_workers);
    await StrategyApi.control(workerKey, 'kill');
    _pollOnce();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _statesCtrl.close();
    _eventsCtrl.close();
  }
}
