// lib/audio/udp_audio_player_service.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:audioplayers/audioplayers.dart' as audioplayers;

import '../config.dart';

// CORRECTED: The abstract class is now the main public class.
abstract class AudioStreamPlayerService {
  bool get isPlaying;
  void start(AppConfig appConfig);
  void stop();

  // CORRECTED: The factory constructor is now correctly part of the abstract class.
  factory AudioStreamPlayerService() {
    if (Platform.isLinux) {
      debugPrint("Audio Service: Using Linux implementation (audioplayers).");
      return _LinuxAudioPlayer();
    } else {
      debugPrint("Audio Service: Using default implementation (just_audio).");
      return _JustAudioPlayer();
    }
  }
}

// `_JustAudioPlayer` now correctly implements the main service class.
class _JustAudioPlayer implements AudioStreamPlayerService {
  final _player = just_audio.AudioPlayer();
  bool _playing = false;
  @override
  bool get isPlaying => _playing;

  StreamSubscription<just_audio.PlayerState>? _playerSub;
  VoidCallback? _configListener;
  String? _lastIp;
  AppConfig? _appConfig;
  int _reconnectDelayMs = 1000;

  @override
  void start(AppConfig appConfig) {
    if (_playing) return;
    _playing = true;
    _appConfig = appConfig;
    _listenConfig(appConfig);
    _startAggressiveReconnect(appConfig);
  }

  @override
  void stop() {
    _playing = false;
    _playerSub?.cancel();
    _player.stop();
    if (_configListener != null && _appConfig != null) {
      _appConfig!.removeListener(_configListener!);
      _configListener = null;
    }
  }

  void _listenConfig(AppConfig appConfig) {
    if (_configListener != null) return;
    _lastIp = appConfig.serverIp;
    _configListener = () {
      if (_lastIp != appConfig.serverIp) {
        _lastIp = appConfig.serverIp;
        if (_playing) {
          _startAggressiveReconnect(appConfig);
        }
      }
    };
    appConfig.addListener(_configListener!);
  }

  void _startAggressiveReconnect(AppConfig appConfig) async {
    _playerSub?.cancel();
    while (_playing) {
      try {
        await _player.setUrl(appConfig.audioUrl);
        await _player.play();
        _reconnectDelayMs = 1000;

        _playerSub = _player.playerStateStream.listen((state) async {
          if (!_playing) return;
          if (state.processingState == just_audio.ProcessingState.completed) {
            await _forceReconnect(appConfig);
          }
        });
        await _player.playingStream.firstWhere((playing) => !playing && _playing);
        if (_playing) await _forceReconnect(appConfig);
      } catch (e) {
        debugPrint('Audio Player Error (just_audio): $e');
        await Future.delayed(Duration(milliseconds: _reconnectDelayMs));
        _reconnectDelayMs = (_reconnectDelayMs * 2).clamp(1000, 8000);
      }
    }
  }

  Future<void> _forceReconnect(AppConfig appConfig) async {
    try {
      await _player.stop();
    } catch (_) {}
    if (_playing) {
      await Future.delayed(Duration(milliseconds: 250));
      await _player.setUrl(appConfig.audioUrl);
      await _player.play();
    }
  }
}

// `_LinuxAudioPlayer` also correctly implements the main service class.
class _LinuxAudioPlayer implements AudioStreamPlayerService {
  final _player = audioplayers.AudioPlayer();
  bool _playing = false;
  @override
  bool get isPlaying => _playing;

  StreamSubscription? _playerCompleteSub;
  StreamSubscription? _playerErrorSub;
  VoidCallback? _configListener;
  String? _lastIp;
  AppConfig? _appConfig;

  _LinuxAudioPlayer() {
    _player.setReleaseMode(audioplayers.ReleaseMode.stop);
  }

  @override
  void start(AppConfig appConfig) {
    if (_playing) return;
    _playing = true;
    _appConfig = appConfig;
    _listenToEvents();
    _listenConfig(appConfig);
    _playStream(appConfig.audioUrl);
  }

  @override
  void stop() {
    _playing = false;
    _playerCompleteSub?.cancel();
    _playerErrorSub?.cancel();
    _player.stop();
    if (_configListener != null && _appConfig != null) {
      _appConfig!.removeListener(_configListener!);
      _configListener = null;
    }
  }

  void _listenConfig(AppConfig appConfig) {
    if (_configListener != null) return;
    _lastIp = appConfig.serverIp;
    _configListener = () {
      if (_lastIp != appConfig.serverIp) {
        _lastIp = appConfig.serverIp;
        if (_playing) {
          _playStream(appConfig.audioUrl);
        }
      }
    };
    appConfig.addListener(_configListener!);
  }

  void _listenToEvents() {
    _playerCompleteSub = _player.onPlayerComplete.listen((event) {
      if (_playing && _appConfig != null) {
        debugPrint("Linux audio stream completed. Reconnecting...");
        _playStream(_appConfig!.audioUrl);
      }
    });

    // CORRECTED: The onLog listener receives a String, not a complex object.
    _playerErrorSub = _player.onLog.listen((logMessage) {
       if (_playing && logMessage.contains('error')) {
         debugPrint("Audio Player Error (audioplayers): $logMessage");
       }
    });
  }

  Future<void> _playStream(String url) async {
    if (!_playing) return;
    try {
      await _player.setSourceUrl(url);
      await _player.resume();
    } catch (e) {
      debugPrint("Error playing stream with audioplayers: $e");
    }
  }
}