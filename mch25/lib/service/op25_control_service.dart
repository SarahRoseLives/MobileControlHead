import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

class Op25ControlService extends ChangeNotifier {
  AppConfig? _appConfig;
  final http.Client _client = http.Client();

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  String? _error;
  String? get error => _error;

  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  void initialize(AppConfig config) {
    _appConfig = config;
    // Initial status check when the service is initialized
    getStatus();
  }

  Future<void> _updateStatus(bool running, {String? errorMsg}) async {
    _isRunning = running;
    _error = errorMsg;
    _isProcessing = false;
    notifyListeners();
  }

  Future<Map<String, dynamic>?> readTrunkConfig() async {
    if (_appConfig == null || _appConfig!.serverIp.isEmpty) return null;

    final url = Uri.parse('${_appConfig!.op25ControlApiUrl}api/trunk/read');
    try {
      final response = await _client.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        _error = 'Failed to read trunk config: ${response.statusCode}';
        notifyListeners();
        return null;
      }
    } catch (e) {
      _error = 'Error reading trunk config: ${e.toString()}';
      notifyListeners();
      return null;
    }
  }

  Future<Map<String, dynamic>?> readOp25Config() async {
    if (_appConfig == null || _appConfig!.serverIp.isEmpty) return null;

    final url = Uri.parse('${_appConfig!.op25ControlApiUrl}api/op25/config');
    try {
      final response = await _client.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        _error = 'Failed to read OP25 config: ${response.statusCode}';
        notifyListeners();
        return null;
      }
    } catch (e) {
      _error = 'Error reading OP25 config: ${e.toString()}';
      notifyListeners();
      return null;
    }
  }

  Future<bool> writeTrunkConfig(String sysname, String controlChannel) async {
    if (_appConfig == null || _appConfig!.serverIp.isEmpty) return false;

    _isProcessing = true;
    _error = null;
    notifyListeners();

    final url = Uri.parse('${_appConfig!.op25ControlApiUrl}api/trunk/write');
    final body = json.encode({
      'sysname': sysname,
      'control_channel': controlChannel,
    });
    debugPrint("Writing trunk config: $body");

    try {
      final response = await _client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 5));

      _isProcessing = false;
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          _error = null;
          notifyListeners();
          return true;
        } else {
          _error = data['error'] ?? 'Unknown error writing trunk config.';
          notifyListeners();
          return false;
        }
      } else {
        _error = 'Failed to write trunk config: ${response.statusCode}';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _isProcessing = false;
      _error = 'Error writing trunk config: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  Future<bool> writeOp25Config(String sdrDevice, String sampleRate, String lnaGain, String trunkFile) async {
    if (_appConfig == null || _appConfig!.serverIp.isEmpty) return false;

    _isProcessing = true;
    _error = null;
    notifyListeners();

    final url = Uri.parse('${_appConfig!.op25ControlApiUrl}api/op25/config');
    final body = json.encode({
      'sdr_device': sdrDevice,
      'sample_rate': sampleRate,
      'lna_gain': lnaGain,
      'trunk_file': trunkFile,
    });
    debugPrint("Writing OP25 config: $body");

    try {
      final response = await _client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 5));

      _isProcessing = false;
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['error'] == null) {
          _error = null;
          notifyListeners();
          return true;
        } else {
          _error = data['error'];
          notifyListeners();
          return false;
        }
      } else {
        _error = 'Failed to write OP25 config: ${response.statusCode}';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _isProcessing = false;
      _error = 'Error writing OP25 config: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  Future<void> getStatus() async {
    if (_appConfig == null || _appConfig!.serverIp.isEmpty) return;
    _isProcessing = true;
    notifyListeners();

    final url = Uri.parse('${_appConfig!.op25ControlApiUrl}api/op25/status');
    try {
      final response = await _client.get(url).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await _updateStatus(data['running'] ?? false, errorMsg: data['error']);
      } else {
        await _updateStatus(false, errorMsg: 'Status Error: ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Get Status Error: $e');
      }
      await _updateStatus(false, errorMsg: 'Failed to connect to server.');
    }
  }

  Future<bool> startOp25() async {
    if (_appConfig == null || _appConfig!.serverIp.isEmpty || _isProcessing) return false;

    _isProcessing = true;
    _error = null;
    notifyListeners();

    final url = Uri.parse('${_appConfig!.op25ControlApiUrl}api/op25/start');
    debugPrint("Attempting to start OP25 using backend config");

    try {
      final response = await _client.post(
        url,
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['started'] == true) {
          await _updateStatus(true);
          return true;
        } else {
          await _updateStatus(false, errorMsg: data['error'] ?? 'Failed to start');
          return false;
        }
      } else {
        await _updateStatus(false, errorMsg: 'Start Error: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      await _updateStatus(false, errorMsg: 'Start Error: ${e.toString()}');
      return false;
    }
  }

  @Deprecated('Use startOp25() instead - backend now manages config')
  Future<bool> startOp25WithFlags(List<String> flags) async {
    if (_appConfig == null || _appConfig!.serverIp.isEmpty || _isProcessing) return false;

    // MODIFIED: Removed the check for `_isRunning`. We always proceed to (re)start.

    _isProcessing = true;
    _error = null;
    notifyListeners();

    final url = Uri.parse('${_appConfig!.op25ControlApiUrl}api/op25/start');
    final body = json.encode({'flags': flags});
    debugPrint("Attempting to (re)start OP25 with flags: $body");

    try {
      final response = await _client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['started'] == true) {
          await _updateStatus(true);
          return true;
        } else {
          await _updateStatus(false, errorMsg: data['error'] ?? 'Failed to start');
          return false;
        }
      } else {
        await _updateStatus(false, errorMsg: 'Start Error: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      await _updateStatus(false, errorMsg: 'Start Error: ${e.toString()}');
      return false;
    }
  }

  Future<bool> stopOp25() async {
     if (_appConfig == null || _appConfig!.serverIp.isEmpty || _isProcessing) return false;
    await getStatus();
    if (!_isRunning) {
        _error = "OP25 is not running.";
        notifyListeners();
        return false;
    }

    _isProcessing = true;
    _error = null;
    notifyListeners();

    final url = Uri.parse('${_appConfig!.op25ControlApiUrl}api/op25/stop');
    try {
      final response = await _client.post(url).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['started'] == false && data['error'] == null) {
          await _updateStatus(false);
          return true;
        } else {
          // It failed to stop, so it's still running
          await _updateStatus(true, errorMsg: data['error'] ?? 'Failed to stop');
          return false;
        }
      } else {
        await _updateStatus(true, errorMsg: 'Stop Error: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      await _updateStatus(true, errorMsg: 'Stop Error: ${e.toString()}');
      return false;
    }
  }

  @Deprecated('No longer needed - backend manages config')
  static List<String>? buildFlagsFromPrefs(SharedPreferences prefs) {
    final device = prefs.getString('op25_device');
    final sampleRate = prefs.getInt('op25_samplerate');
    final gain = prefs.getString('op25_gain');

    if (device == null || sampleRate == null || gain == null) {
      return null;
    }

    // Per API doc, the 'rtl' argument is quoted.
    String deviceArg = (device == 'rtl') ? "'rtl'" : device;

    return [
      '--args', deviceArg,
      '-N', 'LNA:$gain',
      '-S', sampleRate.toString(),
      '-T', 'trunk.tsv',
      '-X',
      '-V',
      '-v', '9',
      '-l', 'http:0.0.0.0:8080', // <-- CORRECTED: Set rx.py to listen on 8080
      '-w',
      '-W', '127.0.0.1'
    ];
  }

  Future<void> attemptAutoStart() async {
    await Future.delayed(const Duration(seconds: 2)); // Wait for IP discovery

    await getStatus();
    if (_isRunning) {
      debugPrint("OP25 auto-start skipped: Process is already running.");
      return;
    }

    debugPrint("Attempting to auto-start OP25 with backend config...");
    await startOp25();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}