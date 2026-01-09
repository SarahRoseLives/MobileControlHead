import 'dart:async';
import 'dart:convert';
import 'dart:math' show cos, sqrt, asin;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../config.dart';

class GpsSiteHoppingService extends ChangeNotifier {
  Timer? _locationTimer;
  Position? _currentPosition;
  String? _currentSystemId;
  String? _currentSiteId;
  List<SiteData> _availableSites = [];
  bool _isEnabled = false;
  bool _isHopping = false;
  final AppConfig _appConfig;
  
  // Distance threshold in kilometers to trigger a site change
  static const double hopThresholdKm = 5.0;
  
  // Location check interval
  static const Duration checkInterval = Duration(seconds: 30);

  GpsSiteHoppingService(this._appConfig);

  bool get isEnabled => _isEnabled;
  bool get isHopping => _isHopping;
  String? get currentSiteId => _currentSiteId;
  Position? get currentPosition => _currentPosition;

  Future<void> startHopping(String systemId) async {
    if (_isEnabled) return;
    
    _currentSystemId = systemId;
    _isEnabled = true;
    
    // Load available sites for this system
    await _loadSystemSites();
    
    // Check location permission
    final permission = await _checkLocationPermission();
    if (!permission) {
      debugPrint('GPS Site Hopping: Location permission denied');
      _isEnabled = false;
      notifyListeners();
      return;
    }
    
    // Start periodic location checks
    _locationTimer = Timer.periodic(checkInterval, (_) => _checkLocationAndHop());
    
    // Do initial hop
    await _checkLocationAndHop();
    
    notifyListeners();
  }

  Future<void> stopHopping() async {
    _locationTimer?.cancel();
    _locationTimer = null;
    _isEnabled = false;
    _isHopping = false;
    _currentSystemId = null;
    _currentSiteId = null;
    _availableSites.clear();
    notifyListeners();
  }

  Future<bool> _checkLocationPermission() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      return permission == LocationPermission.whileInUse || 
             permission == LocationPermission.always;
    } catch (e) {
      debugPrint('GPS Site Hopping: Error checking permission: $e');
      return false;
    }
  }

  Future<void> _loadSystemSites() async {
    if (_currentSystemId == null) return;
    
    try {
      final backendUrl = 'http://${_appConfig.serverIp}:${AppConfig.serverPort}';
      final response = await http.get(
        Uri.parse('$backendUrl/api/systems/list')
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final List<dynamic> systems = data['systems'] ?? [];
          
          for (var system in systems) {
            if (system['system_id'] == _currentSystemId) {
              final List<dynamic> sites = system['sites'] ?? [];
              _availableSites = sites.map((s) => SiteData.fromJson(s)).toList();
              debugPrint('GPS Site Hopping: Loaded ${_availableSites.length} sites');
              break;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('GPS Site Hopping: Error loading sites: $e');
    }
  }

  Future<void> _checkLocationAndHop() async {
    if (!_isEnabled || _availableSites.isEmpty) return;
    
    try {
      _isHopping = true;
      notifyListeners();
      
      // Get current location
      _currentPosition = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
      
      // Find closest site
      SiteData? closestSite;
      double closestDistance = double.infinity;
      
      for (var site in _availableSites) {
        final distance = _calculateDistance(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          double.tryParse(site.latitude) ?? 0,
          double.tryParse(site.longitude) ?? 0,
        );
        
        if (distance < closestDistance) {
          closestDistance = distance;
          closestSite = site;
        }
      }
      
      // Check if we should hop to a different site
      if (closestSite != null) {
        final shouldHop = _currentSiteId == null || 
                         (_currentSiteId != closestSite.siteId.toString() && 
                          closestDistance < hopThresholdKm);
        
        if (shouldHop) {
          debugPrint('GPS Site Hopping: Switching to site ${closestSite.siteId} '
                    '(${closestSite.description}) - ${closestDistance.toStringAsFixed(1)}km away');
          await _hopToSite(closestSite);
        } else {
          debugPrint('GPS Site Hopping: Current site $_currentSiteId is still optimal '
                    '(closest: ${closestDistance.toStringAsFixed(1)}km)');
        }
      }
      
      _isHopping = false;
      notifyListeners();
      
    } catch (e) {
      debugPrint('GPS Site Hopping: Error checking location: $e');
      _isHopping = false;
      notifyListeners();
    }
  }

  Future<void> _hopToSite(SiteData site) async {
    if (_currentSystemId == null) return;
    
    try {
      final backendUrl = 'http://${_appConfig.serverIp}:${AppConfig.serverPort}';
      final trunkFile = 'systems/$_currentSystemId/${_currentSystemId}_${site.siteId}_trunk.tsv';
      
      // Update OP25 config with new trunk file
      final configResponse = await http.post(
        Uri.parse('$backendUrl/api/op25/config'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'trunk_file': trunkFile}),
      );
      
      if (configResponse.statusCode != 200) {
        throw Exception('Failed to update config');
      }
      
      // Restart OP25 with new site
      final startResponse = await http.post(
        Uri.parse('$backendUrl/api/op25/start'),
      );
      
      if (startResponse.statusCode == 200) {
        _currentSiteId = site.siteId.toString();
        debugPrint('GPS Site Hopping: Successfully hopped to site ${site.siteId}');
      } else {
        throw Exception('Failed to start OP25');
      }
    } catch (e) {
      debugPrint('GPS Site Hopping: Error hopping to site: $e');
    }
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    // Haversine formula
    const p = 0.017453292519943295; // Pi/180
    final a = 0.5 - cos((lat2 - lat1) * p) / 2 + 
              cos(lat1 * p) * cos(lat2 * p) * 
              (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)); // 2 * R; R = 6371 km
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    super.dispose();
  }
}

class SiteData {
  final int siteId;
  final String description;
  final String latitude;
  final String longitude;

  SiteData({
    required this.siteId,
    required this.description,
    required this.latitude,
    required this.longitude,
  });

  factory SiteData.fromJson(Map<String, dynamic> json) {
    return SiteData(
      siteId: json['site_id'] ?? 0,
      description: json['description'] ?? 'Unknown',
      latitude: json['latitude'] ?? '0',
      longitude: json['longitude'] ?? '0',
    );
  }
}
