import 'package:flutter/material.dart';

import '../services/storage_service.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool? isLoggedIn;
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _checkAuthWithTimeout();
  }

  Future<void> _checkAuthWithTimeout() async {
    // Timeout future
    final timeout = Future.delayed(
      const Duration(seconds: 10),
    );

    // Auth check future
    final authCheck = _checkAuth();

    // Whichever completes first wins
    await Future.any([timeout, authCheck]);

    if (!_resolved && mounted) {
      setState(() {
        isLoggedIn = isLoggedIn ?? false;
        _resolved = true;
      });
    }
  }

  Future<void> _checkAuth() async {
    try {
      final token = await StorageService.getAccessToken();

      if (!mounted) return;

      setState(() {
        isLoggedIn = token != null;
        _resolved = true;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isLoggedIn = false;
        _resolved = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoggedIn == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return isLoggedIn!
        ? const HomeScreen()
        : const LoginScreen();
  }
}