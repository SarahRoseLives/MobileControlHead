import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:http/http.dart' as http;
import '../config.dart';

class mDNScannerService extends ChangeNotifier {
  static final mDNScannerService _instance = mDNScannerService._internal();
  factory mDNScannerService() => _instance;
  mDNScannerService._internal();

  final String serviceType = '_op25mch._tcp.local';
  final String desiredServiceName = 'OP25MCH._op25mch._tcp.local';
  ServerStatus _status = ServerStatus.searching;
  ServerStatus get status => _status;
  MDnsClient? _client;
  String? _lastFoundIp;

  Future<void> startDiscovery(AppConfig appConfig) async {
    _updateStatus(ServerStatus.searching);
    _client = MDnsClient();

    try {
      await _client?.start();

      await for (PtrResourceRecord ptr in _client!.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(serviceType),
      )) {
        if (ptr.domainName.isEmpty || ptr.domainName != desiredServiceName) continue;

        debugPrint('Found service: ${ptr.domainName}');

        await for (SrvResourceRecord srv in _client!.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(ptr.domainName),
        )) {
          debugPrint('Service running on ${srv.target}:${srv.port}');
          await for (IPAddressResourceRecord a in _client!.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(srv.target),
          )) {
            final ip = a.address?.address;
            if (ip != null && ip != _lastFoundIp) {
              final healthy = await _checkHealth(ip, srv.port);
              if (healthy) {
                _lastFoundIp = ip;
                appConfig.updateServerIp(_lastFoundIp!);
                _updateStatus(ServerStatus.found);
                debugPrint('Found healthy server at $ip:${srv.port}');
                return; // Use the first healthy server and stop
              } else {
                debugPrint('Ignoring $ip:${srv.port} (health check failed)');
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('mDNS Discovery Error: $e');
      _updateStatus(ServerStatus.notFound);
      Future.delayed(Duration(seconds: 5), () => startDiscovery(appConfig));
    }
  }

  Future<bool> _checkHealth(String ip, int port) async {
    final url = Uri.parse('http://$ip:$port/health');
    try {
      final resp = await http.get(url).timeout(Duration(seconds: 2));
      return resp.statusCode == 200 && resp.body.trim() == "OK";
    } catch (e) {
      return false;
    }
  }

  void stopDiscovery() {
    _client?.stop();
    _client = null;
    _lastFoundIp = null;
    _updateStatus(ServerStatus.stopped);
  }

  void restartDiscovery(AppConfig appConfig) {
    stopDiscovery();
    startDiscovery(appConfig);
  }

  void _updateStatus(ServerStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      notifyListeners();
    }
  }
}

enum ServerStatus { searching, found, notFound, stopped }