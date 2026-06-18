import 'package:flutter/material.dart';
import 'auth_gate.dart';
import 'services/api_client.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ApiClient.init();
  runApp(const TradingApp());
}

class TradingApp extends StatelessWidget {
  const TradingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Forex AI Trader",
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xff0b1220),
      ),
      home: const AuthGate(),
    );
  }
}