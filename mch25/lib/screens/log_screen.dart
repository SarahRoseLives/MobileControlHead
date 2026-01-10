import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mch25/service/op25_control_service.dart';
import 'package:provider/provider.dart';
import '../config.dart';

class LogScreen extends StatefulWidget {
  @override
  _LogScreenState createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  final List<String> _logLines = [];
  static const int _maxLines = 2000;
  StreamSubscription<String>? _streamSub;
  final ScrollController _scrollController = ScrollController();
  bool _atBottom = true;
  int _retryDelay = 1;
  bool _connected = false;
  http.Client? _client;
  bool _isConnecting = false;
  int _tapCount = 0;
  Timer? _tapTimer;
  AppConfig? _appConfig; // Store reference to avoid context in dispose

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Store reference and listen for config changes
    _appConfig = Provider.of<AppConfig>(context);
    _appConfig!.addListener(_handleConfigChange);
    // Initial connection attempt
    _handleConfigChange();
  }

  void _handleConfigChange() {
    // Debounce reconnect attempts
    if (_isConnecting) return;
    _isConnecting = true;
    _connectToLogStream();
    Future.delayed(Duration(seconds: 1), () {
      if (mounted) {
        _isConnecting = false;
      }
    });
  }

  @override
  void dispose() {
    _appConfig?.removeListener(_handleConfigChange);
    _streamSub?.cancel();
    _client?.close();
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _tapTimer?.cancel();
    super.dispose();
  }

  void _handleScroll() {
    if (_scrollController.hasClients) {
      _atBottom = _scrollController.offset >=
          _scrollController.position.maxScrollExtent - 30;
    }
  }

  TextStyle _getLogStyle(String log) {
    Color color;
    FontWeight fontWeight = FontWeight.normal;

    final lowerCaseLog = log.toLowerCase();

    if (lowerCaseLog.contains('error') ||
        lowerCaseLog.contains('errs 10') ||
        lowerCaseLog.contains('errs 15')) {
      color = Colors.redAccent;
      fontWeight = FontWeight.bold;
    } else if (lowerCaseLog.contains('timeout') ||
        lowerCaseLog.contains('err_rate') ||
        lowerCaseLog.contains('errs')) {
      color = Colors.orange;
    } else if (lowerCaseLog.contains('success') ||
        lowerCaseLog.contains('loaded') ||
        lowerCaseLog.contains('started')) {
      color = Colors.lightGreenAccent;
    } else if (lowerCaseLog.contains('freq') ||
        lowerCaseLog.contains('nac') ||
        lowerCaseLog.contains('tgid')) {
      color = Colors.cyan;
    } else if (lowerCaseLog.contains('[system]')) {
      color = Colors.blueGrey;
    } else if (lowerCaseLog.contains('http') ||
        lowerCaseLog.contains('audio.wav')) {
      color = Colors.purpleAccent;
    } else if (lowerCaseLog.contains('ambe') || lowerCaseLog.contains('imbe')) {
      color = const Color.fromARGB(255, 187, 187, 187);
    } else {
      color = Colors.white;
    }

    return TextStyle(
      color: color,
      fontFamily: 'monospace',
      fontSize: 12,
      fontWeight: fontWeight,
    );
  }

  void _connectToLogStream() async {
    if (!mounted) return;
    
    // Close any existing connection before starting a new one
    _streamSub?.cancel();
    _client?.close();

    if (_appConfig == null) return;
    
    final uri = Uri.parse(_appConfig!.logStreamUrl);
    _client = http.Client();

    try {
      final request = http.Request('GET', uri);
      final response = await _client!.send(request);

      if (mounted) {
        setState(() {
          _retryDelay = 1;
          _connected = true;
        });
      }

      _streamSub = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          if (line.startsWith('data: ')) {
            final logLine = line.substring(6);
            if (mounted) {
              setState(() {
                _logLines.add(logLine);
                if (_logLines.length > _maxLines) {
                  _logLines.removeRange(0, _logLines.length - _maxLines);
                }
              });

              if (_atBottom && _scrollController.hasClients) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _scrollController.hasClients) {
                    _scrollController
                        .jumpTo(_scrollController.position.maxScrollExtent);
                  }
                });
              }
            }
          }
        },
        onDone: () {
          if (mounted) _retryLogStream(aggressive: true);
        },
        onError: (e) {
          if (mounted) _retryLogStream(aggressive: true);
        },
      );
    } catch (e) {
      if (mounted) _retryLogStream(aggressive: true);
    }
  }

  void _retryLogStream({bool aggressive = false}) {
    if (!mounted) return;
    
    _streamSub?.cancel();
    _client?.close();

    if (mounted) {
      setState(() {
        _connected = false;
      });
    }

    int delay = aggressive ? 1 : _retryDelay;
    Future.delayed(Duration(seconds: delay), () {
      if (mounted) {
        if (!aggressive) {
          setState(() {
            _retryDelay = (_retryDelay * 2).clamp(1, 5);
          });
        }
        _connectToLogStream();
      }
    });
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _handleDoubleTap() {
    _scrollToBottom();
  }

  void _handleTap() {
    _tapCount += 1;

    if (_tapCount == 2) {
      _handleDoubleTap();
      _tapCount = 0;
      _tapTimer?.cancel();
    } else {
      _tapTimer?.cancel();
      _tapTimer = Timer(const Duration(milliseconds: 300), () {
        _tapCount = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch the control service to know if OP25 is running
    final controlService = context.watch<Op25ControlService>();
    final isOp25Running = controlService.isRunning;

    final showScrollButton = !_atBottom && _logLines.isNotEmpty;

    // If OP25 is not running, show a dedicated message.
    if (!isOp25Running) {
      return Scaffold(
        body: Container(
          decoration: AppTheme.gradientBackground,
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.power_off_outlined,
                        color: Colors.white54, size: 48),
                    const SizedBox(height: 16),
                    const Text(
                      "OP25 Not Running",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Start OP25 from the Settings screen to see logs.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    // If OP25 is running, show the standard log screen UI.
    return Scaffold(
      body: Container(
        decoration: AppTheme.gradientBackground,
        child: SafeArea(
          child: Column(
          children: [
            if (!_connected)
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.orange,
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      "Connecting to log stream in $_retryDelay seconds...",
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: GestureDetector(
                onDoubleTap: _handleDoubleTap,
                onTap: _handleTap,
                child: _logLines.isEmpty
                    ? Center(
                        child: Text(
                          _connected
                              ? "Waiting for logs..."
                              : "Connecting to log stream...",
                          style: const TextStyle(
                              color: Colors.white, fontSize: 18),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        itemCount: _logLines.length,
                        itemBuilder: (context, index) {
                          final log = _logLines[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            child: Text(
                              log,
                              style: _getLogStyle(log),
                            ),
                          );
                        },
                      ),
              ),
            ),
            if (showScrollButton)
              Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 16, bottom: 12),
                child: FloatingActionButton(
                  mini: true,
                  backgroundColor: Colors.grey[900],
                  child:
                      const Icon(Icons.arrow_downward, color: Colors.white),
                  onPressed: _scrollToBottom,
                  tooltip: "Scroll to bottom",
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}