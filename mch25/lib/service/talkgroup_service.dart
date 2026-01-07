import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config.dart';

class TalkgroupService extends ChangeNotifier {
  Map<String, String> _talkgroupNames = {}; // tgid -> name
  Timer? _refreshTimer;
  
  String getTalkgroupName(int tgid) {
    final name = _talkgroupNames[tgid.toString()];
    return name ?? 'Unknown';
  }
  
  bool get hasData => _talkgroupNames.isNotEmpty;
  
  void start(AppConfig config) {
    _loadTalkgroups(config);
    
    // Refresh talkgroups every 60 seconds in case system changes
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _loadTalkgroups(config);
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
            notifyListeners();
            
            debugPrint('TalkgroupService: Loaded ${_talkgroupNames.length} talkgroups for system $systemId');
          }
        }
      }
    } catch (e) {
      debugPrint('TalkgroupService: Error loading talkgroups: $e');
    }
  }
  
  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}
