import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config.dart';

// Model for active talkgroup from logs
class ActiveTalkgroup {
  final int tgid;
  final String tag;
  final int srcid;
  final String frequency;
  final DateTime lastUpdate;

  ActiveTalkgroup({
    required this.tgid,
    required this.tag,
    required this.srcid,
    required this.frequency,
    required this.lastUpdate,
  });
}

// Service to parse OP25 logs and extract talkgroup information
class LogParserService extends ChangeNotifier {
  AppConfig? _appConfig;
  StreamSubscription<String>? _streamSub;
  http.Client? _client;
  bool _isConnected = false;
  bool _isConnecting = false;

  ActiveTalkgroup? _activeTalkgroup;
  ActiveTalkgroup? get activeTalkgroup => _activeTalkgroup;

  String _controlChannel = '';
  String get controlChannel => _controlChannel;

  bool get isConnected => _isConnected;

  void initialize(AppConfig config) {
    _appConfig = config;
    _appConfig!.addListener(_handleConfigChange);
    _connectToLogStream();
  }

  void _handleConfigChange() {
    if (_isConnecting) return;
    _isConnecting = true;
    _connectToLogStream();
    Future.delayed(const Duration(seconds: 1), () => _isConnecting = false);
  }

  void _connectToLogStream() async {
    _streamSub?.cancel();
    _client?.close();

    if (_appConfig == null || _appConfig!.serverIp.isEmpty) {
      _isConnected = false;
      notifyListeners();
      return;
    }

    final uri = Uri.parse(_appConfig!.logStreamUrl);
    _client = http.Client();

    try {
      final request = http.Request('GET', uri);
      final response = await _client!.send(request);

      _isConnected = true;
      notifyListeners();

      _streamSub = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          if (line.startsWith('data: ')) {
            final logLine = line.substring(6);
            _parseLogLine(logLine);
          }
        },
        onDone: () => _reconnect(),
        onError: (e) => _reconnect(),
      );
    } catch (e) {
      _reconnect();
    }
  }

  void _reconnect() {
    _isConnected = false;
    _streamSub?.cancel();
    _client?.close();
    notifyListeners();

    Future.delayed(const Duration(seconds: 2), () {
      _connectToLogStream();
    });
  }

  void _parseLogLine(String line) {
    // OP25 log patterns to extract talkgroup info:
    // Example: "clear tgid=10001, freq=161.950000, slot=0"
    // Example: "voice update tgid=12345 src=54321 freq=851.0125"
    
    try {
      // Pattern 1: tgid=(...) freq=(...) - most common format
      final tgMatch = RegExp(r'tgid[=:]?\s*(\d+)', caseSensitive: false).firstMatch(line);
      final freqMatch = RegExp(r'freq[=:]?\s*([\d.]+)', caseSensitive: false).firstMatch(line);
      
      // Pattern 2: src=(...) or source=(...)
      final srcMatch = RegExp(r'(?:src|source)[=:]?\s*(\d+)', caseSensitive: false).firstMatch(line);

      if (tgMatch != null) {
        final tgid = int.parse(tgMatch.group(1)!);
        final srcid = srcMatch != null ? int.parse(srcMatch.group(1)!) : 0;
        final freq = freqMatch?.group(1) ?? '';

        // Only update if it's a new call or source changed
        if (_activeTalkgroup == null || 
            _activeTalkgroup!.tgid != tgid || 
            (_activeTalkgroup!.srcid != srcid && srcid > 0)) {
          _activeTalkgroup = ActiveTalkgroup(
            tgid: tgid,
            tag: 'Talkgroup $tgid', // Default tag, could be enhanced with tag lookup
            srcid: srcid,
            frequency: freq,
            lastUpdate: DateTime.now(),
          );
          if (kDebugMode) {
            print('LogParser: Active TG=$tgid SRC=$srcid FREQ=$freq');
          }
          notifyListeners();
        } else {
          // Update timestamp for existing call
          _activeTalkgroup = ActiveTalkgroup(
            tgid: _activeTalkgroup!.tgid,
            tag: _activeTalkgroup!.tag,
            srcid: _activeTalkgroup!.srcid,
            frequency: _activeTalkgroup!.frequency,
            lastUpdate: DateTime.now(),
          );
        }
      }

      // Pattern 3: Extract control channel
      // Example: "control channel: 851.5125 MHz"
      // Example: "Tracking: 851512500 Hz"
      final ccMatch = RegExp(r'(?:control|tracking).*?([\d.]+)\s*(?:MHz|Hz)?', caseSensitive: false).firstMatch(line);
      if (ccMatch != null) {
        var ccFreq = ccMatch.group(1)!;
        // Convert Hz to MHz if needed
        if (line.toLowerCase().contains('hz') && !line.toLowerCase().contains('mhz')) {
          final hz = double.tryParse(ccFreq);
          if (hz != null && hz > 100000) {
            ccFreq = (hz / 1000000).toStringAsFixed(6);
          }
        }
        if (_controlChannel != ccFreq) {
          _controlChannel = ccFreq;
          if (kDebugMode) {
            print('LogParser: Control Channel=$ccFreq MHz');
          }
          notifyListeners();
        }
      }

      // Clear active talkgroup after timeout (e.g., 5 seconds of no updates)
      _checkTalkgroupTimeout();

    } catch (e) {
      if (kDebugMode) {
        print('Error parsing log line: $e');
      }
    }
  }

  Timer? _timeoutTimer;
  void _checkTalkgroupTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 5), () {
      if (_activeTalkgroup != null) {
        final age = DateTime.now().difference(_activeTalkgroup!.lastUpdate);
        if (age.inSeconds > 5) {
          _activeTalkgroup = null;
          notifyListeners();
        }
      }
    });
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _streamSub?.cancel();
    _client?.close();
    _appConfig?.removeListener(_handleConfigChange);
    super.dispose();
  }
}
