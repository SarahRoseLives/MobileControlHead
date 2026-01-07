import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config.dart';

class AudioMetadataService extends ChangeNotifier {
  AppConfig? _appConfig;
  Timer? _timer;
  
  int? _talkgroupId;
  int? _sourceId;
  
  int? get talkgroupId => _talkgroupId;
  int? get sourceId => _sourceId;
  
  void start(AppConfig appConfig) {
    _appConfig = appConfig;
    _timer?.cancel();
    
    // Poll audio headers every 500ms for low latency
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _fetchAudioMetadata();
    });
    
    if (kDebugMode) {
      print('AudioMetadataService started');
    }
  }
  
  void stop() {
    _timer?.cancel();
    _talkgroupId = null;
    _sourceId = null;
    notifyListeners();
  }
  
  Future<void> _fetchAudioMetadata() async {
    if (_appConfig == null || _appConfig!.serverIp.isEmpty) return;
    
    try {
      // Make HEAD request to get headers without downloading audio
      final response = await http.head(
        Uri.parse(_appConfig!.audioUrl),
      ).timeout(const Duration(milliseconds: 300));
      
      if (response.statusCode == 200 || response.statusCode == 206) {
        final tgHeader = response.headers['x-talkgroup-id'];
        final srcHeader = response.headers['x-source-id'];
        
        final newTgid = tgHeader != null ? int.tryParse(tgHeader) : null;
        final newSrcid = srcHeader != null ? int.tryParse(srcHeader) : null;
        
        // Only notify if changed
        if (newTgid != _talkgroupId || newSrcid != _sourceId) {
          _talkgroupId = newTgid;
          _sourceId = newSrcid;
          
          if (kDebugMode && _talkgroupId != null) {
            print('Audio Metadata: TG=$_talkgroupId SRC=$_sourceId');
          }
          
          notifyListeners();
        }
      }
    } catch (e) {
      // Silently fail - metadata is optional
      if (kDebugMode) {
        print('Error fetching audio metadata: $e');
      }
    }
  }
  
  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
