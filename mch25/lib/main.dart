import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

import 'config.dart';
import 'service/mdns_scanner_service.dart';
import 'screens/radio_scanner_screen.dart';
import 'wizard/onboarding_wizard.dart';
import 'audio/udp_audio_player_service.dart';
import 'audio/audio_metadata_service.dart';
import 'service/op25_api_service.dart';
import 'service/op25_control_service.dart';
import 'service/radioreference_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // --- Instantiate services ---
  final appConfig = AppConfig();
  final mDNScanner = mDNScannerService();
  final audioService = AudioStreamPlayerService();
  final audioMetadataService = AudioMetadataService();
  final op25ApiService = Op25ApiService();
  final op25ControlService = Op25ControlService();

  // Start discovery
  mDNScanner.startDiscovery(appConfig);

  // Set up periodic rediscovery
  Timer.periodic(const Duration(seconds: 30), (_) {
    mDNScanner.restartDiscovery(appConfig);
  });

  // Start audio service so it listens for IP changes
  audioService.start(appConfig);
  
  // Start audio metadata service
  audioMetadataService.start(appConfig);

  // Start OP25 API service so it polls for data
  op25ApiService.start(appConfig);

  // Initialize the OP25 Control Service
  op25ControlService.initialize(appConfig);

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]).then((_) {
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: appConfig),
          ChangeNotifierProvider.value(value: mDNScanner),
          Provider.value(value: audioService),
          ChangeNotifierProvider.value(value: audioMetadataService),
          ChangeNotifierProvider.value(value: op25ApiService),
          ChangeNotifierProvider.value(value: op25ControlService),
          ChangeNotifierProvider(create: (_) => RadioReferenceService()),
        ],
        child: MobileRadioScannerApp(),
      ),
    );
  });
}

class MobileRadioScannerApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mobile Control Head 25',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF181818),
        textTheme: ThemeData.dark().textTheme.copyWith(
              bodyLarge: const TextStyle(fontFamily: 'Segment7'),
              bodyMedium: const TextStyle(fontFamily: 'Segment7'),
            ),
      ),
      debugShowCheckedModeBanner: false,
      home: MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  bool _showWizard = false;
  bool _prefsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadPrefsAndAutoStart();
  }

  Future<void> _loadPrefsAndAutoStart() async {
    final prefs = await SharedPreferences.getInstance();
    final wizardCompleted = prefs.getBool('wizardCompleted') ?? false;

    if (!wizardCompleted) {
      // First run, show wizard
      setState(() {
        _showWizard = true;
        _prefsLoaded = true;
      });
    } else {
      // Not first run, show main screen and attempt to auto-start OP25
      setState(() {
        _showWizard = false;
        _prefsLoaded = true;
      });
      // Use the provided Op25ControlService to attempt auto-start
      // We add a post-frame callback to ensure the context is ready
      WidgetsBinding.instance.addPostFrameCallback((_) {
         Provider.of<Op25ControlService>(context, listen: false).attemptAutoStart();
      });
    }
  }

  void _completeWizard() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('wizardCompleted', true);
    setState(() {
      _showWizard = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_prefsLoaded) {
      return MaterialApp(home: Container(color: Colors.black));
    }
    return _showWizard
        ? OnboardingWizard(onSkip: _completeWizard, onDone: _completeWizard)
        : RadioScannerScreen();
  }
}