// lib/audio/udp_audio_player_service.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../config.dart';

abstract class AudioStreamPlayerService {
  bool get isPlaying;
  void start(AppConfig appConfig);
  void stop();

  factory AudioStreamPlayerService() {
    debugPrint("Audio Service: Using native Android AudioTrack player");
    return _NativeAudioPlayer();
  }
}

class _NativeAudioPlayer implements AudioStreamPlayerService {
  static const platform = MethodChannel('com.example.mch25/audio');
  
  bool _playing = false;
  @override
  bool get isPlaying => _playing;

  VoidCallback? _configListener;
  String? _lastIp;
  AppConfig? _appConfig;

  @override
  void start(AppConfig appConfig) {
    debugPrint("NativeAudioPlayer: start() called");
    if (_playing) {
      debugPrint("NativeAudioPlayer: Already playing");
      return;
    }
    _playing = true;
    _appConfig = appConfig;
    _listenConfig(appConfig);
    _startStream(appConfig.audioUrl);
  }

  @override
  void stop() {
    debugPrint("NativeAudioPlayer: stop() called");
    _playing = false;
    if (_configListener != null && _appConfig != null) {
      _appConfig!.removeListener(_configListener!);
      _configListener = null;
    }
    platform.invokeMethod('stopStream');
  }

  void _listenConfig(AppConfig appConfig) {
    if (_configListener != null) return;
    _lastIp = appConfig.serverIp;
    _configListener = () {
      if (_lastIp != appConfig.serverIp) {
        _lastIp = appConfig.serverIp;
        if (_playing) {
          _startStream(appConfig.audioUrl);
        }
      }
    };
    appConfig.addListener(_configListener!);
  }

  Future<void> _startStream(String url) async {
    if (!_playing) return;
    
    if (url.isEmpty || url.startsWith('http://:')) {
      debugPrint("NativeAudio: Waiting for server discovery");
      Future.delayed(const Duration(seconds: 2), () {
        if (_playing && _appConfig != null) _startStream(_appConfig!.audioUrl);
      });
      return;
    }
    
    try {
      debugPrint("NativeAudio: Starting stream: $url");
      await platform.invokeMethod('startStream', {'url': url});
      debugPrint("NativeAudio: Stream started successfully");
    } catch (e) {
      debugPrint("NativeAudio: Error starting stream: $e");
      Future.delayed(const Duration(seconds: 2), () {
        if (_playing && _appConfig != null) _startStream(_appConfig!.audioUrl);
      });
    }
  }
}
