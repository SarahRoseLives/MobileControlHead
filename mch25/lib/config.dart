import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Shared UI constants
class AppTheme {
  // Consistent gradient background for all screens
  static const gradientBackground = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF1a1a1a),
        Color(0xFF202020),
        Color(0xFF2a2a2a),
      ],
    ),
  );
}

class AppConfig extends ChangeNotifier {
  String _serverIp = "192.168.1.240";
  static const int serverPort = 9000;      // For Go server (Control API, Audio, Log Stream)
  static const int op25DataPort = 8080;      // For rx.py's internal data API

  String get serverIp => _serverIp;

  void updateServerIp(String newIp) {
    if (_serverIp != newIp) {
      _serverIp = newIp;
      notifyListeners();
    }
  }

  // URLs for services on the main server (port 9000)
  String get audioUrl => "http://$_serverIp:$serverPort/audio.wav";  // WAV stream for audio players
  String get logStreamUrl => "http://$_serverIp:$serverPort/stream";
  String get op25ControlApiUrl => "http://$_serverIp:$serverPort/"; // For start/stop/status

  // URL for the data polling service, which talks directly to rx.py (port 8080)
  String get op25DataApiUrl => "http://$_serverIp:$op25DataPort/";
}