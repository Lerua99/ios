import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/shelly_device.dart';
import '../services/auth_service.dart';
import '../utils/device_utils.dart';

class ShellyService {
  final String baseUrl;
  final AuthService authService;

  ShellyService({
    required this.baseUrl,
    required this.authService,
  });

  // Obține lista de dispozitive
  Future<List<ShellyDevice>> getDevices() async {
    try {
      final token = authService.token;
      if (token == null) throw Exception('Nu sunteți autentificat');

      final response = await http.get(
        Uri.parse('$baseUrl/shelly/devices'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      final decoded = json.decode(response.body);

      if (response.statusCode == 200 && decoded['success'] == true) {
        final List<dynamic> devicesJson = decoded['devices'];
        return devicesJson.map((json) => ShellyDevice.fromJson(json)).toList();
      }

      // Dacă serverul a trimis mesaj, îl propagăm pentru debug
      final serverMsg = decoded is Map && decoded.containsKey('message')
          ? decoded['message']
          : 'Eroare la obținerea dispozitivelor';
      throw Exception(serverMsg);
    } catch (e) {
      print('Eroare getDevices: $e');
      throw e;
    }
  }

  // Controlează un dispozitiv
  Future<Map<String, dynamic>> controlDevice(int deviceId, String action) async {
    try {
      final token = authService.token;
      if (token == null) throw Exception('Nu sunteți autentificat');

      // Obține modelul telefonului
      final deviceModel = await DeviceUtils.getDeviceModel();

      final response = await http.post(
        Uri.parse('$baseUrl/shelly/devices/$deviceId/control'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-Device-Model': deviceModel, // Trimite modelul telefonului
        },
        body: json.encode({
          'action': action, // 'open', 'close', 'toggle'
        }),
      );

      final data = json.decode(response.body);
      
      if (response.statusCode == 200 && data['success'] == true) {
        return data;
      } else if (response.statusCode == 403) {
        throw Exception(data['message'] ?? 'Nu aveți permisiunea');
      } else {
        throw Exception(data['message'] ?? 'Eroare la controlul dispozitivului');
      }
    } catch (e) {
      print('Eroare controlDevice: $e');
      throw e;
    }
  }

  // Obține status-ul unui dispozitiv
  Future<Map<String, dynamic>> getDeviceStatus(int deviceId) async {
    try {
      final token = authService.token;
      if (token == null) throw Exception('Nu sunteți autentificat');

      final response = await http.get(
        Uri.parse('$baseUrl/shelly/devices/$deviceId/status'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return data;
        }
      }
      
      throw Exception('Eroare la obținerea statusului');
    } catch (e) {
      print('Eroare getDeviceStatus: $e');
      throw e;
    }
  }

  // Obține istoricul unui dispozitiv
  Future<List<Map<String, dynamic>>> getDeviceHistory(int deviceId) async {
    try {
      final token = authService.token;
      if (token == null) throw Exception('Nu sunteți autentificat');

      final response = await http.get(
        Uri.parse('$baseUrl/shelly/devices/$deviceId/history'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['logs']);
        }
      }
      
      throw Exception('Eroare la obținerea istoricului');
    } catch (e) {
      print('Eroare getDeviceHistory: $e');
      throw e;
    }
  }
} 