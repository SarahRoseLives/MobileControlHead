import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config.dart';
import '../service/radioreference_service.dart';
import 'settings_category.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class RadioReferenceSettingsScreen extends StatefulWidget {
  @override
  _RadioReferenceSettingsScreenState createState() =>
      _RadioReferenceSettingsScreenState();
}

class _RadioReferenceSettingsScreenState
    extends State<RadioReferenceSettingsScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _zipcodeController = TextEditingController();
  final _systemIdController = TextEditingController();
  bool _isLoadingLocation = false;

  @override
  void initState() {
    super.initState();
    // Use addPostFrameCallback to access the provider safely in initState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final rrService =
          Provider.of<RadioReferenceService>(context, listen: false);
      _usernameController.text = rrService.username ?? '';
      _passwordController.text = rrService.password ?? '';
      _zipcodeController.text = rrService.currentZipcode ?? '';
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _zipcodeController.dispose();
    _systemIdController.dispose();
    super.dispose();
  }

  Future<void> _handleSaveCredentials(RadioReferenceService rrService) async {
    final user = _usernameController.text;
    final pass = _passwordController.text;
    if (user.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Username and password cannot be empty.')),
      );
      return;
    }

    final success = await rrService.validateCredentials(user, pass);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'Credentials saved and verified!'
              : rrService.errorMessage ?? 'Login failed. Please check your credentials.'),
          backgroundColor: success ? Colors.green : Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _handleDownloadSystem(RadioReferenceService rrService) async {
    final systemId = int.tryParse(_systemIdController.text);
    if (systemId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid System ID.')));
      return;
    }

    // Get backend URL from config
    final appConfig = Provider.of<AppConfig>(context, listen: false);
    final backendUrl = 'http://${appConfig.serverIp}:${AppConfig.serverPort}';

    await rrService.createSystemTsvFiles(systemId, backendUrl);

    if (mounted) {
      if (rrService.errorMessage == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('System files created on server! Now select a site.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(rrService.errorMessage!),
          backgroundColor: Colors.red,
        ));
      }
    }
  }
  
  Future<void> _handleUploadSite(RadioReferenceService rrService, int systemId, int siteId, String siteName) async {
    debugPrint("Select site clicked - System: $systemId, Site: $siteId, Name: $siteName");
    
    // Get backend URL from config
    final appConfig = Provider.of<AppConfig>(context, listen: false);
    final backendUrl = 'http://${appConfig.serverIp}:${AppConfig.serverPort}';
    
    debugPrint("Backend URL: $backendUrl");
    
    // Since files are already on server, just update the config to point to this trunk file
    final trunkFile = 'systems/$systemId/${systemId}_${siteId}_trunk.tsv';
    final success = await rrService.selectSiteOnServer(trunkFile, backendUrl);
    
    debugPrint("Select site result: $success");
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(success 
            ? 'Site "$siteName" selected and OP25 started!' 
            : rrService.errorMessage ?? 'Selection failed'),
        backgroundColor: success ? Colors.green : Colors.red,
        duration: const Duration(seconds: 5),
      ));
    }
  }

  Future<void> _handleDiscoverSystems(RadioReferenceService rrService) async {
    final zipcode = _zipcodeController.text;
    if (zipcode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a zip code.')));
      return;
    }

    final systems = await rrService.discoverSystemsByZipcode(zipcode);
    if (mounted) {
      if (systems != null && systems.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Found ${systems.length} system(s) in your area!'),
          backgroundColor: Colors.green,
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(rrService.errorMessage ?? 'No systems found.'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _getZipCodeFromGPS() async {
    setState(() {
      _isLoadingLocation = true;
    });

    try {
      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      if (permission == LocationPermission.denied || 
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permission denied'),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() {
          _isLoadingLocation = false;
        });
        return;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );

      // Reverse geocode to get address
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        final zipCode = placemark.postalCode;
        
        if (zipCode != null && zipCode.isNotEmpty) {
          setState(() {
            _zipcodeController.text = zipCode;
          });
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Found zip code: $zipCode'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Could not determine zip code from location'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error getting location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoadingLocation = false;
      });
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
                title: 'Discover Local Systems',
                icon: Icons.location_on,
              ),
              // Zip code field with GPS button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildCredentialTile(
                        'Zip Code',
                        _zipcodeController,
                        Icons.pin_drop,
                        false,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // GPS button
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      child: ElevatedButton(
                        onPressed: _isLoadingLocation ? null : _getZipCodeFromGPS,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.greenAccent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.all(16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _isLoadingLocation
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(Colors.black),
                                ),
                              )
                            : const Icon(Icons.my_location, size: 24),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: rrService.isLoggedIn
                        ? () => _handleDiscoverSystems(rrService)
                        : null,
                    icon: const Icon(Icons.search),
                    label: const Text('Search Systems'),
                    style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.black,
                        backgroundColor: Colors.cyanAccent),
                  ),
                ),
              ),
              if (rrService.availableSystems != null &&
                  rrService.availableSystems!.isNotEmpty)
                ...rrService.availableSystems!.map((system) {
                  return Card(
                    color: Colors.white.withOpacity(0.1),
                    margin: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 4.0),
                    child: ListTile(
                      leading: const Icon(Icons.radio, color: Colors.cyanAccent),
                      title: Text(
                        system['sName'] ?? 'Unknown System',
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        'ID: ${system['sid']}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      trailing: ElevatedButton(
                        onPressed: () {
                          _systemIdController.text = system['sid'].toString();
                          _handleDownloadSystem(rrService);
                        },
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.black,
                          backgroundColor: Colors.greenAccent,
                        ),
                        child: const Text('Download'),
                      ),
                    ),
                  );
                }).toList(),
              const Divider(
                color: Colors.white24,
                height: 40,
                indent: 16,
                endIndent: 16,
              ),
              const SettingsCategory(
                title: 'Manual System Download',
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
              if (rrService.downloadedSites != null &&
                  rrService.downloadedSites!.isNotEmpty) ...[
                const Divider(
                  color: Colors.white24,
                  height: 40,
                  indent: 16,
                  endIndent: 16,
                ),
                const SettingsCategory(
                  title: 'Select Site for OP25',
                  icon: Icons.radio,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    '${rrService.downloadedSites!.length} site(s) available',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
                ...rrService.downloadedSites!.map((site) {
                  final siteId = site['siteId'];
                  final siteName = site['siteDescr'] ?? 'Site $siteId';
                  final lat = site['lat']?.toString() ?? '';
                  final lon = site['lon']?.toString() ?? '';
                  
                  // Calculate distance if location is available
                  String? distance;
                  if (rrService.currentLat != null && 
                      rrService.currentLon != null &&
                      lat.isNotEmpty && lon.isNotEmpty) {
                    final siteLat = double.tryParse(lat);
                    final siteLon = double.tryParse(lon);
                    if (siteLat != null && siteLon != null) {
                      final dist = rrService.calculateDistance(
                        rrService.currentLat!, rrService.currentLon!, siteLat, siteLon);
                      distance = '${dist.toStringAsFixed(1)} km';
                    }
                  }
                  
                  return Card(
                    color: Colors.white.withOpacity(0.1),
                    margin: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 4.0),
                    child: ListTile(
                      leading: const Icon(Icons.cell_tower, color: Colors.cyanAccent),
                      title: Text(
                        siteName,
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Site ID: $siteId',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                          if (distance != null)
                            Text(
                              'Distance: $distance',
                              style: const TextStyle(color: Colors.greenAccent, fontSize: 12),
                            ),
                        ],
                      ),
                      trailing: ElevatedButton(
                        onPressed: rrService.isLoading 
                            ? null
                            : () async {
                                debugPrint("=== SELECT SITE BUTTON PRESSED ===");
                                debugPrint("System ID: ${rrService.downloadedSystemId}");
                                debugPrint("Site ID: $siteId");
                                debugPrint("Site Name: $siteName");
                                try {
                                  await _handleUploadSite(
                                      rrService, 
                                      rrService.downloadedSystemId!, 
                                      siteId, 
                                      siteName
                                    );
                                } catch (e, stackTrace) {
                                  debugPrint("ERROR in select site button handler: $e");
                                  debugPrint("Stack trace: $stackTrace");
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.black,
                          backgroundColor: Colors.greenAccent,
                        ),
                        child: const Text('Select'),
                      ),
                    ),
                  );
                }).toList(),
              ],
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