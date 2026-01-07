import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class SystemsSettingsScreen extends StatefulWidget {
  @override
  _SystemsSettingsScreenState createState() => _SystemsSettingsScreenState();
}

class _SystemsSettingsScreenState extends State<SystemsSettingsScreen> {
  List<SystemInfo> _systems = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSystems();
  }

  Future<void> _loadSystems() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final appConfig = Provider.of<AppConfig>(context, listen: false);
      final backendUrl = 'http://${appConfig.serverIp}:${AppConfig.serverPort}';
      
      final response = await http.get(Uri.parse('$backendUrl/api/systems/list'));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final List<dynamic> systemsJson = data['systems'] ?? [];
          setState(() {
            _systems = systemsJson.map((s) => SystemInfo.fromJson(s)).toList();
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = 'Failed to load systems';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Server error: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading systems: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _selectSite(String systemId, String siteId, String description) async {
    try {
      final appConfig = Provider.of<AppConfig>(context, listen: false);
      final backendUrl = 'http://${appConfig.serverIp}:${AppConfig.serverPort}';
      
      // Update OP25 config with selected trunk file
      final trunkFile = 'systems/$systemId/${systemId}_${siteId}_trunk.tsv';
      
      final configResponse = await http.post(
        Uri.parse('$backendUrl/api/op25/config'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'trunk_file': trunkFile}),
      );
      
      if (configResponse.statusCode != 200) {
        throw Exception('Failed to update config');
      }
      
      // Start OP25
      final startResponse = await http.post(
        Uri.parse('$backendUrl/api/op25/start'),
      );
      
      if (startResponse.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Selected $description and started OP25!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else {
        throw Exception('Failed to start OP25');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Downloaded Systems'),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSystems,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, color: Colors.red, size: 48),
                      SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadSystems,
                        child: Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _systems.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inbox, color: Colors.white54, size: 64),
                          SizedBox(height: 16),
                          Text(
                            'No systems downloaded yet',
                            style: TextStyle(color: Colors.white70, fontSize: 16),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Use Radio Reference to download systems',
                            style: TextStyle(color: Colors.white54, fontSize: 14),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(8.0),
                      itemCount: _systems.length,
                      itemBuilder: (context, index) {
                        final system = _systems[index];
                        return _buildSystemCard(system);
                      },
                    ),
    );
  }

  Widget _buildSystemCard(SystemInfo system) {
    return Card(
      color: Colors.white.withOpacity(0.1),
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      child: ExpansionTile(
        leading: const Icon(Icons.cell_tower, color: Colors.cyanAccent),
        title: Text(
          'System ${system.systemId}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          '${system.sites.length} site(s) available',
          style: const TextStyle(color: Colors.white70),
        ),
        children: system.sites.map((site) {
          return ListTile(
            leading: const Icon(Icons.location_on, color: Colors.greenAccent, size: 20),
            title: Text(
              site.description,
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              'Site ID: ${site.siteId}',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            trailing: ElevatedButton(
              onPressed: () => _selectSite(
                system.systemId,
                site.siteId.toString(),
                site.description,
              ),
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.black,
                backgroundColor: Colors.cyanAccent,
              ),
              child: const Text('Select'),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class SystemInfo {
  final String systemId;
  final List<SiteInfo> sites;

  SystemInfo({required this.systemId, required this.sites});

  factory SystemInfo.fromJson(Map<String, dynamic> json) {
    final List<dynamic> sitesJson = json['sites'] ?? [];
    return SystemInfo(
      systemId: json['system_id'] ?? '',
      sites: sitesJson.map((s) => SiteInfo.fromJson(s)).toList(),
    );
  }
}

class SiteInfo {
  final int siteId;
  final String description;
  final String latitude;
  final String longitude;

  SiteInfo({
    required this.siteId,
    required this.description,
    required this.latitude,
    required this.longitude,
  });

  factory SiteInfo.fromJson(Map<String, dynamic> json) {
    return SiteInfo(
      siteId: json['site_id'] ?? 0,
      description: json['description'] ?? 'Unknown',
      latitude: json['latitude'] ?? '0',
      longitude: json['longitude'] ?? '0',
    );
  }
}
