import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config.dart';

class TalkgroupService extends ChangeNotifier {
  Map<String, String> _talkgroupNames = {}; // tgid -> name
  Map<String, TalkgroupMetadata> _talkgroupMetadata = {}; // tgid -> metadata
  Set<String> _whitelist = {}; // enabled talkgroups
  Set<String> _blacklist = {}; // disabled talkgroups
  String? _currentSystemId;
  Timer? _refreshTimer;
  
  String getTalkgroupName(int tgid) {
    final name = _talkgroupNames[tgid.toString()];
    return name ?? 'Unknown';
  }
  
  String? getTalkgroupCategory(int tgid) {
    final metadata = _talkgroupMetadata[tgid.toString()];
    return metadata?.category;
  }
  
  String? getTalkgroupTag(int tgid) {
    final metadata = _talkgroupMetadata[tgid.toString()];
    return metadata?.tag;
  }
  
  Set<String> get allCategories {
    final categories = <String>{};
    for (var meta in _talkgroupMetadata.values) {
      if (meta.category != null && meta.category!.isNotEmpty) {
        categories.add(meta.category!);
      }
    }
    return categories;
  }
  
  bool get hasData => _talkgroupNames.isNotEmpty;
  
  bool isEnabled(int tgid) {
    final tgidStr = tgid.toString();
    // If whitelist has entries, talkgroup must be in whitelist
    if (_whitelist.isNotEmpty) {
      return _whitelist.contains(tgidStr);
    }
    // Otherwise, check if it's NOT in blacklist
    return !_blacklist.contains(tgidStr);
  }
  
  List<MapEntry<String, String>> get allTalkgroups {
    return _talkgroupNames.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
  }
  
  String? get currentSystemId => _currentSystemId;
  
  void start(AppConfig config) {
    _loadTalkgroups(config);
    _loadLists(config);
    _loadMetadata(config);
    
    // Refresh talkgroups every 60 seconds in case system changes
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _loadTalkgroups(config);
      _loadLists(config);
      _loadMetadata(config);
    });
  }
  
  Future<void> _loadTalkgroups(AppConfig config) async {
    try {
      final serverIp = config.serverIp;
      if (serverIp.isEmpty) return;
      
      final url = 'http://$serverIp:${AppConfig.serverPort}/api/talkgroups/list';
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final String? systemId = data['system_id'];
          final List<dynamic> talkgroups = data['talkgroups'] ?? [];
          
          // Only update if we got data
          if (systemId != null && talkgroups.isNotEmpty) {
            final Map<String, String> newMap = {};
            for (var tg in talkgroups) {
              final id = tg['id']?.toString() ?? '';
              final name = tg['name'] ?? 'Unknown';
              if (id.isNotEmpty) {
                newMap[id] = name;
              }
            }
            
            // Update the map and system ID
            _talkgroupNames = newMap;
            _currentSystemId = systemId;
            notifyListeners();
            
            debugPrint('TalkgroupService: Loaded ${_talkgroupNames.length} talkgroups for system $systemId');
          }
        }
      }
    } catch (e) {
      debugPrint('TalkgroupService: Error loading talkgroups: $e');
    }
  }
  
  Future<void> _loadLists(AppConfig config) async {
    try {
      final serverIp = config.serverIp;
      if (serverIp.isEmpty) return;
      
      final url = 'http://$serverIp:${AppConfig.serverPort}/api/talkgroups/lists';
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final List<dynamic> whitelist = data['whitelist'] ?? [];
          final List<dynamic> blacklist = data['blacklist'] ?? [];
          
          _whitelist = Set<String>.from(whitelist.map((e) => e.toString()));
          _blacklist = Set<String>.from(blacklist.map((e) => e.toString()));
          
          notifyListeners();
          
          debugPrint('TalkgroupService: Loaded whitelist: ${_whitelist.length}, blacklist: ${_blacklist.length}');
        }
      }
    } catch (e) {
      debugPrint('TalkgroupService: Error loading lists: $e');
    }
  }
  
  Future<void> _loadMetadata(AppConfig config) async {
    try {
      final serverIp = config.serverIp;
      if (serverIp.isEmpty) return;
      
      final url = 'http://$serverIp:${AppConfig.serverPort}/api/talkgroups/metadata';
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final Map<String, dynamic> metadata = Map<String, dynamic>.from(data['metadata'] ?? {});
          
          _talkgroupMetadata.clear();
          metadata.forEach((key, value) {
            if (value is Map<String, dynamic>) {
              _talkgroupMetadata[key] = TalkgroupMetadata.fromJson(value);
            }
          });
          
          notifyListeners();
          
          debugPrint('TalkgroupService: Loaded metadata for ${_talkgroupMetadata.length} talkgroups');
        }
      }
    } catch (e) {
      debugPrint('TalkgroupService: Error loading metadata: $e');
    }
  }
  
  Future<bool> toggleTalkgroup(String tgid, bool enabled) async {
    if (enabled) {
      // Add to whitelist, remove from blacklist
      _whitelist.add(tgid);
      _blacklist.remove(tgid);
    } else {
      // Remove from whitelist, add to blacklist
      _whitelist.remove(tgid);
      _blacklist.add(tgid);
    }
    
    notifyListeners();
    return await _saveLists();
  }
  
  Future<bool> _saveLists() async {
    try {
      final serverIp = _currentSystemId != null ? '' : '';
      if (serverIp.isEmpty) {
        // Get server IP from somewhere - we'll need to pass config
        return false;
      }
      
      // This will be called with proper context
      return true;
    } catch (e) {
      debugPrint('TalkgroupService: Error saving lists: $e');
      return false;
    }
  }
  
  Future<bool> saveLists(AppConfig config) async {
    try {
      final serverIp = config.serverIp;
      if (serverIp.isEmpty) return false;
      
      final url = 'http://$serverIp:${AppConfig.serverPort}/api/talkgroups/update-lists';
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'whitelist': _whitelist.toList(),
          'blacklist': _blacklist.toList(),
        }),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final wasRestarted = data['restarted'] ?? false;
          debugPrint('TalkgroupService: Lists saved successfully${wasRestarted ? " and OP25 restarted" : ""}');
          return true;
        }
      }
      
      return false;
    } catch (e) {
      debugPrint('TalkgroupService: Error saving lists: $e');
      return false;
    }
  }
  
  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}

class TalkgroupMetadata {
  final String? category;
  final String? tag;
  final bool encrypted;
  final String? mode;

  TalkgroupMetadata({
    this.category,
    this.tag,
    this.encrypted = false,
    this.mode,
  });

  factory TalkgroupMetadata.fromJson(Map<String, dynamic> json) {
    return TalkgroupMetadata(
      category: json['category'] as String?,
      tag: json['tag'] as String?,
      encrypted: json['encrypted'] as bool? ?? false,
      mode: json['mode'] as String?,
    );
  }
}
