import 'dart:async';
import 'package:flutter/material.dart';
import '../models/account.dart';
import '../models/strategy_state.dart';
import '../models/trade_history.dart';
import '../services/api_client.dart';
import '../services/strategy_service.dart';
import '../widgets/account_card.dart';
import '../widgets/strategy_card.dart';
import 'chart_screen.dart';
import 'strategy_screen.dart';
import 'trades_screen.dart';
import '../screens/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int currentIndex = 0;
  AccountData? _accountData;
  List<TradeHistory> _history = [];
  final StrategyService _strategy = PollingStrategyService();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _fetchAccount();
    _startPolling(); // Start auto-refresh
  }

  void _startPolling() {
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) _fetchAccount();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _strategy.dispose();
    super.dispose();
  }

  Future<void> _fetchAccount() async {
    try {
      final results = await Future.wait([
        ApiClient.get('/accounts/info/'),
        ApiClient.get('/execution/trading-data/'),
      ]);

      if (mounted && results[0] != null) {
        setState(() {
          _accountData = AccountData.fromJson(results[0]);
          if (results[1] != null) {
            final tradeData = results[1] as Map<String, dynamic>;
            final rawDeals = tradeData['deals'] as List? ?? [];
            _history = rawDeals
                .map((h) => TradeHistory.fromJson(h as Map<String, dynamic>))
                .toList();
          }
        });
      }
    } catch (e) {
      debugPrint("Error fetching account: $e");
    }
  }

  Widget bottomNav() {
    return BottomNavigationBar(
      currentIndex: currentIndex,
      backgroundColor: const Color(0xff111827),
      selectedItemColor: Colors.green,
      unselectedItemColor: Colors.grey,
      type: BottomNavigationBarType.fixed,
      onTap: (index) => setState(() => currentIndex = index),
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
        BottomNavigationBarItem(icon: Icon(Icons.show_chart), label: "Chart"),
        BottomNavigationBarItem(icon: Icon(Icons.swap_horiz), label: "Trades"),
        BottomNavigationBarItem(
          icon: Icon(Icons.psychology),
          label: "Strategies",
        ),
        BottomNavigationBarItem(icon: Icon(Icons.settings), label: "Settings"),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      HomeDashboard(accountData: _accountData, strategy: _strategy, history: _history),
      const ChartScreen(),
      const TradesScreen(),
      StrategyScreen(strategy: _strategy),
      const SettingsScreen(),
    ];
    return Scaffold(
      backgroundColor: const Color(0xff0b1220),
      appBar: AppBar(
        backgroundColor: const Color(0xff0b1220),
        elevation: 0,
        title: const Text("Sadra", style: TextStyle(color: Colors.white)),
        actions: [
          StreamBuilder<List<WorkerState>>(
            stream: _strategy.states,
            initialData: _strategy.snapshot,
            builder: (context, snap) {
              final anyRunning = (snap.data ?? []).any(
                (w) => w.running && !w.paused,
              );
              return Padding(
                padding: const EdgeInsets.only(right: 24),
                child: Row(
                  children: [
                    Text(
                      anyRunning ? 'LIVE' : 'IDLE',
                      style: TextStyle(
                        color: anyRunning ? Colors.green : Colors.grey,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: anyRunning ? Colors.green : Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: pages[currentIndex],
      bottomNavigationBar: bottomNav(),
    );
  }
}

class HomeDashboard extends StatelessWidget {
  final AccountData? accountData;
  final StrategyService strategy;
  final List<TradeHistory> history;

  const HomeDashboard({
    super.key,
    required this.strategy,
    this.accountData,
    this.history = const [],
  });

  Future<void> _confirmKill(BuildContext context, WorkerState w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xff162033),
        title: const Text(
          'Kill strategy?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Kill ${w.strategy} on ${w.symbol}? Worker stops permanently.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kill', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true) strategy.kill(w.key);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AccountCard(data: accountData, history: history),
            const SizedBox(height: 20),
            _sectionTitle("Running strategies"),
            StreamBuilder<List<WorkerState>>(
              stream: strategy.states,
              initialData: strategy.snapshot,
              builder: (context, snap) {
                final workers = snap.data ?? [];
                if (workers.isEmpty)
                  return _placeholder("No running strategies.");
                return Column(
                  children: workers
                      .map(
                        (w) => StrategyCard(
                          state: w,
                          onPause: () => strategy.pause(w.key),
                          onResume: () => strategy.resume(w.key),
                          onKill: () => _confirmKill(context, w),
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 12),
            _sectionTitle("Recent activity"),
            _ActivityFeed(strategy: strategy),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12, top: 4),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),
  );

  Widget _placeholder(String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xff162033),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(text, style: const TextStyle(color: Colors.grey)),
  );
}

class _ActivityFeed extends StatefulWidget {
  final StrategyService strategy;
  const _ActivityFeed({required this.strategy});
  @override
  State<_ActivityFeed> createState() => _ActivityFeedState();
}

class _ActivityFeedState extends State<_ActivityFeed> {
  final List<StrategyEvent> _events = [];
  @override
  void initState() {
    super.initState();
    widget.strategy.events.listen((e) {
      if (!mounted) return;
      setState(() {
        _events.insert(0, e);
        if (_events.length > 30) _events.removeLast();
      });
    });
  }

  String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xff162033),
        borderRadius: BorderRadius.circular(16),
      ),
      child: _events.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                "Waiting for events…",
                style: TextStyle(color: Colors.grey),
              ),
            )
          : Column(
              children: _events
                  .map(
                    (e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _time(e.time),
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: Colors.blueAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              e.symbol,
                              style: const TextStyle(
                                color: Colors.blueAccent,
                                fontSize: 10,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              e.message,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}
