import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/device_utils.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  static const _storage = FlutterSecureStorage();
  static const String _hopaApDefaultIp = '192.168.4.1';
  static const String _hopaApIpPrefix = '192.168.4.';
  static const List<String> _hopaSsidHints = <String>['HOPA', 'ESP32', 'CAM'];

  static DateTime? _lastLocalNetworkProbeAt;
  static bool _lastLocalNetworkProbeValue = false;
  static DateTime? _skipGateStatusCloudUntil;
  static DateTime? _lastGateDnsLogAt;

  // Alege automat URL-ul în funcție de mediu: debug ⇒ local, release ⇒ producție
  static String get baseUrl {
    // Domeniul public al backend-ului (pentru producție)
    const production = 'https://hopa.tritech.ro/api/v1';

    // FOLOSESC PRODUCȚIA pentru funcționare reală:
    return production;
  }

  // Headers comuni pentru toate request-urile
  static Map<String, String> get headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  // Get auth headers cu token
  static Future<Map<String, String>> getAuthHeaders() async {
    final token = await _storage.read(key: 'auth_token');

    return {...headers, if (token != null) 'Authorization': 'Bearer $token'};
  }

  // Get auth headers cu token + device model
  static Future<Map<String, String>> getAuthHeadersWithDevice() async {
    final token = await _storage.read(key: 'auth_token');
    final deviceModel = await DeviceUtils.getDeviceModel();

    return {
      ...headers,
      if (token != null) 'Authorization': 'Bearer $token',
      'X-Device-Model': deviceModel, // Header custom cu modelul telefonului
    };
  }

  // Login cu cod de activare (pentru CLIENȚI)
  static Future<Map<String, dynamic>> loginWithCode(String code) async {
    try {
      final url = '$baseUrl/auth/login-code';
      final payload = {'code': code};

      print('🌐 HOPA CLIENT LOGIN DEBUG:');
      print('URL: $url');
      print('Headers: $headers');
      print('Payload: $payload');

      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode(payload),
      );

      print('Response Status: ${response.statusCode}');
      print('Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Salvează token-ul securizat
        if (data['token'] != null) {
          await _storage.write(key: 'auth_token', value: data['token']);
        }

        print('✅ Client Login SUCCESS: $data');
        return data;
      } else if (response.statusCode == 429) {
        print('⏳ Client Login RATE LIMITED');
        return {
          'success': false,
          'message': 'Prea multe încercări. Așteptați un minut.',
        };
      } else {
        final error = jsonDecode(response.body);
        print('❌ Client Login FAILED: $error');
        return {
          'success': false,
          'message': error['message'] ?? 'Eroare la autentificare',
        };
      }
    } catch (e) {
      print('🔥 Exception: $e');
      return {'success': false, 'message': 'Eroare de conexiune: $e'};
    }
  }

  // Login cu cod de activare (pentru INSTALATORI)
  static Future<Map<String, dynamic>> loginInstallerWithCode(
    String code,
  ) async {
    try {
      final url = '$baseUrl/auth/login-code-installer';
      final payload = {'code': code};

      print('🌐 HOPA INSTALLER LOGIN DEBUG:');
      print('URL: $url');
      print('Headers: $headers');
      print('Payload: $payload');

      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode(payload),
      );

      print('Response Status: ${response.statusCode}');
      print('Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Salvează token-ul securizat
        if (data['token'] != null) {
          await _storage.write(key: 'auth_token', value: data['token']);
        }

        print('✅ Installer Login SUCCESS: $data');
        return data;
      } else if (response.statusCode == 429) {
        print('⏳ Installer Login RATE LIMITED');
        return {
          'success': false,
          'message': 'Prea multe încercări. Așteptați un minut.',
        };
      } else {
        final error = jsonDecode(response.body);
        print('❌ Installer Login FAILED: $error');
        return {
          'success': false,
          'message': error['message'] ?? 'Eroare la autentificare',
        };
      }
    } catch (e) {
      print('🔥 Exception: $e');
      return {'success': false, 'message': 'Eroare de conexiune: $e'};
    }
  }

  // Get gates config
  static Future<Map<String, dynamic>> getGatesConfig() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/client/gates-config'),
        headers: await getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        throw Exception(
          'Sesiune expirată. Te rugăm să te autentifici din nou.',
        );
      } else {
        throw Exception('Eroare la obținerea configurației');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  // Control gate - ULTRA FAST
  static Future<Map<String, dynamic>> controlGate(
    String? gateId,
    String action,
  ) async {
    const int maxRetries = 2; // redus
    const Duration retryDelay = Duration(milliseconds: 500); // mult mai rapid

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final response = await http
            .post(
              Uri.parse('$baseUrl/gate/control'),
              headers: await getAuthHeaders(),
              body: jsonEncode({
                if (gateId != null) 'gate_id': gateId,
                'action': action, // 'open', 'close', sau 'toggle'
              }),
            )
            .timeout(
              const Duration(seconds: 3), // timeout mai mic
              onTimeout: () {
                throw TimeoutException('Timeout 3 secunde');
              },
            );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          print('✅ Gate control response (încercare $attempt): $data');
          return data;
        } else if (response.statusCode == 500 || response.statusCode == 502) {
          // Server errors - retry
          print(
            '⚠️ Server error ${response.statusCode} (încercare $attempt/$maxRetries)',
          );
          if (attempt < maxRetries) {
            await Future.delayed(retryDelay);
            continue;
          }
        } else {
          final error = jsonDecode(response.body);
          throw Exception(error['message'] ?? 'Eroare la controlul porții');
        }
      } on TimeoutException catch (e) {
        print('⏱️ Timeout (încercare $attempt/$maxRetries): $e');
        if (attempt < maxRetries) {
          await Future.delayed(retryDelay);
          continue;
        }
        throw Exception(
          'Conexiunea a expirat. Verifică conexiunea la internet.',
        );
      } catch (e) {
        print('🔴 Gate control error (încercare $attempt/$maxRetries): $e');
        if (attempt < maxRetries && e.toString().contains('SocketException')) {
          await Future.delayed(retryDelay);
          continue;
        }
        throw Exception(
          'Eroare de conexiune: ${e.toString().replaceAll('Exception: ', '')}',
        );
      }
    }

    throw Exception('Nu s-a putut executa comanda după $maxRetries încercări');
  }

  // Get Shelly devices
  static Future<Map<String, dynamic>> getShellyDevices() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/shelly/devices'),
        headers: await getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        // Sesiune expirată sau token invalid
        throw Exception(
          'Sesiune expirată. Te rugăm să te autentifici din nou.',
        );
      } else {
        // Încearcă să extragi mesajul de eroare din răspuns
        try {
          final error = jsonDecode(response.body);
          throw Exception(
            error['message'] ?? 'Eroare la obținerea dispozitivelor',
          );
        } catch (_) {
          throw Exception('Eroare la obținerea dispozitivelor');
        }
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  // ==================== HOPA Pairing / Devices ====================

  static Map<String, dynamic> _decodeJsonMap(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return <String, dynamic>{};
    try {
      final parsed = jsonDecode(trimmed);
      if (parsed is Map<String, dynamic>) return parsed;
      if (parsed is Map) return Map<String, dynamic>.from(parsed);
      return <String, dynamic>{'raw': trimmed};
    } catch (_) {
      return <String, dynamic>{'raw': trimmed};
    }
  }

  static String? _normalizeHost(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return null;

    try {
      final withScheme = raw.startsWith('http://') || raw.startsWith('https://')
          ? raw
          : 'http://$raw';
      final uri = Uri.parse(withScheme);
      if (uri.host.isEmpty) return null;
      if (uri.hasPort) return '${uri.host}:${uri.port}';
      return uri.host;
    } catch (_) {
      return null;
    }
  }

  static Uri _buildLocalUri(String host, String path) {
    final normalized = host.trim();
    if (normalized.startsWith('http://') || normalized.startsWith('https://')) {
      final base = Uri.parse(normalized);
      return base.replace(path: path, query: null, fragment: null);
    }
    return Uri.parse('http://$normalized$path');
  }

  static Future<String?> _getWifiIpSafe() async {
    try {
      final wifiIp = (await NetworkInfo().getWifiIP() ?? '').trim();
      if (wifiIp.isEmpty) return null;
      return wifiIp;
    } catch (_) {
      return null;
    }
  }

  static bool _isLikelyPrivateLanHost(String host) {
    final normalized = _normalizeHost(host);
    if (normalized == null) return false;
    final ip = normalized.split(':').first;
    return ip.startsWith('192.168.') ||
        ip.startsWith('10.') ||
        ip.startsWith('172.');
  }

  static bool _same24Subnet(String ipA, String ipB) {
    final a = ipA.split('.');
    final b = ipB.split('.');
    if (a.length != 4 || b.length != 4) return false;
    return a[0] == b[0] && a[1] == b[1] && a[2] == b[2];
  }

  static Future<bool> _isOnHopaLocalNetwork({bool forceRefresh = false}) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _lastLocalNetworkProbeAt != null &&
        now.difference(_lastLocalNetworkProbeAt!) <
            const Duration(seconds: 5)) {
      return _lastLocalNetworkProbeValue;
    }

    bool isLocal = false;
    try {
      final info = NetworkInfo();
      final wifiIp = (await info.getWifiIP() ?? '').trim();
      if (wifiIp.startsWith(_hopaApIpPrefix)) {
        isLocal = true;
      } else {
        final ssidRaw = (await info.getWifiName() ?? '').toUpperCase();
        final ssid = ssidRaw.replaceAll('"', '');
        isLocal = _hopaSsidHints.any((hint) => ssid.contains(hint));
      }
    } catch (_) {
      // Păstrăm fallback-ul pe valoarea cache-uită.
      isLocal = _lastLocalNetworkProbeValue;
    }

    _lastLocalNetworkProbeAt = now;
    _lastLocalNetworkProbeValue = isLocal;
    return isLocal;
  }

  static Future<List<String>> _resolveLocalPairHosts() async {
    final prefs = await SharedPreferences.getInstance();
    final hosts = <String>[];
    final onLocalHopaNetwork = await _isOnHopaLocalNetwork();

    void addHost(String? raw) {
      final host = _normalizeHost(raw);
      if (host != null && !hosts.contains(host)) {
        hosts.add(host);
      }
    }

    if (onLocalHopaNetwork) {
      // Când telefonul e pe AP-ul HUB, încercăm prima dată IP-ul local standard.
      addHost(_hopaApDefaultIp);
    }

    addHost(prefs.getString('hopa_device_ip'));

    if (!onLocalHopaNetwork) {
      try {
        final response = await http
            .get(
              Uri.parse('$baseUrl/client/data'),
              headers: await getAuthHeaders(),
            )
            .timeout(const Duration(seconds: 3));

        if (response.statusCode == 200) {
          final data = _decodeJsonMap(response.body);
          String? ip = (data['device_ip_address'] ?? '').toString();
          final clientData = data['client'];
          if ((ip.isEmpty || ip == 'null') && clientData is Map) {
            ip = (clientData['device_ip_address'] ?? '').toString();
          }

          final normalized = _normalizeHost(ip);
          if (normalized != null) {
            await prefs.setString('hopa_device_ip', normalized);
            addHost(normalized);
          }
        }
      } catch (_) {
        // Ignorăm erorile de cloud; fallback-ul local continuă.
      }
    }

    if (!onLocalHopaNetwork) {
      addHost(_hopaApDefaultIp);
    }

    return hosts;
  }

  static Future<void> _rememberLocalHost(String host) async {
    final normalized = _normalizeHost(host);
    if (normalized == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('hopa_device_ip', normalized);
  }

  static Future<Map<String, dynamic>> _startHopaPairingDirect({
    required String host,
    required int duration,
    required String target,
    String? deviceType,
    int? remoteLimit,
    int? remoteSlot,
  }) async {
    final response = await http
        .post(
          _buildLocalUri(host, '/hopa/pairing'),
          headers: headers,
          body: jsonEncode({
            'action': 'start',
            'duration': duration,
            if (target != 'any') 'target': target,
            if ((deviceType ?? '').trim().isNotEmpty) 'device_type': deviceType,
            if ((remoteLimit ?? 0) > 0) 'remote_limit': remoteLimit,
            if ((remoteSlot ?? 0) > 0) 'remote_slot': remoteSlot,
          }),
        )
        .timeout(
          const Duration(seconds: 3),
          onTimeout: () =>
              throw TimeoutException('HUB local nu a răspuns în 3 sec ($host)'),
        );

    final data = _decodeJsonMap(response.body);
    final statusOk = response.statusCode >= 200 && response.statusCode < 300;
    final deviceAccepted =
        data['success'] == null ||
        data['success'] == true ||
        data['ok'] == true;

    if (statusOk && deviceAccepted) {
      await _rememberLocalHost(host);
      return {
        'success': true,
        'message': data['message'] ?? 'Pairing mode activat local',
        'mode': 'local_direct',
        'device_ip': host,
        ...data,
      };
    }

    throw Exception(
      data['message'] ??
          'HUB a respins pairing-ul local (HTTP ${response.statusCode})',
    );
  }

  static Future<Map<String, dynamic>> _startHopaPairingCloud({
    required int clientId,
    required int duration,
    required String target,
    String? deviceType,
    int? remoteLimit,
    int? remoteSlot,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/hopa/pairing/start'),
          headers: await getAuthHeaders(),
          body: jsonEncode({
            'client_id': clientId,
            'duration': duration,
            if (target != 'any') 'target': target,
            if ((deviceType ?? '').trim().isNotEmpty) 'device_type': deviceType,
            if ((remoteLimit ?? 0) > 0) 'remote_limit': remoteLimit,
            if ((remoteSlot ?? 0) > 0) 'remote_slot': remoteSlot,
          }),
        )
        .timeout(const Duration(seconds: 8));

    final data = _decodeJsonMap(response.body);
    final statusOk = response.statusCode >= 200 && response.statusCode < 300;
    final accepted = data['success'] == null || data['success'] == true;

    if (statusOk && accepted) {
      return {
        'success': true,
        'message': data['message'] ?? 'Pairing mode activat prin cloud',
        'mode': 'cloud_api',
        ...data,
      };
    }

    throw Exception(
      data['message'] ??
          'Pairing indisponibil prin cloud (HTTP ${response.statusCode})',
    );
  }

  static Future<Map<String, dynamic>> startHopaPairing({
    required int clientId,
    int duration = 60,
    String target = 'tag',
    String? deviceType,
    int? remoteLimit,
    int? remoteSlot,
  }) async {
    final onLocalHopaNetwork = await _isOnHopaLocalNetwork();
    final hosts = await _resolveLocalPairHosts();
    final localErrors = <String>[];

    for (final host in hosts) {
      try {
        return await _startHopaPairingDirect(
          host: host,
          duration: duration,
          target: target,
          deviceType: deviceType,
          remoteLimit: remoteLimit,
          remoteSlot: remoteSlot,
        );
      } catch (e) {
        localErrors.add(
          '${host}: ${e.toString().replaceAll('Exception: ', '').trim()}',
        );
      }
    }

    final localError = localErrors.join(' | ').trim();
    final wifiIp = await _getWifiIpSafe();
    if (wifiIp == null) {
      final detailsLocal = localError.isNotEmpty
          ? ' Detalii locale: $localError.'
          : '';
      throw Exception(
        'Telefonul este pe date mobile (5G/4G), nu pe Wi-Fi local.$detailsLocal Conectează telefonul la aceeași rețea Wi-Fi cu HUB-ul (ex: DIGI-x4ts sau HOPA-M) și încearcă din nou.',
      );
    }

    final privateHosts = hosts
        .where(_isLikelyPrivateLanHost)
        .map((h) => _normalizeHost(h)!.split(':').first)
        .toSet();
    final hasSameSubnet = privateHosts.any((ip) => _same24Subnet(wifiIp, ip));
    if (!onLocalHopaNetwork && privateHosts.isNotEmpty && !hasSameSubnet) {
      final detailsLocal = localError.isNotEmpty
          ? ' Detalii locale: $localError.'
          : '';
      throw Exception(
        'Telefonul nu este în aceeași rețea locală cu HUB-ul (Wi-Fi telefon: $wifiIp, HUB: ${privateHosts.join(', ')}).$detailsLocal Conectează telefonul la Wi-Fi-ul unde este HUB-ul și încearcă din nou.',
      );
    }

    // Dacă telefonul este pe AP-ul HUB/local, cloud-ul poate să nu fie accesibil (normal).
    if (onLocalHopaNetwork) {
      final detailsLocal = localError.isNotEmpty
          ? ' Detalii locale: $localError.'
          : '';
      throw Exception(
        'Nu s-a putut porni pairing-ul local.$detailsLocal Verifică să fii conectat la rețeaua HUB și încearcă din nou.',
      );
    }

    try {
      return await _startHopaPairingCloud(
        clientId: clientId,
        duration: duration,
        target: target,
        deviceType: deviceType,
        remoteLimit: remoteLimit,
        remoteSlot: remoteSlot,
      );
    } catch (e) {
      final cloudError = e.toString().replaceAll('Exception: ', '');
      final detailsLocal = localError.isNotEmpty ? ' Local: $localError.' : '';
      final detailsCloud = cloudError.isNotEmpty ? ' Cloud: $cloudError.' : '';
      throw Exception(
        'Nu s-a putut porni pairing-ul.$detailsLocal$detailsCloud',
      );
    }
  }

  static Future<Map<String, dynamic>> restartHopaHubLocal() async {
    final hosts = await _resolveLocalPairHosts();
    var localError = '';

    for (final host in hosts) {
      try {
        final response = await http
            .post(
              _buildLocalUri(host, '/restart'),
              headers: headers,
              body: jsonEncode({'action': 'restart'}),
            )
            .timeout(const Duration(seconds: 5));

        final data = _decodeJsonMap(response.body);
        final statusOk =
            response.statusCode >= 200 && response.statusCode < 300;
        final accepted =
            data['success'] == null ||
            data['success'] == true ||
            data['ok'] == true;

        if (statusOk && accepted) {
          await _rememberLocalHost(host);
          return {
            'success': true,
            'message': data['message'] ?? 'Restart trimis către HUB',
            'mode': 'local_direct',
            'device_ip': host,
            ...data,
          };
        }

        throw Exception(
          data['message'] ??
              'HUB a respins restart-ul local (HTTP ${response.statusCode})',
        );
      } catch (e) {
        localError = e.toString().replaceAll('Exception: ', '');
      }
    }

    final details = localError.isNotEmpty ? ' Detalii: $localError' : '';
    throw Exception('Nu s-a putut trimite restart local către HUB.$details');
  }

  static Future<Map<String, dynamic>> clearHopaPairingLocal({
    String? tagMac,
    String? deviceType,
    String? deviceMac,
    int? remoteSlot,
  }) async {
    final wifiIp = await _getWifiIpSafe();
    if (wifiIp == null) {
      throw Exception(
        'Telefonul este pe date mobile (5G/4G). Pentru desperechere locală conectează-l la Wi-Fi-ul HUB.',
      );
    }

    final hosts = await _resolveLocalPairHosts();
    var localError = '';

    for (final host in hosts) {
      try {
        final response = await http
            .post(
              _buildLocalUri(host, '/hopa/unpair'),
              headers: headers,
              body: jsonEncode({
                'action': 'clear',
                if ((tagMac ?? '').trim().isNotEmpty) 'tag_mac': tagMac,
                if ((deviceType ?? '').trim().isNotEmpty)
                  'device_type': deviceType,
                if ((deviceMac ?? '').trim().isNotEmpty)
                  'device_mac': deviceMac,
                if ((remoteSlot ?? 0) > 0) 'remote_slot': remoteSlot,
              }),
            )
            .timeout(const Duration(seconds: 5));

        final data = _decodeJsonMap(response.body);
        final statusOk =
            response.statusCode >= 200 && response.statusCode < 300;
        final accepted =
            data['success'] == null ||
            data['success'] == true ||
            data['ok'] == true;

        if (statusOk && accepted) {
          await _rememberLocalHost(host);
          return {
            'success': true,
            'message': data['message'] ?? 'TAG desperecheat local',
            'mode': 'local_direct',
            'device_ip': host,
            ...data,
          };
        }

        throw Exception(
          data['message'] ??
              'HUB a respins desperecherea locală (HTTP ${response.statusCode})',
        );
      } catch (e) {
        localError = e.toString().replaceAll('Exception: ', '');
      }
    }

    final details = localError.isNotEmpty ? ' Detalii: $localError' : '';
    throw Exception(
      'Nu s-a putut face desperecherea locală. Apropie-te de HUB și încearcă din nou.$details',
    );
  }

  static Future<Map<String, dynamic>> getHopaHubStatusLocal() async {
    final hosts = await _resolveLocalPairHosts();
    var localError = '';

    for (final host in hosts) {
      try {
        final response = await http
            .get(_buildLocalUri(host, '/status'), headers: headers)
            .timeout(const Duration(seconds: 5));

        final data = _decodeJsonMap(response.body);
        final statusOk =
            response.statusCode >= 200 && response.statusCode < 300;
        if (statusOk) {
          await _rememberLocalHost(host);
          return {
            'success': true,
            'mode': 'local_direct',
            'device_ip': host,
            ...data,
          };
        }

        throw Exception(
          data['message'] ??
              'HUB status indisponibil (HTTP ${response.statusCode})',
        );
      } catch (e) {
        localError = e.toString().replaceAll('Exception: ', '');
      }
    }

    final details = localError.isNotEmpty ? ' Detalii: $localError' : '';
    throw Exception('Nu s-a putut citi statusul local HUB.$details');
  }

  static Future<Map<String, dynamic>> enrollHopaDevice({
    required int clientId,
    required String macAddress,
    String deviceType = 'tag',
    String? deviceName,
    int rssi = -45,
  }) async {
    try {
      final payload = <String, dynamic>{
        'client_id': clientId,
        'mac_address': macAddress,
        'rssi': rssi,
        'device_type': deviceType,
      };
      if ((deviceName ?? '').trim().isNotEmpty) {
        payload['device_name'] = deviceName!.trim();
      }

      final response = await http.post(
        Uri.parse('$baseUrl/hopa/pairing/enroll'),
        headers: await getAuthHeaders(),
        body: jsonEncode(payload),
      );

      final data = _decodeJsonMap(response.body);
      if ((response.statusCode == 200 || response.statusCode == 201) &&
          data['success'] == true) {
        return data;
      }

      throw Exception(data['message'] ?? 'Nu s-a putut adăuga TAG-ul');
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  static Future<Map<String, dynamic>> sendHopaOfflineAlert(int deviceId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/hopa/device/$deviceId/offline-alert'),
        headers: await getAuthHeaders(),
      );

      final data = _decodeJsonMap(response.body);
      if ((response.statusCode == 200 || response.statusCode == 201) &&
          data['success'] == true) {
        return data;
      }

      throw Exception(data['message'] ?? 'Nu s-a putut trimite alerta offline');
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  static Future<Map<String, dynamic>> getHopaDevices(int clientId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/hopa/devices/$clientId'),
        headers: await getAuthHeaders(),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return data;
      }

      throw Exception(
        data['message'] ?? 'Eroare la obținerea dispozitivelor HOPA',
      );
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  static Future<Map<String, dynamic>> updateHopaDevice(
    int deviceId,
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/hopa/device/$deviceId'),
        headers: await getAuthHeaders(),
        body: jsonEncode(payload),
      );

      final data = jsonDecode(response.body);
      if ((response.statusCode == 200 || response.statusCode == 201) &&
          data['success'] == true) {
        return data;
      }

      throw Exception(
        data['message'] ?? 'Eroare la actualizarea dispozitivului HOPA',
      );
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  static Future<Map<String, dynamic>> removeHopaDevice(int deviceId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/hopa/device/$deviceId'),
        headers: await getAuthHeaders(),
      );

      final rawBody = response.body.trim();
      final data = rawBody.isEmpty
          ? <String, dynamic>{'success': true}
          : jsonDecode(rawBody) as Map<String, dynamic>;
      if ((response.statusCode == 200 || response.statusCode == 204) &&
          (data['success'] == null || data['success'] == true)) {
        return data;
      }

      throw Exception(
        data['message'] ?? 'Eroare la ștergerea dispozitivului HOPA',
      );
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  // Send SOS
  static Future<Map<String, dynamic>> sendSOS(String message) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/sos/send'),
        headers: await getAuthHeaders(),
        body: jsonEncode({'message': message}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Eroare la trimiterea SOS');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  // Update FCM token for push notifications
  static Future<Map<String, dynamic>> updateFcmToken(String token) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/push/update-token'),
        headers: await getAuthHeaders(),
        body: jsonEncode({'fcm_token': token}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Eroare la actualizarea token-ului FCM');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  // Update notification settings
  static Future<Map<String, dynamic>> updateNotificationSettings(
    Map<String, bool> settings,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/notifications/settings'),
        headers: await getAuthHeaders(),
        body: jsonEncode(settings),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Eroare la actualizarea setărilor');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  // Get subscription status from backend
  static Future<Map<String, dynamic>> getSubscriptionStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/subscription/status'),
        headers: await getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        throw Exception(
          'Sesiune expirată. Te rugăm să te autentifici din nou.',
        );
      } else {
        throw Exception('Eroare la obținerea statusului abonament');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  // Get subscription plans
  static Future<List<dynamic>> getSubscriptionPlans() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/subscription/plans'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['data'] ?? [];
      } else {
        throw Exception('Eroare la obținerea planurilor');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  // Upgrade subscription
  static Future<Map<String, dynamic>> upgradeSubscription(
    int planId,
    int extraCount,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/subscription/upgrade'),
        headers: await getAuthHeaders(),
        body: jsonEncode({'plan_id': planId, 'hopa_extra_count': extraCount}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Eroare la upgrade');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  // Activate PRO trial via backend
  static Future<Map<String, dynamic>> activateProTrialBackend() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/subscription/trial/start'),
        headers: await getAuthHeaders(),
        body: jsonEncode({}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Eroare la activarea trial-ului');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  // Logout
  static Future<void> logout() async {
    try {
      await http.post(
        Uri.parse('$baseUrl/logout'),
        headers: await getAuthHeaders(),
      );
    } catch (e) {
      // Ignore errors on logout
    } finally {
      // Clear local data
      final prefs = await SharedPreferences.getInstance();
      await _storage.delete(key: 'auth_token');
      await prefs.clear();
    }
  }

  // Control poartă - deschide poarta
  static Future<Map<String, dynamic>> openGate() async {
    try {
      final url = '$baseUrl/gate/open';
      final response = await http.post(
        Uri.parse(url),
        headers: await getAuthHeaders(),
        body: json.encode({}),
      );

      print('Open gate response: ${response.statusCode}');

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': 'Poarta s-a deschis cu succes',
          'gate_status': 'open',
        };
      }

      return {'success': false, 'message': 'Eroare la deschiderea porții'};
    } catch (e) {
      print('Error opening gate: $e');
      return {'success': false, 'message': 'Eroare de conexiune'};
    }
  }

  // Control poartă - închide poarta
  static Future<Map<String, dynamic>> closeGate() async {
    try {
      final url = '$baseUrl/gate/close';
      final response = await http.post(
        Uri.parse(url),
        headers: await getAuthHeaders(),
        body: json.encode({}),
      );

      print('Close gate response: ${response.statusCode}');

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': 'Poarta s-a închis cu succes',
          'gate_status': 'closed',
        };
      }

      return {'success': false, 'message': 'Eroare la închiderea porții'};
    } catch (e) {
      print('Error closing gate: $e');
      return {'success': false, 'message': 'Eroare de conexiune'};
    }
  }

  // Verifică statusul curent al porții
  static Future<Map<String, dynamic>> getGateStatus() async {
    final now = DateTime.now();
    if (_skipGateStatusCloudUntil != null &&
        now.isBefore(_skipGateStatusCloudUntil!)) {
      return {
        'success': false,
        'state': 'unknown',
        'sensor_active': false,
        'provisioned': true,
      };
    }

    if (await _isOnHopaLocalNetwork()) {
      return {
        'success': false,
        'state': 'unknown',
        'sensor_active': false,
        'provisioned': true,
      };
    }

    try {
      final url = '$baseUrl/gate/status';
      final response = await http.get(
        Uri.parse(url),
        headers: await getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'state':
              data['status'] ??
              data['state'] ??
              data['gate_status'] ??
              'unknown',
          'sensor_active': data['sensor_active'] ?? false,
          // Dacă backend nu trimite explicit, considerăm provisionat dacă există oricare din câmpurile de stare
          'provisioned':
              data['provisioned'] ??
              (data['state'] != null || data['gate_status'] != null),
          'last_action': data['last_action'],
          'timestamp': data['timestamp'],
        };
      }

      // Fallback: nu blocăm aplicația
      return {
        'success': false,
        'state': 'unknown',
        'sensor_active': false,
        'provisioned': true,
      };
    } on SocketException catch (e) {
      final err = e.toString().toLowerCase();
      if (err.contains('failed host lookup') ||
          err.contains('no address associated')) {
        _skipGateStatusCloudUntil = DateTime.now().add(
          const Duration(seconds: 45),
        );
        final shouldLog =
            _lastGateDnsLogAt == null ||
            DateTime.now().difference(_lastGateDnsLogAt!) >
                const Duration(seconds: 30);
        if (shouldLog) {
          _lastGateDnsLogAt = DateTime.now();
          print('Gate status DNS fail -> skip cloud polling 45s');
        }
      }
      return {
        'success': false,
        'state': 'unknown',
        'sensor_active': false,
        'provisioned': true,
      };
    } catch (e) {
      print('Error getting gate status: $e');
      // Fallback în caz de eroare rețea: mergem înainte în app
      return {
        'success': false,
        'state': 'unknown',
        'sensor_active': false,
        'provisioned': true,
      };
    }
  }

  //=== GATE STATISTICS ===
  static Future<Map<String, dynamic>> getGateStats(String period) async {
    try {
      final url = '$baseUrl/gate/stats?period=$period';
      final response = await http.get(
        Uri.parse(url),
        headers: await getAuthHeaders(),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Eroare la statistici');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  // Guest Pass Methods
  static Future<Map<String, dynamic>> createGuestPass(
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/guest-passes'),
        headers: await getAuthHeaders(),
        body: jsonEncode(data),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Eroare la crearea invitației');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  static Future<Map<String, dynamic>> getGuestPasses() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/guest-passes'),
        headers: await getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Eroare la obținerea invitațiilor');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  static Future<Map<String, dynamic>> updateGuestPass(
    int id,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/guest-passes/$id'),
        headers: await getAuthHeaders(),
        body: jsonEncode(data),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(
          error['message'] ?? 'Eroare la actualizarea invitației',
        );
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  // Dezactivează guest pass (setează is_active = false)
  static Future<Map<String, dynamic>> deactivateGuestPass(int id) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/guest-passes/$id/reject'),
        headers: await getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(
          error['message'] ?? 'Eroare la dezactivarea invitației',
        );
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  static Future<Map<String, dynamic>> deleteGuestPass(int id) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/guest-passes/$id'),
        headers: await getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Eroare la ștergerea invitației');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  // Obține cererile SOS pentru client
  static Future<List<dynamic>> getSosRequestsForClient() async {
    try {
      final url =
          '$baseUrl/sos/notifications'; // Changed endpoint to match Laravel
      final response = await http.get(
        Uri.parse(url),
        headers: await getAuthHeaders(),
      );

      print('🌐 DEBUG SOS Requests:');
      print('URL: $url');
      print('Status Code: ${response.statusCode}');
      print('Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['notifications'] is List) {
          return data['notifications'];
        } else {
          throw Exception(data['message'] ?? 'Răspuns invalid de la server');
        }
      } else if (response.statusCode == 401) {
        throw Exception(
          'Sesiune expirată. Te rugăm să te autentifici din nou.',
        );
      } else {
        final error = jsonDecode(response.body);
        throw Exception(
          error['message'] ?? 'Eroare la obținerea cererilor SOS',
        );
      }
    } catch (e) {
      print('🔥 Exception in getSosRequestsForClient: $e');
      throw Exception('Eroare de conexiune: $e');
    }
  }

  // Confirmă programarea SOS
  static Future<Map<String, dynamic>> confirmSosAppointment(
    String sosId,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/sos/notifications/$sosId/confirm'),
        headers: await getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        throw Exception(
          'Sesiune expirată. Te rugăm să te autentifici din nou.',
        );
      } else {
        final error = jsonDecode(response.body);
        throw Exception(
          error['message'] ?? 'Eroare la confirmarea programării',
        );
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  // Răspunde unui instalator pentru o notificare SOS
  static Future<Map<String, dynamic>> replyToInstaller(
    String sosNotificationId,
    String messageContent,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/sos/notifications/$sosNotificationId/reply'),
        headers: await getAuthHeaders(),
        body: jsonEncode({'message_content': messageContent}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        throw Exception(
          'Sesiune expirată. Te rugăm să te autentifici din nou.',
        );
      } else {
        final error = jsonDecode(response.body);
        throw Exception(
          error['message'] ??
              'Eroare la trimiterea răspunsului către instalator',
        );
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  static Future<List<dynamic>> getPushNotificationHistory({
    int limit = 50,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/push/history?limit=$limit'),
        headers: await getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['notifications'] ?? [];
      } else if (response.statusCode == 401) {
        throw Exception(
          'Sesiune expirată. Te rugăm să te autentifici din nou.',
        );
      } else {
        final error = jsonDecode(response.body);
        throw Exception(
          error['message'] ?? 'Eroare la obținerea notificărilor',
        );
      }
    } catch (e) {
      print('🔥 Exception getPushNotificationHistory: $e');
      throw Exception('Eroare de conexiune: $e');
    }
  }

  // Reprogramează o programare SOS cu dată și oră nouă
  static Future<Map<String, dynamic>> rescheduleSosAppointment(
    String sosId,
    DateTime newDate,
    String newTime,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/sos/notifications/$sosId/reschedule'),
        headers: await getAuthHeaders(),
        body: jsonEncode({
          'appointment_date':
              '${newDate.year}-${newDate.month.toString().padLeft(2, '0')}-${newDate.day.toString().padLeft(2, '0')}',
          'appointment_time': newTime,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Eroare la reprogramare');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  // Anulează sau marchează pentru reprogramare o programare SOS
  static Future<Map<String, dynamic>> cancelSosAppointment(
    String sosId,
    bool reschedule,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/sos/notifications/$sosId/cancel'),
        headers: await getAuthHeaders(),
        body: jsonEncode({'action': reschedule ? 'reschedule' : 'cancel'}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Eroare la anularea programării');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  // Șterge o notificare push
  static Future<Map<String, dynamic>> deletePushNotification(
    String notificationId,
  ) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/push/notifications/$notificationId'),
        headers: await getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Eroare la ștergerea notificării');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  // Șterge toate notificările push - MODIFICAT să accepte tip
  static Future<Map<String, dynamic>> deleteAllPushNotifications({
    String? type,
  }) async {
    try {
      // Adăugăm parametrul type în URL dacă e specificat
      String url = '$baseUrl/push/notifications';
      if (type != null) {
        url += '?type=$type';
      }

      final response = await http.delete(
        Uri.parse(url),
        headers: await getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(
          error['message'] ?? 'Eroare la ștergerea notificărilor',
        );
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  // Șterge un mesaj SOS specific
  static Future<Map<String, dynamic>> deleteSosMessage(
    String notificationId,
  ) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/sos/notifications/$notificationId'),
        headers: await getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Eroare la ștergerea mesajului');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  // Șterge toate mesajele SOS (marchează ca arhivate) - FOLOSIM POST
  static Future<Map<String, dynamic>> deleteAllSosMessages() async {
    try {
      // SCHIMBAT din DELETE în POST cu action=archive_all
      final response = await http.post(
        Uri.parse('$baseUrl/sos/notifications/archive-all'),
        headers: await getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Eroare la arhivarea mesajelor');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  //=== NEW: Request activation code via email (public endpoint)
  static Future<Map<String, dynamic>> requestActivationCode(
    String email,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/activation/send'),
        headers: headers,
        body: jsonEncode({'email': email}),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return jsonDecode(response.body);
      }
    } catch (e) {
      return {'success': false, 'message': 'Eroare de conexiune: $e'};
    }
  }

  //=== SHELLY: Switch ON/OFF via backend EMQX HTTP API ===
  static Future<Map<String, dynamic>> shellySwitch({
    required bool on,
    String? deviceId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // FOLOSIM CODUL HOPA (71BDA...) în loc de shelly_device_id
      String? hopaCode = deviceId ?? prefs.getString('hopa_device_code');

      // DEBUG
      print('🔍 DEBUG HOPA Device Code: $hopaCode');

      // Dacă nu e în cache, îl cerem de la backend
      if (hopaCode == null || hopaCode.isEmpty) {
        try {
          final response = await http
              .get(
                Uri.parse('$baseUrl/client/data'),
                headers: await getAuthHeaders(),
              )
              .timeout(const Duration(seconds: 5));

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            hopaCode = data['client']?['hopa_device_code'];
            if (hopaCode != null && hopaCode.isNotEmpty) {
              await prefs.setString('hopa_device_code', hopaCode);
            }
          }
        } catch (e) {
          print('⚠️ Nu am putut obține HOPA code de la backend: $e');
        }
      }

      if (hopaCode == null || hopaCode.isEmpty) {
        throw Exception('Lipsește HOPA device code. Relogați-vă.');
      }

      // Trimite comanda folosind codul HOPA (71BDA0001)
      final response = await http
          .post(
            Uri.parse('$baseUrl/shelly/switch'),
            headers: await getAuthHeadersWithDevice(), // Cu modelul telefonului
            body: jsonEncode({
              'id': hopaCode, // Folosim codul HOPA direct
              'on': on,
            }),
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException('Timeout 10 secunde'),
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      }

      // Returnează eroare cu detalii
      return {
        'ok': false,
        'status': response.statusCode,
        'error': response.body,
      };
    } on TimeoutException catch (e) {
      throw Exception('Conexiunea a expirat: $e');
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  //=== NEW: Regenerate activation code via email (public endpoint)
  static Future<Map<String, dynamic>> regenerateActivationCode(
    String email,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/activation/send'),
        headers: headers,
        body: jsonEncode({'email': email}),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Eroare la regenerarea codului');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  // ==================== INSTALLER API ENDPOINTS ====================

  /// Get installer statistics
  static Future<Map<String, dynamic>> getInstallerStats() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/installer/stats'),
        headers: await getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        throw Exception('Sesiune expirată');
      } else {
        throw Exception('Eroare la obținerea statisticilor');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  /// Get installer clients
  static Future<List<dynamic>> getInstallerClients() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/installer/clients'),
        headers: await getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['data'] ?? [];
      } else {
        throw Exception('Eroare la obținerea clienților');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  /// Get installer employees (sub-installers)
  static Future<List<dynamic>> getInstallerEmployees() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/installer/sub-installers'),
        headers: await getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['data'] ?? [];
      } else {
        throw Exception('Eroare la obținerea angajaților');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  /// Add client (installer creates)
  static Future<Map<String, dynamic>> addInstallerClient(
    Map<String, dynamic> data,
  ) async {
    try {
      print('🌐 ADD CLIENT DEBUG:');
      print('URL: $baseUrl/installer/clients');
      print('Payload: $data');

      final response = await http.post(
        Uri.parse('$baseUrl/installer/clients'),
        headers: await getAuthHeaders(),
        body: jsonEncode(data),
      );

      print('Response Status: ${response.statusCode}');
      print('Response Body: ${response.body}');

      if (response.statusCode == 201 || response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        print('❌ API Error: $error');
        
        // Extrage erorile detaliate de validare (422)
        String errorMsg = error['message'] ?? 'Eroare la crearea clientului';
        if (error['errors'] != null && error['errors'] is Map) {
          final validationErrors = <String>[];
          (error['errors'] as Map).forEach((field, messages) {
            if (messages is List) {
              validationErrors.addAll(messages.map((m) => m.toString()));
            }
          });
          if (validationErrors.isNotEmpty) {
            errorMsg = validationErrors.join('\n');
          }
        }
        
        throw Exception(errorMsg);
      }
    } catch (e) {
      print('🔥 Exception in addInstallerClient: $e');
      rethrow;
    }
  }

  // Șterge un client complet (pentru instalatori)
  static Future<Map<String, dynamic>> deleteClient(int clientId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/installer/clients/$clientId'),
        headers: await getAuthHeaders(),
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        return jsonDecode(
          response.body.isNotEmpty ? response.body : '{"success": true}',
        );
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Eroare la ștergerea clientului');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  /// Update client with Shelly device_id after wizard completes
  static Future<Map<String, dynamic>> updateClientShellyDevice(
    int clientId,
    String shellyDeviceId,
  ) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/installer/clients/$clientId'),
        headers: await getAuthHeaders(),
        body: jsonEncode({'shelly_device_id': shellyDeviceId}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Eroare la actualizarea device ID');
      }
    } catch (e) {
      throw Exception('Eroare: $e');
    }
  }

  /// Update client device info (pentru Modul HOPA wizard)
  static Future<Map<String, dynamic>> updateClientDevice(
    int clientId,
    Map<String, dynamic> deviceData,
  ) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/installer/clients/$clientId'),
        headers: await getAuthHeaders(),
        body: jsonEncode(deviceData),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Eroare la actualizarea dispozitivului');
      }
    } catch (e) {
      throw Exception('Eroare: $e');
    }
  }

  /// Add employee (sub-installer)
  static Future<Map<String, dynamic>> addEmployee(
    Map<String, dynamic> employeeData,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/installer/sub-installers'),
        headers: await getAuthHeaders(),
        body: jsonEncode(employeeData),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Eroare la adăugarea angajatului');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  /// Suspend employee
  static Future<Map<String, dynamic>> suspendEmployee(int employeeId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/installer/sub-installers/$employeeId/suspend'),
        headers: await getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Eroare la suspendarea angajatului');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  /// Activate employee
  static Future<Map<String, dynamic>> activateEmployee(int employeeId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/installer/sub-installers/$employeeId/activate'),
        headers: await getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Eroare la activarea angajatului');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  /// Get SOS alerts for installer
  static Future<List<dynamic>> getInstallerSOS({String? status}) async {
    try {
      var url = '$baseUrl/installer/sos';
      if (status != null) {
        url += '?status=$status';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: await getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['data'] ?? [];
      } else {
        throw Exception('Eroare la obținerea SOS-urilor');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  /// Acknowledge SOS alert
  static Future<Map<String, dynamic>> acknowledgeInstallerSOS(int sosId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/installer/sos/$sosId/acknowledge'),
        headers: await getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Eroare la marcarea SOS-ului ca preluat');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  /// Schedule SOS alert
  static Future<Map<String, dynamic>> scheduleInstallerSOS(
    int sosId, {
    required String date,
    required String time,
    String? notes,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/installer/sos/$sosId/schedule'),
        headers: await getAuthHeaders(),
        body: jsonEncode({
          'appointment_date': date,
          'appointment_time': time,
          if (notes != null && notes.isNotEmpty) 'appointment_notes': notes,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Eroare la programarea vizitei');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  /// Resolve SOS alert
  static Future<Map<String, dynamic>> resolveInstallerSOS(
    int sosId, {
    String? notes,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/installer/sos/$sosId/resolve'),
        headers: await getAuthHeaders(),
        body: jsonEncode({if (notes != null) 'resolution_notes': notes}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Eroare la rezolvarea SOS-ului');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  /// Get installation requests for installer
  static Future<List<dynamic>> getInstallationRequests() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/installer/installation-requests'),
        headers: await getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['data'] ?? [];
      } else {
        throw Exception('Eroare la obținerea cererilor de instalare');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  /// Accept installation request
  static Future<Map<String, dynamic>> acceptInstallationRequest(
    int requestId,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/installer/installation-requests/$requestId/accept'),
        headers: await getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Eroare la acceptarea cererii');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  /// Get admin notifications for installer
  static Future<List<dynamic>> getAdminNotifications() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/installer/notifications'),
        headers: await getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['data'] ?? [];
      } else {
        throw Exception('Eroare la obținerea notificărilor');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  /// Mark admin notification as read
  static Future<Map<String, dynamic>> markAdminNotificationRead(
    int notificationId,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/installer/notifications/$notificationId/read'),
        headers: await getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Eroare la marcarea ca citită');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  // ==================== ESP32 Provisioning ====================
  static Future<Map<String, dynamic>> getProvisionToken(int clientId) async {
    try {
      // Provision endpoints sunt expuse pe /api/provision (în afara /v1).
      final provisionBaseUrl = baseUrl.replaceFirst(RegExp(r'/v1$'), '');
      final response = await http.get(
        Uri.parse('$provisionBaseUrl/provision/token/$clientId'),
        headers: await getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        throw Exception('Sesiune expirată');
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Eroare la obținerea token-ului');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  /// Obține detaliile unui client (pentru polling provisioning status)
  static Future<Map<String, dynamic>> getInstallerClientDetails(
    int clientId,
  ) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/installer/clients/$clientId'),
        headers: await getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        throw Exception('Sesiune expirată');
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Eroare la obținerea detaliilor');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  /// Test ON/OFF pentru instalator (ESP32 wizard) - apelează endpoint installer-specific
  static Future<Map<String, dynamic>> installerGateControl(
    int clientId,
    String action,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/installer/gate/control'),
            headers: await getAuthHeaders(),
            body: jsonEncode({'client_id': clientId, 'action': action}),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Eroare la controlul porții');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  // ==================== Marketing Offers ====================

  /// Obține ofertele marketing pentru utilizatorul autentificat
  static Future<List<dynamic>> getMarketingOffers() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/marketing/offers'),
        headers: await getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<dynamic>.from(data['data'] ?? []);
      } else if (response.statusCode == 401) {
        throw Exception('Sesiune expirată');
      } else {
        throw Exception('Eroare la obținerea ofertelor');
      }
    } catch (e) {
      print('❌ Error getting marketing offers: $e');
      return []; // Returnează listă goală în caz de eroare
    }
  }

  /// Marchează o ofertă ca citită
  static Future<void> markOfferAsRead(int campaignId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/marketing/offers/$campaignId/read'),
        headers: await getAuthHeaders(),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        print('⚠️ Failed to mark offer as read: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error marking offer as read: $e');
    }
  }

  /// Obține numărul de oferte necitite
  static Future<int> getUnreadOffersCount() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/marketing/offers/unread-count'),
        headers: await getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['unread_count'] ?? 0;
      }
      return 0;
    } catch (e) {
      print('❌ Error getting unread offers count: $e');
      return 0;
    }
  }

  /// Șterge o ofertă marketing (doar o ascunde pentru user)
  static Future<void> deleteMarketingOffer(int campaignId) async {
    try {
      // Marchează ca citită (ca să dispară din lista de oferte necitite)
      await markOfferAsRead(campaignId);
      print('✅ Marketing offer $campaignId marked as read (hidden)');
    } catch (e) {
      print('❌ Error deleting marketing offer: $e');
      throw Exception('Nu s-a putut șterge oferta');
    }
  }

  /// Șterge toate ofertele marketing (le marchează pe toate ca citite)
  static Future<void> deleteAllMarketingOffers() async {
    try {
      // Obține toate ofertele și le marchează ca citite
      final offers = await getMarketingOffers();
      for (var offer in offers) {
        await markOfferAsRead(offer['id']);
      }
      print('✅ All marketing offers marked as read');
    } catch (e) {
      print('❌ Error deleting all marketing offers: $e');
      throw Exception('Nu s-au putut șterge ofertele');
    }
  }

  // ==================== Romania Data - Județe și Orașe ====================

  /// Obține lista județelor din România
  static Future<List<Map<String, dynamic>>> getCounties() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/romania-data/counties'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['data'] ?? []);
      } else {
        throw Exception('Eroare la obținerea județelor');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  /// Obține lista localităților pentru un județ
  static Future<List<String>> getLocalities(String countyCode) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/romania-data/localities/$countyCode'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<String>.from(data['data'] ?? []);
      } else {
        throw Exception('Eroare la obținerea localităților');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  /// Obține toate județele cu localitățile lor (pentru cache local)
  static Future<Map<String, dynamic>> getAllRomaniaData() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/romania-data/all'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Eroare la obținerea datelor României');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  // ==================== Technician Activity ====================

  /// Obține activitatea unui tehnician (clienți, statistici)
  static Future<Map<String, dynamic>> getTechnicianActivity(
    int technicianId,
  ) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/installer/sub-installers/$technicianId/activity'),
        headers: await getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['data'];
      } else {
        throw Exception('Eroare la obținerea activității');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }
}
