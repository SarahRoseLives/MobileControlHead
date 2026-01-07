import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config.dart'; // Your app's config file

//region Talkgroup Data Model
class TalkgroupData {
  final int tgid;
  final int srcid;
  final String frequency;
  final DateTime lastUpdate;
  final bool active;

  TalkgroupData({
    required this.tgid,
    required this.srcid,
    required this.frequency,
    required this.lastUpdate,
    required this.active,
  });

  factory TalkgroupData.fromJson(Map<String, dynamic> json) {
    return TalkgroupData(
      tgid: json['tgid'] ?? 0,
      srcid: json['srcid'] ?? 0,
      frequency: json['frequency'] ?? '',
      lastUpdate: DateTime.parse(json['last_update'] ?? DateTime.now().toIso8601String()),
      active: json['active'] ?? false,
    );
  }
}
//endregion

//region Expanded Data Models
// Main container for all data received from the API
class Op25Data {
  TrunkUpdate? trunkInfo;
  ChannelUpdate? channelInfo;
  List<CallLogEntry> callLog;
  RxUpdate? rxInfo;
  TerminalConfig? terminalConfig;
  FullConfig? fullConfig;

  Op25Data({
    this.trunkInfo,
    this.channelInfo,
    this.callLog = const [],
    this.rxInfo,
    this.terminalConfig,
    this.fullConfig,
  });
}

class TrunkUpdate {
  final String nac;
  final String systemName;
  final String systemType;
  final String? callsign;
  final String wacn;
  final String sysid;
  final String rfid;
  final String stid;
  final Map<String, FrequencyInfo> frequencyData;
  final Map<String, dynamic> adjacentSites;
  final Map<String, dynamic> patches;
  final List<BandPlanEntry> bandPlan;
  final String topLine; // ADDED for TSBK parsing

  TrunkUpdate({
    required this.nac,
    required this.systemName,
    required this.systemType,
    this.callsign,
    required this.wacn,
    required this.sysid,
    required this.rfid,
    required this.stid,
    required this.frequencyData,
    required this.adjacentSites,
    required this.patches,
    this.bandPlan = const [],
    this.topLine = '', // ADDED for TSBK parsing
  });

  factory TrunkUpdate.fromJson(String nac, Map<String, dynamic> json) {
    var freqs = <String, FrequencyInfo>{};
    if (json['frequency_data'] is Map) {
      (json['frequency_data'] as Map).forEach((key, value) {
        freqs[key] = FrequencyInfo.fromJson(value);
      });
    }

    var bp = <BandPlanEntry>[];
    if (json['band_plan'] is Map) {
      (json['band_plan'] as Map).forEach((key, value) {
        bp.add(BandPlanEntry.fromJson(key, value));
      });
    }

    return TrunkUpdate(
      nac: nac,
      systemName: json['system'] ?? 'N/A',
      systemType: json['type'] ?? 'N/A',
      callsign: json['callsign'],
      wacn: json['wacn']?.toString() ?? '-',
      sysid: json['sysid']?.toRadixString(16).toUpperCase() ?? '-',
      rfid: json['rfid']?.toString() ?? '-',
      stid: json['stid']?.toString() ?? '-',
      frequencyData: freqs,
      adjacentSites: json['adjacent_data'] ?? {},
      patches: json['patch_data'] ?? {},
      bandPlan: bp,
      topLine: json['top_line'] ?? '', // ADDED for TSBK parsing
    );
  }
}

class FrequencyInfo {
  final String type;
  final String lastActivity;
  final String mode;
  final int counter;
  final List<int?> tgids;
  final List<String?> tags;
  final List<int?> srcaddrs;
  final List<String?> srctags;

  FrequencyInfo({
    required this.type,
    required this.lastActivity,
    required this.mode,
    required this.counter,
    required this.tgids,
    required this.tags,
    required this.srcaddrs,
    required this.srctags,
  });

  factory FrequencyInfo.fromJson(Map<String, dynamic> json) {
    return FrequencyInfo(
      type: json['type'] ?? 'voice',
      lastActivity: json['last_activity']?.toString() ?? '0',
      mode: json['mode']?.toString() ?? '-',
      counter: json['counter'] ?? 0,
      tgids: List<int?>.from(json['tgids'] ?? []),
      tags: List<String?>.from(json['tags'] ?? []),
      srcaddrs: List<int?>.from(json['srcaddrs'] ?? []),
      srctags: List<String?>.from(json['srctags'] ?? []),
    );
  }
}

class ChannelUpdate {
  final List<String> channelIds;
  final Map<String, ChannelInfo> channels;

  ChannelUpdate({required this.channelIds, required this.channels});

  factory ChannelUpdate.fromJson(Map<String, dynamic> json) {
    var channelMap = <String, ChannelInfo>{};
    List<String> idList =
        List<String>.from(json['channels']?.map((c) => c.toString()) ?? []);

    for (var id in idList) {
      if (json[id] is Map) {
        channelMap[id] = ChannelInfo.fromJson(json[id]);
      }
    }

    return ChannelUpdate(channelIds: idList, channels: channelMap);
  }
}

class ChannelInfo {
  final String name;
  final String system;
  final double freq;
  final int tgid;
  final String tag;
  final int srcaddr;
  final String srctag;
  final int encrypted;
  final int emergency;
  final String tdma;
  final int? holdTgid;
  final bool? capture;
  final int? error;

  ChannelInfo({
    required this.name,
    required this.system,
    required this.freq,
    required this.tgid,
    required this.tag,
    required this.srcaddr,
    required this.srctag,
    required this.encrypted,
    required this.emergency,
    required this.tdma,
    this.holdTgid,
    this.capture,
    this.error,
  });

  factory ChannelInfo.fromJson(Map<String, dynamic> json) {
    return ChannelInfo(
      name: json['name'] ?? '',
      system: json['system'] ?? 'N/A',
      freq: (json['freq'] ?? 0.0).toDouble(),
      tgid: json['tgid'] ?? 0,
      tag: json['tag'] ?? 'Talkgroup ${json['tgid'] ?? 0}',
      srcaddr: json['srcaddr'] ?? 0,
      srctag: json['srctag'] ?? 'ID: ${json['srcaddr'] ?? 0}',
      encrypted: json['encrypted'] ?? 0,
      emergency: json['emergency'] ?? 0,
      tdma: json['tdma']?.toString() ?? '-',
      holdTgid: json['hold_tgid'],
      capture: json['capture'],
      error: json['error'],
    );
  }
}

class CallLogEntry {
  final int time;
  final String sysid;
  final int tgid;
  final String tgtag;
  final int rid;
  final String rtag;
  final double freq;
  final int slot;
  final int? prio;
  final String? rcvr;
  final String? rcvrtag;

  CallLogEntry({
    required this.time,
    required this.sysid,
    required this.tgid,
    required this.tgtag,
    required this.rid,
    required this.rtag,
    required this.freq,
    required this.slot,
    this.prio,
    this.rcvr,
    this.rcvrtag,
  });

  factory CallLogEntry.fromJson(Map<String, dynamic> json) {
    return CallLogEntry(
      time: json['time'] ?? 0,
      sysid: json['sysid']?.toRadixString(16).toUpperCase() ?? '-',
      tgid: json['tgid'] ?? 0,
      tgtag: json['tgtag'] ?? '',
      rid: json['rid'] ?? 0,
      rtag: json['rtag'] ?? '',
      freq: (json['freq'] ?? 0.0).toDouble(),
      slot: json['slot'] ?? 0,
      prio: json['prio'],
      rcvr: json['rcvr'],
      rcvrtag: json['rcvrtag'],
    );
  }
}

class RxUpdate {
  final List<String> files;
  final int? error;
  final double? fineTune;

  RxUpdate({this.files = const [], this.error, this.fineTune});

  factory RxUpdate.fromJson(Map<String, dynamic> json) {
    return RxUpdate(
      files: List<String>.from(json['files'] ?? []),
      error: json['error'],
      fineTune: json['fine_tune']?.toDouble(),
    );
  }
}

class TerminalConfig {
  final List<SmartColor> smartColors;
  final int largeTuningStep;
  final int smallTuningStep;

  TerminalConfig({
    this.smartColors = const [],
    this.largeTuningStep = 1200,
    this.smallTuningStep = 100,
  });

  factory TerminalConfig.fromJson(Map<String, dynamic> json) {
    var colors = <SmartColor>[];
    if (json['smart_colors'] is List) {
      colors = (json['smart_colors'] as List)
          .map((item) => SmartColor.fromJson(item))
          .toList();
    }
    return TerminalConfig(
      smartColors: colors,
      largeTuningStep: json['tuning_step_large'] ?? 1200,
      smallTuningStep: json['tuning_step_small'] ?? 100,
    );
  }
}

class SmartColor {
  final List<String> keywords;
  final String color;

  SmartColor({required this.keywords, required this.color});

  factory SmartColor.fromJson(Map<String, dynamic> json) {
    return SmartColor(
      keywords: List<String>.from(json['keywords'] ?? []),
      color: json['color'] ?? '#FFFFFF',
    );
  }
}

class FullConfig {
  final Map<String, List<Preset>> presetsBySysname;
  final Map<String, dynamic> siteAliases;

  FullConfig({this.presetsBySysname = const {}, this.siteAliases = const {}});

  factory FullConfig.fromJson(Map<String, dynamic> json) {
    var presetsMap = <String, List<Preset>>{};
    var aliasMap = <String, dynamic>{};

    if (json['trunking']?['chans'] is List) {
      for (var chan in json['trunking']['chans']) {
        final sysname = chan['sysname'];
        if (sysname != null) {
          if (chan['presets'] is List) {
            presetsMap[sysname] = (chan['presets'] as List)
                .map((p) => Preset.fromJson(p))
                .toList();
          }
          if (chan['site_alias'] is Map) {
            aliasMap[sysname.toUpperCase()] = chan['site_alias'];
          }
        }
      }
    }
    return FullConfig(presetsBySysname: presetsMap, siteAliases: aliasMap);
  }
}

class Preset {
  final int id;
  final String label;
  final int tgid;

  Preset({required this.id, required this.label, required this.tgid});

  factory Preset.fromJson(Map<String, dynamic> json) {
    return Preset(
      id: json['id'] ?? 0,
      label: json['label'] ?? 'Preset',
      tgid: json['tgid'] ?? 0,
    );
  }
}

class BandPlanEntry {
  final String id;
  final String type;
  final double frequency;
  final double txOffset;
  final double spacing;
  final int slots;

  BandPlanEntry({
    required this.id,
    required this.type,
    required this.frequency,
    required this.txOffset,
    required this.spacing,
    required this.slots,
  });

  factory BandPlanEntry.fromJson(String id, Map<String, dynamic> json) {
    final mode = json['tdma'] ?? 1;
    return BandPlanEntry(
      id: id,
      type: mode > 1 ? "TDMA" : "FDMA",
      frequency: (json['frequency'] ?? 0.0) / 1000000.0,
      txOffset: (json['offset'] ?? 0.0) / 1000000.0,
      spacing: (json['step'] ?? 0.0) / 1000.0,
      slots: mode,
    );
  }
}

//endregion

class Op25ApiService extends ChangeNotifier {
  AppConfig? _appConfig;
  Timer? _timer;
  final http.Client _client = http.Client();

  //region State Properties
  Op25Data? _data;
  Op25Data? get data => _data;

  String _error = '';
  String get error => _error;

  bool _isFetching = false;

  int _channelIndex = 0;
  int get channelIndex => _channelIndex;

  int _httpErrors = 0;
  int get httpErrors => _httpErrors;

  final List<Map<String, dynamic>> _commandQueue = [];
  static const int _commandQueueLimit = 5;

  // Stateful variables to hold the last known call info, mirroring the JS UI
  int _lastActiveTgid = 0;
  String _lastActiveTag = '';
  int _lastActiveSrcAddr = 0;
  String _lastActiveSrcTag = '';
  
  // Talkgroup data from backend
  TalkgroupData? _talkgroupData;
  TalkgroupData? get talkgroupData => _talkgroupData;
  
  String _controlChannel = '';
  double get controlChannelMhz => double.tryParse(_controlChannel) ?? 0.0;
  //endregion

  ChannelInfo? get currentChannelInfo {
    final channelInfoData = data?.channelInfo;
    if (channelInfoData == null || channelInfoData.channels.isEmpty) {
      return null;
    }

    // 1. Find a channel that is reporting an active talkgroup.
    ChannelInfo? baseChannel;
    for (final channel in channelInfoData.channels.values) {
      if (channel.tgid > 0) {
        baseChannel = channel;
        break;
      }
    }

    // 2. If no channel is obviously active, fall back to the one at the current index.
    baseChannel ??=
        channelInfoData.channels[channelInfoData.channelIds.elementAtOrNull(channelIndex)];
    if (baseChannel == null) return null;

    // 3. Synthesize the final ChannelInfo object by combining the base channel
    //    data with the last known live call data.
    final tgid = baseChannel.tgid > 0 ? baseChannel.tgid : _lastActiveTgid;
    final srcaddr = baseChannel.srcaddr > 0 ? baseChannel.srcaddr : _lastActiveSrcAddr;
    final tag = (baseChannel.tag.isNotEmpty && baseChannel.tag != 'Talkgroup 0')
        ? baseChannel.tag
        : _lastActiveTag;
    final srctag = (baseChannel.srctag.isNotEmpty && baseChannel.srctag != 'ID: 0')
        ? baseChannel.srctag
        : _lastActiveSrcTag;

    return ChannelInfo(
      name: baseChannel.name,
      system: baseChannel.system,
      freq: baseChannel.freq,
      tgid: tgid,
      tag: tag.isEmpty ? 'Talkgroup $tgid' : tag,
      srcaddr: srcaddr,
      srctag: srctag.isEmpty ? 'ID: $srcaddr' : srctag,
      encrypted: baseChannel.encrypted,
      emergency: baseChannel.emergency,
      tdma: baseChannel.tdma,
      holdTgid: baseChannel.holdTgid,
      capture: baseChannel.capture,
      error: baseChannel.error,
    );
  }

  //region Public Methods for UI Interaction
  void start(AppConfig appConfig) {
    _appConfig = appConfig;
    _timer?.cancel();
    // Initial fetch for config data
    getFullConfig();
    getTerminalConfig();
    // Start periodic updates
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _fetchData();
      _fetchTalkgroupData();
    });
    debugPrint("OP25 API Service Started");
  }

  void stop() {
    _timer?.cancel();
    debugPrint("OP25 API Service Stopped");
  }

  void nextChannel() {
      final int channelCount = _data?.channelInfo?.channelIds.length ?? 0;
      if (channelCount == 0) return;
      _channelIndex = (_channelIndex + 1) % channelCount;
      notifyListeners();
  }

  void previousChannel() {
      final int channelCount = _data?.channelInfo?.channelIds.length ?? 0;
      if (channelCount == 0) return;
      _channelIndex = (_channelIndex - 1 + channelCount) % channelCount;
      notifyListeners();
  }

  void tune(int amount) {
    _sendCommand('adj_tune', amount);
  }

  void togglePlot(String plotType) {
    _sendCommand('toggle_plot', plotType);
  }

  void setHold(int tgid) {
    if (tgid > 0) {
      _sendCommand("whitelist", tgid);
    }
    _sendCommand('hold', tgid);
  }

  void setLockout(int tgid) {
    _sendCommand('lockout', tgid);
  }

  void clearScanRules() {
    setHold(0);
  }

  void toggleCapture() {
   _sendCommand('capture');
  }

  void dumpTGs() => _sendCommand('dump_tgids');
  void dumpTracking() => _sendCommand('dump_tracking');
  void dumpBuffer() => _sendCommand('dump_buffer');

  void getFullConfig() => _sendCommand('get_full_config');
  void getTerminalConfig() => _sendCommand('get_terminal_config');
  //endregion

  //region Core Logic

  void _sendCommand(String command, [dynamic arg1, dynamic arg2]) {
    final Map<String, dynamic> cmd = {"command": command};

    cmd['arg1'] = arg1 ?? 0;

    final currentChannelId = _data?.channelInfo?.channelIds.elementAtOrNull(_channelIndex);
    final finalArg2 = arg2 ?? (currentChannelId != null ? int.tryParse(currentChannelId) ?? 0 : 0);
    cmd['arg2'] = finalArg2;

    if (_commandQueue.length >= _commandQueueLimit) {
        _commandQueue.removeAt(0);
    }
    _commandQueue.add(cmd);

    _processCommandQueue();
  }

  Future<void> _fetchData() async {
    _sendCommand("update");
  }

  Future<void> _processCommandQueue() async {
    if (_isFetching || _appConfig == null || _appConfig!.serverIp.isEmpty || _commandQueue.isEmpty) return;
    _isFetching = true;

    final url = Uri.parse(_appConfig!.op25DataApiUrl);
    final List<Map<String, dynamic>> commandsToSend = List.from(_commandQueue);
    _commandQueue.clear();

    final requestBody = json.encode(commandsToSend);

    try {
      final response = await _client.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: requestBody,
      ).timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        if (response.body.isNotEmpty) {
          final List<dynamic> responseData = json.decode(response.body);
          _parseResponse(responseData);
          _error = '';
        } else {
          _error = "Received empty response from server.";
        }
      } else {
        _httpErrors++;
        _error = "Server Error: ${response.statusCode}";
      }
    } catch (e) {
      _httpErrors++;
      _error = "Connection Error: ${e.toString()}";
    } finally {
      _isFetching = false;
      notifyListeners();
    }
  }

  void _parseResponse(List<dynamic> responseList) {
    _data ??= Op25Data();

    for (var item in responseList) {
      if (item is! Map<String, dynamic> || !item.containsKey('json_type')) continue;

      final String jsonType = item['json_type'];

      switch (jsonType) {
        case 'trunk_update':
          if (item['srcaddr'] != null) _lastActiveSrcAddr = item['srcaddr'];
          if (item['grpaddr'] != null) _lastActiveTgid = item['grpaddr'];

          item.forEach((key, value) {
            if (key != 'json_type' && value is Map<String, dynamic>) {
              _data!.trunkInfo = TrunkUpdate.fromJson(key, value);
            }
          });
          break;
        case 'channel_update':
          _data!.channelInfo = ChannelUpdate.fromJson(item);
          // Also inspect the channels for any live call data to update our state
          for (final channel in _data!.channelInfo!.channels.values) {
            if (channel.tgid > 0) {
              _lastActiveTgid = channel.tgid;
              _lastActiveTag = channel.tag;
            }
            if (channel.srcaddr > 0) {
              _lastActiveSrcAddr = channel.srcaddr;
              _lastActiveSrcTag = channel.srctag;
            }
          }
          break;
        case 'change_freq':
          _lastActiveTgid = item['tgid'] ?? _lastActiveTgid;
          _lastActiveTag = item['tag'] ?? _lastActiveTag;
          break;
        case 'call_log':
          if (item['log'] is List) {
            _data!.callLog = (item['log'] as List)
                .map((logItem) => CallLogEntry.fromJson(logItem))
                .toList();
          }
          break;
        case 'rx_update':
          _data!.rxInfo = RxUpdate.fromJson(item);
          break;
        case 'terminal_config':
          _data!.terminalConfig = TerminalConfig.fromJson(item);
          break;
        case 'full_config':
          _data!.fullConfig = FullConfig.fromJson(item);
          break;
        case 'plot':
          break;
      }
    }
  }

  Future<void> _fetchTalkgroupData() async {
    if (_appConfig == null || _appConfig!.serverIp.isEmpty) return;

    final url = Uri.parse('${_appConfig!.op25ControlApiUrl}api/talkgroup');
    
    try {
      final response = await _client.get(url).timeout(const Duration(seconds: 2));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Extract talkgroup data
        if (data['talkgroup'] != null) {
          _talkgroupData = TalkgroupData.fromJson(data['talkgroup']);
        } else {
          _talkgroupData = null;
        }
        
        // Extract control channel
        if (data['control_channel'] != null) {
          _controlChannel = data['control_channel'];
        }
        
        notifyListeners();
      }
    } catch (e) {
      // Silently fail - talkgroup data is optional
      if (kDebugMode) {
        print('Error fetching talkgroup data: $e');
      }
    }
  }

  @override
  void dispose() {
    stop();
    _client.close();
    super.dispose();
  }
  //endregion
}