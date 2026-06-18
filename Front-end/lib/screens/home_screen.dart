import 'package:flutter/material.dart';
import '../models/account.dart'; // Ensure this path is correct
import '../services/api_client.dart';
import '../widgets/account_card.dart'; // Ensure this path is correct
import 'chart_screen.dart';
import 'strategy_screen.dart';
import 'trades_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int currentIndex = 0;
  bool isBotRunning = true;
  AccountData? _accountData;

  // 1. CHANGED: This is now a getter so it refreshes when _accountData changes
  List<Widget> get pages => [
    HomeDashboard(accountData: _accountData),
    const ChartScreen(),
    const TradesScreen(),
    const StrategyScreen(),
    const Center(
      child: Text("Settings", style: TextStyle(color: Colors.white)),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _fetchAccount();
  }

  Future<void> _fetchAccount() async {
    try {
      final response = await ApiClient.get('/accounts/info/');
      if (response != null && mounted) {
        setState(() => _accountData = AccountData.fromJson(response));
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
      onTap: (index) {
        setState(() {
          currentIndex = index;
        });
      },
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
    return Scaffold(
      backgroundColor: const Color(0xff0b1220),
      appBar: AppBar(
        backgroundColor: const Color(0xff0b1220),
        elevation: 0,
        title: const Text("Sadra", style: TextStyle(color: Colors.white)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 28),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: isBotRunning ? Colors.green : Colors.red,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
      // 2. CHANGED: Use the getter 'pages'
      body: pages[currentIndex],
      bottomNavigationBar: bottomNav(),
    );
  }
}

// 3. CHANGED: HomeDashboard now accepts accountData
class HomeDashboard extends StatelessWidget {
  final AccountData? accountData;
  const HomeDashboard({super.key, this.accountData});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Using the AccountCard widget we built
            AccountCard(data: accountData),

            const SizedBox(height: 20),

            // Strategy Panel
            sectionTitle("Strategy Status"),
            card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "London Breakout",
                    style: TextStyle(color: Colors.white, fontSize: 20),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text("RUNNING"),
                      ),
                      const SizedBox(width: 20),
                      const Text(
                        "Signal: BUY EUR/USD",
                        style: TextStyle(color: Colors.green),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
            sectionTitle("Open Positions"),
            card(
              child: Column(
                children: [
                  position("EUR/USD", "BUY", "+\$35"),
                  position("GBP/USD", "SELL", "-\$12"),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Your existing helper widgets...
  Widget card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xff162033),
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }

  Widget sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget position(String pair, String type, String profit) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(pair, style: const TextStyle(color: Colors.white)),
      subtitle: Text(type, style: const TextStyle(color: Colors.grey)),
      trailing: Text(
        profit,
        style: TextStyle(
          color: profit.contains("+") ? Colors.green : Colors.red,
          fontSize: 18,
        ),
      ),
    );
  }
}
