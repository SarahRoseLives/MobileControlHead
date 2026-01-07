import 'package:flutter/material.dart';

class AboutSettingsScreen extends StatelessWidget {
  const AboutSettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('About'),
        backgroundColor: Colors.black,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // About the App
          _buildSectionTitle('About the App'),
          const SizedBox(height: 8),
          const Text(
            'This app allows you to remotely control and extend the features of OP25. ',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 24),

          // Licenses
          _buildSectionTitle('Licenses'),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'View Licenses',
              style: TextStyle(color: Colors.cyanAccent, fontSize: 16),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white54),
            onTap: () {
              showLicensePage(
                context: context,
                applicationName: 'MCH25',
                applicationVersion: '1.0.0',
                applicationLegalese: '© 2025 SarahRose AD8NT',
                applicationIcon: const Icon(Icons.info_outline, size: 40, color: Colors.cyanAccent),
              );
            },
          ),
          const SizedBox(height: 24),

          // About Me
          _buildSectionTitle('About the Developer'),
          const SizedBox(height: 8),
          const Text(
            'Hi! I\'m Sarah Rose, an independent developer passionate about radio, '
            'public safety, and open source projects. You can connect with me on GitHub as SarahRoseLives.',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.cyanAccent,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}