import 'package:flutter/material.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Mock state variables for toggles
  bool _oneClickTrading = false;
  bool _biometricsEnabled = true;
  bool _executionSounds = true;
  bool _pushNotifications = true;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: const Color(0xff0f172a),
        appBar: AppBar(
          backgroundColor: const Color(0xff0f172a),
          elevation: 0,
          title: const Text("Settings", style: TextStyle(fontWeight: FontWeight.bold)),
          centerTitle: false,
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(vertical: 10),
          children: [
            _buildSectionHeader("TRADING PREFERENCES"),
            _buildSwitchTile(
              title: "One-Click Trading",
              subtitle: "Execute market orders without confirmation",
              value: _oneClickTrading,
              onChanged: (v) => setState(() => _oneClickTrading = v),
              icon: Icons.speed,
              activeColor: Colors.redAccent, // Red because it's a risky setting
            ),
            _buildListTile(
              title: "Default Lot Size",
              subtitle: "0.10",
              icon: Icons.candlestick_chart,
              onTap: () {
                // Show dialog to enter default lot
              },
            ),
            _buildListTile(
              title: "Default SL / TP",
              subtitle: "Not set",
              icon: Icons.security,
              onTap: () {},
            ),

            const SizedBox(height: 10),
            _buildSectionHeader("SECURITY"),
            _buildSwitchTile(
              title: "Biometric Lock",
              subtitle: "Require FaceID/TouchID to open app",
              value: _biometricsEnabled,
              onChanged: (v) => setState(() => _biometricsEnabled = v),
              icon: Icons.fingerprint,
              activeColor: Colors.blueAccent,
            ),
            _buildListTile(
              title: "Connected Account",
              subtitle: "MT5 • 8392011 (Demo Server)",
              icon: Icons.account_balance,
              onTap: () {},
            ),

            const SizedBox(height: 10),
            _buildSectionHeader("NOTIFICATIONS"),
            _buildSwitchTile(
              title: "Execution Sounds",
              subtitle: "Play sound when order fills",
              value: _executionSounds,
              onChanged: (v) => setState(() => _executionSounds = v),
              icon: Icons.volume_up,
              activeColor: Colors.blueAccent,
            ),
            _buildSwitchTile(
              title: "Push Notifications",
              subtitle: "Margin calls and price alerts",
              value: _pushNotifications,
              onChanged: (v) => setState(() => _pushNotifications = v),
              icon: Icons.notifications_active,
              activeColor: Colors.blueAccent,
            ),

            const SizedBox(height: 30),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
                  foregroundColor: Colors.redAccent,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  // Handle logout
                },
                child: const Text("Disconnect Account", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, bottom: 10, top: 20),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildListTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xff162033),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.white70, size: 20),
      ),
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 13)),
      trailing: const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
      onTap: onTap,
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required IconData icon,
    required Color activeColor,
  }) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      secondary: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xff162033),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.white70, size: 20),
      ),
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 13)),
      value: value,
      activeThumbColor: activeColor,
      onChanged: onChanged,
    );
  }
}