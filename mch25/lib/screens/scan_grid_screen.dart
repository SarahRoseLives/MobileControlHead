import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class Talkgroup {
  final String name;
  final String id;
  bool enabled;

  Talkgroup({
    required this.name,
    required this.id,
    this.enabled = true, // Default to enabled
  });

  factory Talkgroup.fromJson(Map<String, dynamic> json) {
    return Talkgroup(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unknown',
      enabled: true,
    );
  }
}

class ScanGridScreen extends StatefulWidget {
  @override
  _ScanGridScreenState createState() => _ScanGridScreenState();
}

class _ScanGridScreenState extends State<ScanGridScreen> {
  List<Talkgroup> _allTalkgroups = [];
  bool _isLoading = false;
  String? _errorMessage;
  String? _systemId;
  bool _pendingChanges = false;
  int _currentPage = 0;
  final int _itemsPerPage = 9;

  @override
  void initState() {
    super.initState();
    _loadTalkgroups();
  }

  Future<void> _loadTalkgroups() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final appConfig = Provider.of<AppConfig>(context, listen: false);
      final backendUrl = 'http://${appConfig.serverIp}:${AppConfig.serverPort}';
      
      final response = await http.get(Uri.parse('$backendUrl/api/talkgroups/list'));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final List<dynamic> talkgroupsJson = data['talkgroups'] ?? [];
          setState(() {
            _systemId = data['system_id'];
            _allTalkgroups = talkgroupsJson.map((tg) => Talkgroup.fromJson(tg)).toList();
            _isLoading = false;
            _currentPage = 0;
          });
        } else {
          setState(() {
            _errorMessage = data['error'] ?? 'Failed to load talkgroups';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Server error: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading talkgroups: $e';
        _isLoading = false;
      });
    }
  }

  List<Talkgroup> get _currentPageTalkgroups {
    final start = _currentPage * _itemsPerPage;
    final end = (start + _itemsPerPage).clamp(0, _allTalkgroups.length);
    if (start >= _allTalkgroups.length) return [];
    return _allTalkgroups.sublist(start, end);
  }

  int get _totalPages {
    return (_allTalkgroups.length / _itemsPerPage).ceil();
  }

  Future<void> _applyChanges() async {
    // Get enabled talkgroups
    final enabledTalkgroups = _allTalkgroups.where((tg) => tg.enabled).toList();
    
    // TODO: Send whitelist to backend and restart OP25
    
    setState(() {
      _pendingChanges = false;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Applied ${enabledTalkgroups.length} talkgroups. Restart OP25 to apply.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _toggleAll(bool enable) {
    setState(() {
      for (var tg in _allTalkgroups) {
        tg.enabled = enable;
      }
      _pendingChanges = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFF232323),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF232323),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Colors.red, size: 48),
              SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadTalkgroups,
                child: Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_allTalkgroups.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFF232323),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.inbox, color: Colors.white54, size: 64),
              SizedBox(height: 16),
              Text(
                'No system configured',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
              SizedBox(height: 8),
              Text(
                'Select a system to load talkgroups',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    final talkgroups = _currentPageTalkgroups;

    return Scaffold(
      backgroundColor: const Color(0xFF232323),
      body: SafeArea(
        child: Column(
          children: [
            // Top bar with system info and controls
            Container(
              color: const Color(0xFF313131),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  // System info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'System $_systemId',
                          style: TextStyle(
                            color: Colors.cyanAccent,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${_allTalkgroups.where((tg) => tg.enabled).length}/${_allTalkgroups.length} enabled',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  // Control buttons
                  TextButton(
                    onPressed: () => _toggleAll(true),
                    child: Text('Enable All', style: TextStyle(color: Colors.greenAccent)),
                  ),
                  TextButton(
                    onPressed: () => _toggleAll(false),
                    child: Text('Disable All', style: TextStyle(color: Colors.redAccent)),
                  ),
                  IconButton(
                    icon: Icon(Icons.refresh, color: Colors.white70),
                    onPressed: _loadTalkgroups,
                  ),
                ],
              ),
            ),
            // Page navigation
            Container(
              color: const Color(0xFF313131),
              height: 48,
              child: Stack(
                children: [
                  // Page tabs
                  ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _totalPages,
                    itemBuilder: (context, i) {
                      final start = i * _itemsPerPage + 1;
                      final end = ((i + 1) * _itemsPerPage).clamp(0, _allTalkgroups.length);
                      return InkWell(
                        onTap: () => setState(() => _currentPage = i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: _currentPage == i
                                    ? Colors.orange
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                            color: _currentPage == i
                                ? const Color(0xFF444444)
                                : const Color(0xFF313131),
                          ),
                          child: Center(
                            child: Text(
                              '$start-$end',
                              style: TextStyle(
                                color: _currentPage == i
                                    ? Colors.orange
                                    : Colors.white70,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  // Pending Changes Button
                  if (_pendingChanges)
                    Positioned(
                      right: 8,
                      top: 6,
                      bottom: 6,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.black,
                          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          elevation: 2,
                        ),
                        onPressed: _applyChanges,
                        child: Text(
                          "Apply Changes",
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // 3x3 grid of talkgroups (9 per page)
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  double gridSpacing = 6.0;
                  double totalSpacing = gridSpacing * 2; // 3 rows: 2 spaces
                  double cardHeight = (constraints.maxHeight - totalSpacing) / 3;

                  return GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(6.0),
                    itemCount: talkgroups.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: gridSpacing,
                      mainAxisSpacing: gridSpacing,
                      childAspectRatio: constraints.maxWidth / (3 * cardHeight),
                    ),
                    itemBuilder: (context, i) {
                      final tg = talkgroups[i];
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            tg.enabled = !tg.enabled;
                            _pendingChanges = true;
                          });
                        },
                        child: Card(
                          color: tg.enabled
                              ? Colors.green[600]
                              : const Color(0xFF424242),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          elevation: tg.enabled ? 3 : 1,
                          child: Padding(
                            padding: const EdgeInsets.all(6.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: Text(
                                    tg.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      color: Colors.white,
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  "${tg.id}",
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 9),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}