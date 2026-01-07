// lib/screens/radioreference_settings_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../service/radioreference_service.dart';
import 'settings_category.dart';

class RadioReferenceSettingsScreen extends StatefulWidget {
  @override
  _RadioReferenceSettingsScreenState createState() =>
      _RadioReferenceSettingsScreenState();
}

class _RadioReferenceSettingsScreenState
    extends State<RadioReferenceSettingsScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _systemIdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Use addPostFrameCallback to access the provider safely in initState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final rrService =
          Provider.of<RadioReferenceService>(context, listen: false);
      _usernameController.text = rrService.username ?? '';
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _systemIdController.dispose();
    super.dispose();
  }

  void _handleSaveCredentials(RadioReferenceService rrService) async {
    final user = _usernameController.text;
    final pass = _passwordController.text;
    if (user.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Username and password cannot be empty.')),
      );
      return;
    }

    final success = await rrService.validateCredentials(user, pass);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success
            ? 'Credentials saved and verified!'
            : 'Login failed. Please check your credentials.'),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
    // Clear password field after attempt
    _passwordController.clear();
  }

  void _handleDownloadSystem(RadioReferenceService rrService) async {
    final systemId = int.tryParse(_systemIdController.text);
    if (systemId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid System ID.')));
      return;
    }

    await rrService.createSystemTsvFiles(systemId);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text(rrService.errorMessage ?? 'System files created successfully!'),
        backgroundColor:
            rrService.errorMessage == null ? Colors.green : Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Radio Reference'),
        backgroundColor: Colors.black,
      ),
      body: Consumer<RadioReferenceService>(
        builder: (context, rrService, child) {
          return ListView(
            padding: const EdgeInsets.all(8.0),
            children: [
              const SettingsCategory(
                title: 'Radio Reference Account',
                icon: Icons.cell_tower,
              ),
              _buildCredentialTile(
                'Username',
                _usernameController,
                Icons.person,
                false,
              ),
              _buildCredentialTile(
                'Password',
                _passwordController,
                Icons.lock,
                true,
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: rrService.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (rrService.isLoggedIn)
                            TextButton(
                              onPressed: () => rrService.logout(),
                              child: const Text('Logout',
                                  style: TextStyle(color: Colors.redAccent)),
                            ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () => _handleSaveCredentials(rrService),
                            icon: const Icon(Icons.save),
                            label: const Text('Save & Verify'),
                            style: ElevatedButton.styleFrom(
                                foregroundColor: Colors.black,
                                backgroundColor: Colors.cyanAccent),
                          ),
                        ],
                      ),
              ),
              if (rrService.isLoggedIn)
                ListTile(
                  leading:
                      const Icon(Icons.check_circle, color: Colors.greenAccent),
                  title: Text('Logged in as ${rrService.username}',
                      style: const TextStyle(color: Colors.white)),
                  dense: true,
                ),
              if (!rrService.isLoggedIn &&
                  rrService.errorMessage != null &&
                  !rrService.isLoading)
                ListTile(
                  leading: const Icon(Icons.error, color: Colors.redAccent),
                  title: Text(rrService.errorMessage!,
                      style: const TextStyle(color: Colors.redAccent)),
                  dense: true,
                ),
              const Divider(
                color: Colors.white24,
                height: 40,
                indent: 16,
                endIndent: 16,
              ),
              const SettingsCategory(
                title: 'System Downloader',
                icon: Icons.download,
              ),
              _buildCredentialTile(
                'System ID',
                _systemIdController,
                Icons.tag,
                false,
                keyboardType: TextInputType.number,
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: rrService.isLoggedIn
                        ? () => _handleDownloadSystem(rrService)
                        : null,
                    icon: const Icon(Icons.download_for_offline),
                    label: const Text('Download System Files'),
                    style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.black,
                        backgroundColor: Colors.cyanAccent),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCredentialTile(String label, TextEditingController controller,
      IconData icon, bool isPassword,
      {TextInputType keyboardType = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        style: const TextStyle(color: Colors.white),
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          prefixIcon: Icon(icon, color: Colors.white54),
          filled: true,
          fillColor: Colors.white.withOpacity(0.1),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}