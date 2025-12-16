import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class ShellyDirectService {
  // Flag pentru a alterna între control direct și cloud
  static bool _useCloudControl = false; // DEZACTIVAT - folosim doar MQTT/local
  
  /// Control principal - PRIORITATE CLOUD prin backend
  static Future<Map<String, dynamic>> controlRelay({
    int relay = 0,
    String action = 'on',
    int? timer = 1,
  }) async {
    print('🌐 HOPA Gate - Control prin cloud MQTT');
    
    // PRIORITATE #1: Control prin backend + cloud MQTT
    if (_useCloudControl) {
      try {
        final cloudResult = await _controlViaBackend(action);
        if (cloudResult['success']) {
          print('✅ Control cloud MQTT reușit!');
          return cloudResult;
        } else {
          print('⚠️ Control cloud eșuat, încerc local...');
        }
      } catch (e) {
        print('🔴 Eroare control cloud: $e');
      }
    }
    
    // FALLBACK: Control local direct (doar dacă cloud-ul nu merge)
    return await _controlLocalDirect(relay, action, timer);
  }
  
  /// Control prin backend cu cloud MQTT
  static Future<Map<String, dynamic>> _controlViaBackend(String action) async {
    try {
      // Obține token-ul de autentificare
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      
      if (token == null) {
        throw Exception('Nu sunteți autentificat. Faceți login din nou.');
      }
      
      print('🚀 Trimit comandă prin backend la cloud MQTT...');
      
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/gate/control'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'action': action, // 'on', 'toggle', etc.
        }),
      ).timeout(Duration(seconds: 15));
      
      final data = jsonDecode(response.body);
      
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'host': 'cloud_mqtt',
          'method': data['method'] ?? 'cloud_mqtt',
          'message': data['message'] ?? 'Comandă executată prin cloud',
          'data': data,
        };
      } else {
        throw Exception(data['message'] ?? 'Eroare la controlul prin cloud');
      }
      
    } catch (e) {
      print('🔴 Eroare backend: $e');
      return {
        'success': false,
        'error': 'Control cloud eșuat: $e',
        'method': 'cloud_mqtt_failed'
      };
    }
  }
  
  /// Control local direct (fallback)
  static Future<Map<String, dynamic>> _controlLocalDirect(
    int relay,
    String action,
    int? timer,
  ) async {
    print('🏠 Fallback: încerc control local direct...');
    
    // Lista de posibile locații ale Shelly-ului (păstrată pentru fallback)
    final List<String> _possibleHosts = [
      '192.168.1.130',
      '192.168.1.131',
      '192.168.1.132',
      '192.168.1.142',
      'shelly1minig3-cc8da245ab7c.local',
      'shellyplus1-cc8da245ab7c.local',
    ];
    
    String lastError = '';
    for (final host in _possibleHosts) {
      try {
        print('🔍 Încerc Shelly local la: $host');
        final result = await _sendLocalCommand(host, relay, action, timer);
        
        if (result['success']) {
          print('✅ Găsit Shelly local la: $host');
          return result;
        }
      } catch (e) {
        lastError = e.toString();
        continue;
      }
    }
    
    return {
      'success': false,
      'error': 'Nu pot găsi Shelly local. Ultimă eroare: $lastError',
      'method': 'local_failed'
    };
  }
  
  /// Trimite comandă HTTP locală
  static Future<Map<String, dynamic>> _sendLocalCommand(
    String host,
    int relay,
    String action,
    int? timer,
  ) async {
    final params = {
      'turn': action,
      if (timer != null) 'timer': timer.toString(),
    };
    
    final uri = Uri.http(host, '/relay/$relay', params);
    
    final response = await http.get(uri).timeout(
      Duration(seconds: 2),
      onTimeout: () => throw Exception('Timeout la $host'),
    );
    
    if (response.statusCode == 200) {
      try {
        final data = json.decode(response.body);
        return {
          'success': true,
          'host': host,
          'method': 'local',
          'data': data,
          'ison': data['ison'] ?? false,
          'has_timer': data['has_timer'] ?? false,
        };
      } catch (e) {
        return {
          'success': true,
          'host': host,
          'method': 'local',
          'data': response.body,
        };
      }
    }
    
    throw Exception('HTTP ${response.statusCode} de la $host');
  }

  /// Comută între control cloud și local (pentru debug/settings)
  static void setCloudControl(bool enabled) {
    _useCloudControl = enabled;
    print(_useCloudControl 
      ? '🌐 Activat: Control prin cloud MQTT' 
      : '🏠 Activat: Control local direct');
  }
  
  static bool get isCloudControlEnabled => _useCloudControl;
} 