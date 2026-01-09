import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'dart:math' show cos, sqrt, asin;

class SystemsSettingsScreen extends StatefulWidget {
  @override
  _SystemsSettingsScreenState createState() => _SystemsSettingsScreenState();
}

class _SystemsSettingsScreenState extends State<SystemsSettingsScreen> {
  List<SystemInfo> _systems = [];
  bool _isLoading = false;
  String? _errorMessage;
  Position? _userLocation;
  bool _locationPermissionGranted = false;

  @override
  void initState() {
    super.initState();
    _checkLocationPermission();
    _loadSystems();
  }

  Future<void> _checkLocationPermission() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      if (permission == LocationPermission.whileInUse || 
          permission == LocationPermission.always) {
        _locationPermissionGranted = true;
        _userLocation = await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 5),
          ),
        );
        setState(() {});
      }
    } catch (e) {
      print('Error getting location: $e');
    }
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    // Haversine formula to calculate distance between two coordinates
    const p = 0.017453292519943295; // Pi/180
    final a = 0.5 - cos((lat2 - lat1) * p) / 2 + 
              cos(lat1 * p) * cos(lat2 * p) * 
              (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)); // 2 * R; R = 6371 km
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
            
            // Sort sites by distance if location is available
            if (_userLocation != null && _locationPermissionGranted) {
              for (var system in _systems) {
                system.sites.sort((a, b) {
                  final distA = _calculateDistance(
                    _userLocation!.latitude, 
                    _userLocation!.longitude,
                    double.tryParse(a.latitude) ?? 0,
                    double.tryParse(a.longitude) ?? 0,
                  );
                  final distB = _calculateDistance(
                    _userLocation!.latitude, 
                    _userLocation!.longitude,
                    double.tryParse(b.latitude) ?? 0,
                    double.tryParse(b.longitude) ?? 0,
                  );
                  return distA.compareTo(distB);
                });
              }
            }
            
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
          String distanceText = '';
          if (_userLocation != null && _locationPermissionGranted) {
            final distance = _calculateDistance(
              _userLocation!.latitude,
              _userLocation!.longitude,
              double.tryParse(site.latitude) ?? 0,
              double.tryParse(site.longitude) ?? 0,
            );
            if (distance < 1) {
              distanceText = ' • ${(distance * 1000).toStringAsFixed(0)}m away';
            } else {
              distanceText = ' • ${distance.toStringAsFixed(1)}km away';
            }
          }
          
          return ListTile(
            leading: const Icon(Icons.location_on, color: Colors.greenAccent, size: 20),
            title: Text(
              site.description,
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              'Site ID: ${site.siteId}$distanceText',
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
