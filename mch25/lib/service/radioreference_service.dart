import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

class RadioReferenceService extends ChangeNotifier {
  final _secureStorage = const FlutterSecureStorage();
  
  String? username;
  String? password;
  bool isLoggedIn = false;
  bool isLoading = false;
  String? errorMessage;
  
  // Location and system discovery
  String? currentZipcode;
  double? currentLat;
  double? currentLon;
  Map<String, dynamic>? countyInfo;
  List<Map<String, dynamic>>? availableSystems;
  
  // Downloaded system info
  int? downloadedSystemId;
  List<Map<String, dynamic>>? downloadedSites;
  String? systemFolderPath;

  RadioReferenceService({this.username, this.password}) {
    _loadCredentials();
  }

  // Load saved credentials from secure storage
  Future<void> _loadCredentials() async {
    try {
      username = await _secureStorage.read(key: 'rr_username');
      password = await _secureStorage.read(key: 'rr_password');
      if (username != null && password != null) {
        isLoggedIn = true;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading credentials: $e');
    }
  }

  // Save credentials to secure storage
  Future<void> _saveCredentials(String user, String pass) async {
    try {
      await _secureStorage.write(key: 'rr_username', value: user);
      await _secureStorage.write(key: 'rr_password', value: pass);
    } catch (e) {
      debugPrint('Error saving credentials: $e');
    }
  }

  // Clear credentials from secure storage
  Future<void> _clearCredentials() async {
    try {
      await _secureStorage.delete(key: 'rr_username');
      await _secureStorage.delete(key: 'rr_password');
    } catch (e) {
      debugPrint('Error clearing credentials: $e');
    }
  }

  Future<bool> validateCredentials(String user, String pass) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    // Try a simple API call to validate credentials
    try {
      debugPrint("RadioReference: Validating credentials for user: $user");
      final authInfo = _buildAuthInfo(user, pass);
      final wsdlUrl = "http://api.radioreference.com/soap2/?wsdl&v=latest&s=rpc";
      // Test: getZipcodeInfo for a known valid US zip (should not error if credentials are good)
      debugPrint("RadioReference: Sending SOAP request to validate credentials...");
      final response = await _soapRequest(
        wsdlUrl,
        'getZipcodeInfo',
        {'zipcode': 90210, 'authInfo': authInfo}
      );
      debugPrint("RadioReference: Response received: $response");
      
      // Check if we got a valid response (any data means credentials are good)
      if (response != null && response.isNotEmpty) {
        // Successful API call means credentials are valid
        username = user;
        password = pass;
        isLoggedIn = true;
        isLoading = false;
        errorMessage = null;
        
        // Save credentials to secure storage
        await _saveCredentials(user, pass);
        
        debugPrint("RadioReference: Login successful and credentials saved!");
        notifyListeners();
        return true;
      } else {
        errorMessage = "API login failed - no data returned";
        isLoggedIn = false;
        isLoading = false;
        debugPrint("RadioReference: Login failed - $errorMessage");
        notifyListeners();
        return false;
      }
    } catch (e, stackTrace) {
      errorMessage = "Login error: $e";
      isLoggedIn = false;
      isLoading = false;
      debugPrint("RadioReference: Exception during login: $e");
      debugPrint("RadioReference: Stack trace: $stackTrace");
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    username = null;
    password = null;
    isLoggedIn = false;
    errorMessage = null;
    
    // Clear saved credentials
    await _clearCredentials();
    
    notifyListeners();
  }

  Map<String, dynamic> _buildAuthInfo(String user, String pass) {
    return {
      "appKey": utf8.decode(base64Decode('Mjg4MDExNjM=')),
      "username": user,
      "password": pass,
      "version": "latest",
      "style": "rpc"
    };
  }

  /// Helper: Build SOAP Envelope
  String _buildSoapEnvelope(String method, Map<String, dynamic> params) {
    final authInfo = params['authInfo'];
    final otherParams = Map<String, dynamic>.from(params)..remove('authInfo');
    final paramXml = otherParams.entries.map((e) => '<${e.key}>${e.value}</${e.key}>').join('\n            ');
    final authXml = '''<authInfo>
              <appKey>${authInfo['appKey']}</appKey>
              <username>${authInfo['username']}</username>
              <password>${authInfo['password']}</password>
              <version>${authInfo['version']}</version>
              <style>${authInfo['style']}</style>
            </authInfo>''';
    
    return '''<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
  <soap:Body>
    <$method xmlns="http://api.radioreference.com/soap2/">
      $paramXml
      $authXml
    </$method>
  </soap:Body>
</soap:Envelope>''';
  }

  /// Helper: Make SOAP Request
  Future<Map<String, dynamic>?> _soapRequest(
    String wsdlUrl,
    String method,
    Map<String, dynamic> params
  ) async {
    final endpoint = wsdlUrl.replaceFirst('?wsdl&v=latest&s=rpc', '');
    final envelope = _buildSoapEnvelope(method, Map.of(params));
    final headers = {
      'Content-Type': 'text/xml; charset=utf-8',
      'SOAPAction': 'http://api.radioreference.com/soap2/$method'
    };
    
    debugPrint("RadioReference SOAP Request:");
    debugPrint("  Endpoint: $endpoint");
    debugPrint("  Method: $method");
    debugPrint("  Envelope: $envelope");
    
    final response = await http.post(
      Uri.parse(endpoint),
      headers: headers,
      body: envelope,
    );
    
    debugPrint("RadioReference SOAP Response:");
    debugPrint("  Status: ${response.statusCode}");
    debugPrint("  Body: ${response.body}");
    
    if (response.statusCode == 200) {
      // Parse XML for result node
      final document = XmlDocument.parse(response.body);
      
      // Try multiple possible response node names
      var resultNode = document.findAllElements('${method}Result').firstOrNull;
      if (resultNode == null) {
        resultNode = document.findAllElements('${method}Response').firstOrNull;
      }
      if (resultNode == null) {
        resultNode = document.findAllElements('return').firstOrNull;
      }
      
      if (resultNode != null) {
        debugPrint("  Result node found: ${resultNode.name}");
        
        // If it's a 'return' node or Response node, parse as XML directly
        final result = _xmlToMap(resultNode);
        debugPrint("  Parsed result: $result");
        return result;
      } else {
        debugPrint("  No result node found in response");
      }
    } else {
      debugPrint("  HTTP error: ${response.statusCode}");
    }
    return null;
  }

  // Helper to convert XML node to Map<String, dynamic>
  Map<String, dynamic> _xmlToMap(XmlElement node) {
    final map = <String, dynamic>{};
    
    // Group children by name to detect arrays
    final childGroups = <String, List<XmlElement>>{};
    for (final child in node.children.whereType<XmlElement>()) {
      final name = child.name.local;
      childGroups.putIfAbsent(name, () => []).add(child);
    }
    
    // Process each group
    for (final entry in childGroups.entries) {
      final name = entry.key;
      final elements = entry.value;
      
      if (elements.length == 1) {
        // Single element
        final child = elements.first;
        if (child.children.length == 1 && child.firstChild is XmlText) {
          map[name] = child.text;
        } else {
          map[name] = _xmlToMap(child);
        }
      } else {
        // Multiple elements with same name = array
        map[name] = elements.map((child) {
          if (child.children.length == 1 && child.firstChild is XmlText) {
            return child.text;
          } else {
            return _xmlToMap(child);
          }
        }).toList();
      }
    }
    
    return map;
  }

  /// Get Zipcode Info (returns county ID)
  Future<Map<String, dynamic>?> getZipcodeInfo(String zip) async {
    if (!(isLoggedIn && username != null && password != null)) {
      errorMessage = "Please login first.";
      notifyListeners();
      return null;
    }
    final wsdlUrl = "http://api.radioreference.com/soap2/?wsdl&v=latest&s=rpc";
    final authInfo = _buildAuthInfo(username!, password!);
    final result = await _soapRequest(wsdlUrl, 'getZipcodeInfo', {
      'zipcode': int.parse(zip),
      'authInfo': authInfo,
    });
    
    if (result != null) {
      currentZipcode = zip;
      currentLat = result['lat'] != null ? double.tryParse(result['lat'].toString()) : null;
      currentLon = result['lon'] != null ? double.tryParse(result['lon'].toString()) : null;
      notifyListeners();
    }
    
    return result;
  }
  
  /// Discover systems by zipcode - gets county info with list of trunked systems
  Future<List<Map<String, dynamic>>?> discoverSystemsByZipcode(String zip) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    
    try {
      // First get zipcode info to get county ID
      final zipInfo = await getZipcodeInfo(zip);
      if (zipInfo == null || zipInfo['ctid'] == null) {
        errorMessage = "Could not find county for zipcode $zip";
        isLoading = false;
        notifyListeners();
        return null;
      }
      
      // Get county info which includes trunked systems list
      countyInfo = await getCountyInfo(zipInfo['ctid'].toString());
      if (countyInfo == null) {
        errorMessage = "Could not fetch county information";
        isLoading = false;
        notifyListeners();
        return null;
      }
      
      // Extract trunked systems list
      availableSystems = [];
      if (countyInfo!['trsList'] != null) {
        final trsList = countyInfo!['trsList'];
        if (trsList is List) {
          availableSystems = trsList.cast<Map<String, dynamic>>();
        } else if (trsList is Map) {
          availableSystems = [Map<String, dynamic>.from(trsList)];
        }
      }
      
      isLoading = false;
      notifyListeners();
      debugPrint("Found ${availableSystems?.length ?? 0} systems in county");
      return availableSystems;
    } catch (e) {
      errorMessage = "Error discovering systems: $e";
      isLoading = false;
      notifyListeners();
      return null;
    }
  }
  
  /// Find nearest site for a system based on current location
  Future<Map<String, dynamic>?> findNearestSite(int systemId) async {
    if (currentLat == null || currentLon == null) {
      errorMessage = "Location not available";
      return null;
    }
    
    final sites = await getTrsSites(systemId);
    if (sites == null || sites.isEmpty) {
      return null;
    }
    
    // Calculate distance to each site and find nearest
    Map<String, dynamic>? nearestSite;
    double? minDistance;
    
    for (final site in sites) {
      final siteLat = site['lat'] != null ? double.tryParse(site['lat'].toString()) : null;
      final siteLon = site['lon'] != null ? double.tryParse(site['lon'].toString()) : null;
      
      if (siteLat != null && siteLon != null) {
        final distance = _calculateDistance(currentLat!, currentLon!, siteLat, siteLon);
        if (minDistance == null || distance < minDistance) {
          minDistance = distance;
          nearestSite = site;
        }
      }
    }
    
    return nearestSite;
  }
  
  /// Calculate distance between two lat/lon points (Haversine formula) - public
  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    return _calculateDistance(lat1, lon1, lat2, lon2);
  }
  
  /// Calculate distance between two lat/lon points (Haversine formula)
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0; // Earth's radius in km
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = 
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }
  
  double _toRadians(double degrees) => degrees * (math.pi / 180);

  /// Get County Info (returns trunked system list)
  Future<Map<String, dynamic>?> getCountyInfo(String countyId) async {
    if (!(isLoggedIn && username != null && password != null)) {
      errorMessage = "Please login first.";
      notifyListeners();
      return null;
    }
    final wsdlUrl = "http://api.radioreference.com/soap2/?wsdl&v=latest&s=rpc";
    final authInfo = _buildAuthInfo(username!, password!);
    final result = await _soapRequest(wsdlUrl, 'getCountyInfo', {
      'ctid': countyId,
      'authInfo': authInfo,
    });
    
    debugPrint("getCountyInfo result keys: ${result?.keys}");
    
    // Handle nested item structure in trsList
    if (result != null && result['trsList'] != null) {
      final trsList = result['trsList'];
      if (trsList is Map && trsList['item'] != null) {
        // Unwrap the item array
        result['trsList'] = trsList['item'];
      }
    }
    
    return result;
  }

  /// Get Trunked System Sites (returns list of sites)
  Future<List<Map<String, dynamic>>?> getTrsSites(int systemId) async {
    if (!(isLoggedIn && username != null && password != null)) {
      errorMessage = "Please login first.";
      notifyListeners();
      return null;
    }
    final wsdlUrl = "http://api.radioreference.com/soap2/?wsdl&v=latest&s=rpc";
    final authInfo = _buildAuthInfo(username!, password!);
    final result = await _soapRequest(wsdlUrl, 'getTrsSites', {
      'sid': systemId,
      'authInfo': authInfo,
    });
    
    debugPrint("getTrsSites result: $result");
    
    if (result != null) {
      // Response has 'item' array inside 'return' node
      if (result['item'] != null) {
        if (result['item'] is List) {
          return List<Map<String, dynamic>>.from(result['item']);
        } else {
          return [Map<String, dynamic>.from(result['item'])];
        }
      }
      // Fallback: check for 'site' (old format)
      if (result['site'] != null) {
        if (result['site'] is List) {
          return List<Map<String, dynamic>>.from(result['site']);
        } else {
          return [Map<String, dynamic>.from(result['site'])];
        }
      }
    }
    return null;
  }

  /// Get Trunked System Talkgroups (list, only unencrypted)
  Future<List<List<dynamic>>?> getTrsTalkgroups(int systemId) async {
    if (!(isLoggedIn && username != null && password != null)) {
      errorMessage = "Please login first.";
      notifyListeners();
      return null;
    }
    final wsdlUrl = "http://api.radioreference.com/soap2/?wsdl&v=latest&s=rpc";
    final authInfo = _buildAuthInfo(username!, password!);
    final result = await _soapRequest(wsdlUrl, 'getTrsTalkgroups', {
      'sid': systemId,
      'start': 0,
      'limit': 0,
      'filter': 0,
      'authInfo': authInfo,
    });
    
    debugPrint("getTrsTalkgroups result keys: ${result?.keys}");
    
    if (result != null) {
      final talkgroups = <List<dynamic>>[];
      
      // Response has 'item' array inside 'return' node
      dynamic tgData = result['item'] ?? result['talkgroup'];
      
      if (tgData is List) {
        for (final tg in tgData) {
          // Filter unencrypted only
          final encValue = tg['enc'];
          if (encValue == '0' || encValue == 0) {
            talkgroups.add([tg['tgDec'], tg['tgAlpha']]);
          }
        }
      } else if (tgData != null) {
        // Single talkgroup
        final encValue = tgData['enc'];
        if (encValue == '0' || encValue == 0) {
          talkgroups.add([tgData['tgDec'], tgData['tgAlpha']]);
        }
      }
      
      debugPrint("Parsed ${talkgroups.length} unencrypted talkgroups");
      return talkgroups;
    }
    return null;
  }
  
  /// Create system TSV files on the SERVER (Go backend)
  Future<void> createSystemTsvFiles(int systemId, String backendUrl) async {
    debugPrint("=== createSystemTsvFiles (SERVER-SIDE) called ===");
    debugPrint("systemId: $systemId, backendUrl: $backendUrl");
    
    if (!(isLoggedIn && username != null && password != null)) {
      errorMessage = "Please login first.";
      debugPrint("ERROR: $errorMessage");
      notifyListeners();
      return;
    }
    
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    
    try {
      final uri = Uri.parse('$backendUrl/api/radioreference/create-system');
      debugPrint("Sending request to: $uri");
      
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
          'system_id': systemId,
        }),
      );
      
      debugPrint("Response status: ${response.statusCode}");
      debugPrint("Response body: ${response.body}");
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true) {
          downloadedSystemId = systemId;
          
          // Now fetch the list of sites from the server
          await _fetchSitesFromServer(systemId, backendUrl);
          
          isLoading = false;
          errorMessage = null;
          notifyListeners();
          debugPrint("System created successfully on server!");
        } else {
          errorMessage = data['error'] ?? 'Failed to create system';
          debugPrint("ERROR: $errorMessage");
          isLoading = false;
          notifyListeners();
        }
      } else {
        errorMessage = "Server error: ${response.statusCode}";
        debugPrint("ERROR: $errorMessage");
        isLoading = false;
        notifyListeners();
      }
    } catch (e, stackTrace) {
      errorMessage = "Error creating system: $e";
      debugPrint("ERROR: $errorMessage");
      debugPrint("Stack trace: $stackTrace");
      isLoading = false;
      notifyListeners();
    }
  }
  
  /// Fetch list of sites from server
  Future<void> _fetchSitesFromServer(int systemId, String backendUrl) async {
    try {
      // Build URL with optional lat/lon parameters
      var uri = Uri.parse('$backendUrl/api/radioreference/list-sites');
      final queryParams = <String, String>{'system_id': systemId.toString()};
      
      // Add location if available
      if (currentLat != null && currentLon != null) {
        queryParams['lat'] = currentLat.toString();
        queryParams['lon'] = currentLon.toString();
        debugPrint("Fetching sites with location: $currentLat, $currentLon");
      }
      
      uri = uri.replace(queryParameters: queryParams);
      debugPrint("Fetching sites from: $uri");
      
      final response = await http.get(uri);
      debugPrint("Sites response status: ${response.statusCode}");
      debugPrint("Sites response body: ${response.body}");
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true) {
          // Convert server sites to our format
          downloadedSites = [];
          for (final site in (data['sites'] as List)) {
            downloadedSites!.add({
              'siteId': site['site_id'],
              'siteDescr': site['description'] ?? 'Site ${site['site_id']}',
              'lat': site['latitude'] ?? '',
              'lon': site['longitude'] ?? '',
              'trunkFile': site['trunk_file'] ?? '',
            });
          }
          
          debugPrint("Fetched ${downloadedSites!.length} sites from server (sorted by distance)");
        } else {
          debugPrint("Failed to fetch sites: ${data['error']}");
        }
      }
    } catch (e) {
      debugPrint("Error fetching sites from server: $e");
    }
  }
  
  /// Select a site on the server (update OP25 config to use this trunk file and start OP25)
  Future<bool> selectSiteOnServer(String trunkFilePath, String backendUrl) async {
    debugPrint("=== selectSiteOnServer called ===");
    debugPrint("trunkFilePath: $trunkFilePath, backendUrl: $backendUrl");
    
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    
    try {
      // Step 1: Update config
      final configUri = Uri.parse('$backendUrl/api/op25/config');
      debugPrint("Updating config at: $configUri");
      
      final configResponse = await http.post(
        configUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'trunk_file': trunkFilePath,
        }),
      );
      
      debugPrint("Config response status: ${configResponse.statusCode}");
      debugPrint("Config response body: ${configResponse.body}");
      
      if (configResponse.statusCode != 200) {
        errorMessage = "Server error: ${configResponse.statusCode}";
        debugPrint("ERROR: $errorMessage");
        isLoading = false;
        notifyListeners();
        return false;
      }
      
      final configData = jsonDecode(configResponse.body);
      if (configData['error'] != null) {
        errorMessage = configData['error'];
        debugPrint("ERROR: $errorMessage");
        isLoading = false;
        notifyListeners();
        return false;
      }
      
      debugPrint("Config updated successfully!");
      
      // Step 2: Start OP25
      final startUri = Uri.parse('$backendUrl/api/op25/start');
      debugPrint("Starting OP25 at: $startUri");
      
      final startResponse = await http.post(
        startUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({}),
      );
      
      debugPrint("Start response status: ${startResponse.statusCode}");
      debugPrint("Start response body: ${startResponse.body}");
      
      if (startResponse.statusCode == 200) {
        final startData = jsonDecode(startResponse.body);
        
        if (startData['started'] == true) {
          isLoading = false;
          errorMessage = null;
          notifyListeners();
          debugPrint("Site selected and OP25 started successfully!");
          return true;
        } else {
          errorMessage = startData['error'] ?? 'Failed to start OP25';
          debugPrint("ERROR: $errorMessage");
          isLoading = false;
          notifyListeners();
          return false;
        }
      } else {
        errorMessage = "Failed to start OP25: ${startResponse.statusCode}";
        debugPrint("ERROR: $errorMessage");
        isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e, stackTrace) {
      errorMessage = "Error selecting site: $e";
      debugPrint("ERROR: $errorMessage");
      debugPrint("Stack trace: $stackTrace");
      isLoading = false;
      notifyListeners();
      return false;
    }
  }
}