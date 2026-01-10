import 'package:flutter/material.dart';
import '../config.dart';
import 'radioreference_settings_screen.dart';
import 'about_settings.dart';
import 'manualop25config_settings.dart'; // Import the new Manual OP25 Config screen
import 'systems_settings_screen.dart';
import 'talkgroup_management_screen.dart';

class SettingsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: AppTheme.gradientBackground,
        child: ListView(
          children: [
          _sectionHeader('Radio Reference'),
          _buildSettingsItem(
            context,
            icon: Icons.cell_tower,
            title: 'Radio Reference',
            subtitle: 'Manage credentials and download system data.',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => RadioReferenceSettingsScreen(),
                ),
              );
            },
          ),
          _buildSettingsItem(
            context,
            icon: Icons.list_alt,
            title: 'Systems',
            subtitle: 'View and select downloaded systems.',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SystemsSettingsScreen(),
                ),
              );
            },
          ),
          _buildSettingsItem(
            context,
            icon: Icons.speaker_phone,
            title: 'Talkgroups',
            subtitle: 'Enable/disable talkgroups (whitelist/blacklist).',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TalkgroupManagementScreen(),
                ),
              );
            },
          ),
          _sectionHeader('Manual OP25 Configuration'),
          _buildSettingsItem(
            context,
            icon: Icons.settings_input_antenna,
            title: 'Manual OP25 Config',
            subtitle: 'Configure SDR, sample rate, gain, system and channels.',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ManualOP25ConfigSettingsScreen(),
                ),
              );
            },
          ),
          _sectionHeader('Appearance'),
          _buildSettingsItem(
            context,
            icon: Icons.palette,
            title: 'Appearance',
            subtitle: 'Customize the look and feel of the app.',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Appearance settings coming soon!')),
              );
            },
          ),
          _sectionHeader('About'),
          _buildSettingsItem(
            context,
            icon: Icons.info_outline,
            title: 'About',
            subtitle: 'View app information and licenses.',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AboutSettingsScreen(),
                ),
              );
            },
          ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.cyanAccent,
          fontSize: 15,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSettingsItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      leading: Icon(icon, color: Colors.cyanAccent, size: 28),
      title: Text(
        title,
        style: const TextStyle(
            color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Colors.white70, fontSize: 14),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.white54),
      onTap: onTap,
    );
  }
}