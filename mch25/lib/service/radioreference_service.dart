import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';

class RadioReferenceService extends ChangeNotifier {
  String? username;
  String? password;
  bool isLoggedIn = false;
  bool isLoading = false;
  String? errorMessage;

  // You may want to persist these in secure storage.
  RadioReferenceService({this.username, this.password});

  // For now, store in memory; for production, use secure storage.
  Future<bool> validateCredentials(String user, String pass) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    // Try a simple API call to validate credentials
    try {
      final authInfo = _buildAuthInfo(user, pass);
      final wsdlUrl = "http://api.radioreference.com/soap2/?wsdl&v=latest&s=rpc";
      // Test: getZipcodeInfo for a known valid US zip (should not error if credentials are good)
      final response = await _soapRequest(
        wsdlUrl,
        'getZipcodeInfo',
        {'zipcode': 90210, 'authInfo': authInfo}
      );
      if (response != null && response.containsKey('ctid')) {
        username = user;
        password = pass;
        isLoggedIn = true;
        isLoading = false;
        errorMessage = null;
        notifyListeners();
        return true;
      } else {
        errorMessage = "API login failed (check credentials)";
        isLoggedIn = false;
        isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      errorMessage = "Login error: $e";
      isLoggedIn = false;
      isLoading = false;
      notifyListeners();
      return false;
    }
  }

  void logout() {
    username = null;
    password = null;
    isLoggedIn = false;
    errorMessage = null;
    notifyListeners();
  }

  Map<String, dynamic> _buildAuthInfo(String user, String pass) {
    return {
      "appKey": utf8.decode(base64Decode('Mjg4MDExNjM=')),
      "username": user,
      "password": pass,
      "version": "latest",
      "style": "rpc"
    };
  }

  /// Helper: Build SOAP Envelope
  String _buildSoapEnvelope(String method, Map<String, dynamic> params) {
    final authInfo = params['authInfo'];
    final otherParams = params..remove('authInfo');
    final paramXml = otherParams.entries.map((e) => '<${e.key}>${e.value}</${e.key}>').join('');
    final authXml = '''
      <authInfo>
        <appKey>${authInfo['appKey']}</appKey>
        <username>${authInfo['username']}</username>
        <password>${authInfo['password']}</password>
        <version>${authInfo['version']}</version>
        <style>${authInfo['style']}</style>
      </authInfo>
    ''';
    return '''
      <?xml version="1.0" encoding="utf-8"?>
      <soap:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xmlns:xsd="http://www.w3.org/2001/XMLSchema"
        xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <$method xmlns="http://api.radioreference.com/soap2/">
            $paramXml
            $authXml
          </$method>
        </soap:Body>
      </soap:Envelope>
    ''';
  }

  /// Helper: Make SOAP Request
  Future<Map<String, dynamic>?> _soapRequest(
    String wsdlUrl,
    String method,
    Map<String, dynamic> params
  ) async {
    final endpoint = wsdlUrl.replaceFirst('?wsdl&v=latest&s=rpc', '');
    final envelope = _buildSoapEnvelope(method, Map.of(params));
    final headers = {
      'Content-Type': 'text/xml; charset=utf-8',
      'SOAPAction': 'http://api.radioreference.com/soap2/$method'
    };
    final response = await http.post(
      Uri.parse(endpoint),
      headers: headers,
      body: envelope,
    );
    if (response.statusCode == 200) {
      // Parse XML for result node
      final document = XmlDocument.parse(response.body);
      final resultNode = document.findAllElements('${method}Result').firstOrNull;
      if (resultNode != null) {
        try {
          // Try JSON decode (if API returns JSON inside XML)
          final jsonMap = jsonDecode(resultNode.text);
          return jsonMap is Map<String, dynamic>
              ? jsonMap
              : Map<String, dynamic>.from(jsonMap);
        } catch (e) {
          // Fallback: try to parse as XML Map
          return _xmlToMap(resultNode);
        }
      }
    }
    return null;
  }

  // Helper to convert XML node to Map<String, dynamic>
  Map<String, dynamic> _xmlToMap(XmlElement node) {
    final map = <String, dynamic>{};
    for (final child in node.children.whereType<XmlElement>()) {
      if (child.children.length == 1 && child.firstChild is XmlText) {
        map[child.name.local] = child.text;
      } else {
        map[child.name.local] = _xmlToMap(child);
      }
    }
    return map;
  }

  /// Get Zipcode Info (returns county ID)
  Future<Map<String, dynamic>?> getZipcodeInfo(String zip) async {
    if (!(isLoggedIn && username != null && password != null)) {
      errorMessage = "Please login first.";
      notifyListeners();
      return null;
    }
    final wsdlUrl = "http://api.radioreference.com/soap2/?wsdl&v=latest&s=rpc";
    final authInfo = _buildAuthInfo(username!, password!);
    return await _soapRequest(wsdlUrl, 'getZipcodeInfo', {
      'zipcode': int.parse(zip),
      'authInfo': authInfo,
    });
  }

  /// Get County Info (returns trunked system list)
  Future<Map<String, dynamic>?> getCountyInfo(String countyId) async {
    if (!(isLoggedIn && username != null && password != null)) {
      errorMessage = "Please login first.";
      notifyListeners();
      return null;
    }
    final wsdlUrl = "http://api.radioreference.com/soap2/?wsdl&v=latest&s=rpc";
    final authInfo = _buildAuthInfo(username!, password!);
    return await _soapRequest(wsdlUrl, 'getCountyInfo', {
      'ctid': countyId,
      'authInfo': authInfo,
    });
  }

  /// Get Trunked System Sites (returns list of sites)
  Future<List<Map<String, dynamic>>?> getTrsSites(int systemId) async {
    if (!(isLoggedIn && username != null && password != null)) {
      errorMessage = "Please login first.";
      notifyListeners();
      return null;
    }
    final wsdlUrl = "http://api.radioreference.com/soap2/?wsdl&v=latest&s=rpc";
    final authInfo = _buildAuthInfo(username!, password!);
    final result = await _soapRequest(wsdlUrl, 'getTrsSites', {
      'sid': systemId,
      'authInfo': authInfo,
    });
    if (result != null && result['site']) {
      if (result['site'] is List) {
        return List<Map<String, dynamic>>.from(result['site']);
      } else {
        return [Map<String, dynamic>.from(result['site'])];
      }
    }
    return null;
  }

  /// Get Trunked System Talkgroups (list, only unencrypted)
  Future<List<List<dynamic>>?> getTrsTalkgroups(int systemId) async {
    if (!(isLoggedIn && username != null && password != null)) {
      errorMessage = "Please login first.";
      notifyListeners();
      return null;
    }
    final wsdlUrl = "http://api.radioreference.com/soap2/?wsdl&v=latest&s=rpc";
    final authInfo = _buildAuthInfo(username!, password!);
    final result = await _soapRequest(wsdlUrl, 'getTrsTalkgroups', {
      'sid': systemId,
      'start': 0,
      'limit': 0,
      'filter': 0,
      'authInfo': authInfo,
    });
    if (result != null && result['talkgroup']) {
      final talkgroups = <List<dynamic>>[];
      if (result['talkgroup'] is List) {
        for (final tg in result['talkgroup']) {
          if (tg['enc'] == '0' || tg['enc'] == 0) {
            talkgroups.add([tg['tgDec'], tg['tgAlpha']]);
          }
        }
      } else {
        // Single talkgroup
        final tg = result['talkgroup'];
        if (tg['enc'] == '0' || tg['enc'] == 0) {
          talkgroups.add([tg['tgDec'], tg['tgAlpha']]);
        }
      }
      return talkgroups;
    }
    return null;
  }

  /// Create system TSV files (and supporting DB) in app's documents directory
  Future<void> createSystemTsvFiles(int systemId) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final sitesInfo = await getTrsSites(systemId);
      if (sitesInfo == null || sitesInfo.isEmpty) {
        errorMessage = "No sites found for this trunked system.";
        isLoading = false;
        notifyListeners();
        return;
      }
      final talkgroupsInfo = await getTrsTalkgroups(systemId);

      final dir = await getApplicationDocumentsDirectory();
      final systemFolder = Directory('${dir.path}/systems/$systemId');
      if (!await systemFolder.exists()) {
        await systemFolder.create(recursive: true);
      }

      // Write site TSVs
      for (final site in sitesInfo) {
        await _writeSiteTsv(systemId, site, systemFolder);
      }

      if (talkgroupsInfo != null && talkgroupsInfo.isNotEmpty) {
        await _writeTalkgroupsTsv(systemId, talkgroupsInfo, systemFolder);
      }

      isLoading = false;
      errorMessage = null;
      notifyListeners();
    } catch (e) {
      errorMessage = "Error creating system files: $e";
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _writeSiteTsv(int systemId, Map<String, dynamic> site, Directory folder) async {
    final siteId = site['siteId'];
    final file = File('${folder.path}/${systemId}_${siteId}_trunk.tsv');
    // Get control channels
    final siteFreqs = site['siteFreqs'];
    final List<dynamic> freqs;
    if (siteFreqs is List) {
      freqs = siteFreqs;
    } else if (siteFreqs != null) {
      freqs = [siteFreqs];
    } else {
      freqs = [];
    }
    final controlChannels = freqs
        .where((f) => f['use'] != null)
        .toList();
    controlChannels.sort((a, b) {
      final aIsPrimary = a['use'] == 'a' ? 1 : 2;
      final bIsPrimary = b['use'] == 'a' ? 1 : 2;
      return aIsPrimary.compareTo(bIsPrimary);
    });
    final controlChannelsStr = controlChannels.map((f) => f['freq'].toString()).join(',');

    final tsv = StringBuffer();
    tsv.writeln([
      "Sysname",
      "Control Channel List",
      "Offset",
      "NAC",
      "Modulation",
      "TGID Tags File",
      "Whitelist",
      "Blacklist",
      "Center Frequency"
    ].map((s) => '"$s"').join('\t'));
    tsv.writeln([
      systemId,
      controlChannelsStr,
      "0",
      "0",
      "cqpsk",
      "${folder.path}/${systemId}_talkgroups.tsv",
      "${folder.path}/${systemId}_whitelist.tsv",
      "${folder.path}/${systemId}_blacklist.tsv",
      ""
    ].map((s) => '"$s"').join('\t'));

    await file.writeAsString(tsv.toString());
  }

  Future<void> _writeTalkgroupsTsv(int systemId, List<List<dynamic>> talkgroups, Directory folder) async {
    final tsvFile = File('${folder.path}/${systemId}_talkgroups.tsv');
    final whitelistFile = File('${folder.path}/${systemId}_whitelist.tsv');
    final blacklistFile = File('${folder.path}/${systemId}_blacklist.tsv');

    final tsv = StringBuffer();
    for (final tg in talkgroups) {
      tsv.writeln('${tg[0]}\t${tg[1]}');
    }
    await tsvFile.writeAsString(tsv.toString());
    await whitelistFile.writeAsString('');
    await blacklistFile.writeAsString('');
  }
}