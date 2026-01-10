import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config.dart';
import '../service/talkgroup_service.dart';

class TalkgroupManagementScreen extends StatefulWidget {
  @override
  _TalkgroupManagementScreenState createState() => _TalkgroupManagementScreenState();
}

class _TalkgroupManagementScreenState extends State<TalkgroupManagementScreen> {
  String _searchQuery = '';
  bool _showEnabledOnly = false;
  bool _showDisabledOnly = false;
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final talkgroupService = context.watch<TalkgroupService>();
    final appConfig = context.watch<AppConfig>();
    
    // Filter talkgroups based on search and filters
    final allTalkgroups = talkgroupService.allTalkgroups;
    final filteredTalkgroups = allTalkgroups.where((entry) {
      final matchesSearch = _searchQuery.isEmpty ||
          entry.key.contains(_searchQuery) ||
          entry.value.toLowerCase().contains(_searchQuery.toLowerCase());
      
      if (!matchesSearch) return false;
      
      final tgid = int.tryParse(entry.key) ?? 0;
      final isEnabled = talkgroupService.isEnabled(tgid);
      
      if (_showEnabledOnly && !isEnabled) return false;
      if (_showDisabledOnly && isEnabled) return false;
      
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('Talkgroup Management'),
        backgroundColor: Colors.black,
        actions: [
          if (talkgroupService.currentSystemId != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Chip(
                label: Text(
                  'System ${talkgroupService.currentSystemId}',
                  style: TextStyle(fontSize: 12),
                ),
                backgroundColor: Colors.cyanAccent,
                labelStyle: TextStyle(color: Colors.black),
              ),
            ),
          IconButton(
            icon: Icon(Icons.save),
            onPressed: _isSaving ? null : () => _saveChanges(talkgroupService, appConfig),
            tooltip: 'Save Changes',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search and filter bar
          Container(
            padding: EdgeInsets.all(8.0),
            color: Colors.grey[900],
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search talkgroups...',
                    hintStyle: TextStyle(color: Colors.white54),
                    prefixIcon: Icon(Icons.search, color: Colors.cyanAccent),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.1),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  style: TextStyle(color: Colors.white),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
                SizedBox(height: 8),
                Row(
                  children: [
                    FilterChip(
                      label: Text('Enabled Only'),
                      selected: _showEnabledOnly,
                      onSelected: (value) {
                        setState(() {
                          _showEnabledOnly = value;
                          if (value) _showDisabledOnly = false;
                        });
                      },
                      selectedColor: Colors.green,
                      checkmarkColor: Colors.white,
                    ),
                    SizedBox(width: 8),
                    FilterChip(
                      label: Text('Disabled Only'),
                      selected: _showDisabledOnly,
                      onSelected: (value) {
                        setState(() {
                          _showDisabledOnly = value;
                          if (value) _showEnabledOnly = false;
                        });
                      },
                      selectedColor: Colors.red,
                      checkmarkColor: Colors.white,
                    ),
                    Spacer(),
                    Text(
                      '${filteredTalkgroups.length} of ${allTalkgroups.length}',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Talkgroup list
          Expanded(
            child: filteredTalkgroups.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.speaker_phone, size: 64, color: Colors.white24),
                        SizedBox(height: 16),
                        Text(
                          allTalkgroups.isEmpty
                              ? 'No talkgroups loaded'
                              : 'No talkgroups match your filters',
                          style: TextStyle(color: Colors.white54, fontSize: 16),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: filteredTalkgroups.length,
                    itemBuilder: (context, index) {
                      final entry = filteredTalkgroups[index];
                      final tgid = int.tryParse(entry.key) ?? 0;
                      final isEnabled = talkgroupService.isEnabled(tgid);
                      
                      return Card(
                        color: Colors.white.withOpacity(0.05),
                        margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: SwitchListTile(
                          value: isEnabled,
                          onChanged: (value) async {
                            await talkgroupService.toggleTalkgroup(entry.key, value);
                          },
                          activeColor: Colors.greenAccent,
                          title: Text(
                            entry.value,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Text(
                            'TGID: ${entry.key}',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          secondary: Icon(
                            isEnabled ? Icons.volume_up : Icons.volume_off,
                            color: isEnabled ? Colors.greenAccent : Colors.red,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveChanges(TalkgroupService talkgroupService, AppConfig appConfig) async {
    setState(() {
      _isSaving = true;
    });

    final success = await talkgroupService.saveLists(appConfig);

    setState(() {
      _isSaving = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'Talkgroup lists saved and OP25 restarted!'
              : 'Failed to save talkgroup lists'),
          backgroundColor: success ? Colors.green : Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }
}
