import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import '../utils/device_utils.dart';

// Instanță globală pentru stocare securizată
const _storage = FlutterSecureStorage();

class ApiService {
  // Alege automat URL-ul în funcție de mediu: debug ⇒ local, release ⇒ producție
  static String get baseUrl {
    // Pentru testare LOCALĂ
    const local = 'http://192.168.1.132:8000/api/v1';
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
    
    return {
      ...headers,
      if (token != null) 'Authorization': 'Bearer $token',
    };
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
      } else {
        final error = jsonDecode(response.body);
        print('❌ Client Login FAILED: $error');
        return {'success': false, 'message': error['message'] ?? 'Eroare la autentificare'};
      }
    } catch (e) {
      print('🔥 Exception: $e');
      return {'success': false, 'message': 'Eroare de conexiune: $e'};
    }
  }

  // Login cu cod de activare (pentru INSTALATORI)
  static Future<Map<String, dynamic>> loginInstallerWithCode(String code) async {
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
      } else {
        final error = jsonDecode(response.body);
        print('❌ Installer Login FAILED: $error');
        return {'success': false, 'message': error['message'] ?? 'Eroare la autentificare'};
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
        throw Exception('Sesiune expirată. Te rugăm să te autentifici din nou.');
      } else {
        throw Exception('Eroare la obținerea configurației');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  // Control gate - ULTRA FAST
  static Future<Map<String, dynamic>> controlGate(String? gateId, String action) async {
    const int maxRetries = 2;  // redus
    const Duration retryDelay = Duration(milliseconds: 500);  // mult mai rapid
    
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final response = await http.post(
          Uri.parse('$baseUrl/gate/control'),
          headers: await getAuthHeaders(),
          body: jsonEncode({
            if (gateId != null) 'gate_id': gateId,
            'action': action, // 'open', 'close', sau 'toggle'
          }),
        ).timeout(
          const Duration(seconds: 3),  // timeout mai mic
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
          print('⚠️ Server error ${response.statusCode} (încercare $attempt/$maxRetries)');
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
        throw Exception('Conexiunea a expirat. Verifică conexiunea la internet.');
      } catch (e) {
        print('🔴 Gate control error (încercare $attempt/$maxRetries): $e');
        if (attempt < maxRetries && e.toString().contains('SocketException')) {
          await Future.delayed(retryDelay);
          continue;
        }
        throw Exception('Eroare de conexiune: ${e.toString().replaceAll('Exception: ', '')}');
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
        throw Exception('Sesiune expirată. Te rugăm să te autentifici din nou.');
      } else {
        // Încearcă să extragi mesajul de eroare din răspuns
        try {
          final error = jsonDecode(response.body);
          throw Exception(error['message'] ?? 'Eroare la obținerea dispozitivelor');
        } catch (_) {
          throw Exception('Eroare la obținerea dispozitivelor');
        }
      }
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
  static Future<Map<String, dynamic>> updateNotificationSettings(Map<String, bool> settings) async {
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
        throw Exception('Sesiune expirată. Te rugăm să te autentifici din nou.');
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
  static Future<Map<String, dynamic>> upgradeSubscription(int planId, int extraCount) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/subscription/upgrade'),
        headers: await getAuthHeaders(),
        body: jsonEncode({
          'plan_id': planId,
          'hopa_extra_count': extraCount,
        }),
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
          'gate_status': 'open'
        };
      }
      
      return {
        'success': false,
        'message': 'Eroare la deschiderea porții'
      };
    } catch (e) {
      print('Error opening gate: $e');
      return {
        'success': false,
        'message': 'Eroare de conexiune'
      };
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
          'gate_status': 'closed'
        };
      }
      
      return {
        'success': false,
        'message': 'Eroare la închiderea porții'
      };
    } catch (e) {
      print('Error closing gate: $e');
      return {
        'success': false,
        'message': 'Eroare de conexiune'
      };
    }
  }
  
  // Verifică statusul curent al porții
  static Future<Map<String, dynamic>> getGateStatus() async {
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
          'state': data['status'] ?? data['state'] ?? data['gate_status'] ?? 'unknown',
          'sensor_active': data['sensor_active'] ?? false,
          // Dacă backend nu trimite explicit, considerăm provisionat dacă există oricare din câmpurile de stare
          'provisioned': data['provisioned'] ?? (data['state'] != null || data['gate_status'] != null),
          'last_action': data['last_action'],
          'timestamp': data['timestamp']
        };
      }
      
      // Fallback: nu blocăm aplicația
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
  static Future<Map<String, dynamic>> createGuestPass(Map<String, dynamic> data) async {
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

  static Future<Map<String, dynamic>> updateGuestPass(int id, Map<String, dynamic> data) async {
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
        throw Exception(error['message'] ?? 'Eroare la actualizarea invitației');
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
        throw Exception(error['message'] ?? 'Eroare la dezactivarea invitației');
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
      final url = '$baseUrl/sos/notifications'; // Changed endpoint to match Laravel
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
        throw Exception('Sesiune expirată. Te rugăm să te autentifici din nou.');
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Eroare la obținerea cererilor SOS');
      }
    } catch (e) {
      print('🔥 Exception in getSosRequestsForClient: $e');
      throw Exception('Eroare de conexiune: $e');
    }
  }

  // Confirmă programarea SOS
  static Future<Map<String, dynamic>> confirmSosAppointment(String sosId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/sos/notifications/$sosId/confirm'),
        headers: await getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        throw Exception('Sesiune expirată. Te rugăm să te autentifici din nou.');
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Eroare la confirmarea programării');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  // Răspunde unui instalator pentru o notificare SOS
  static Future<Map<String, dynamic>> replyToInstaller(String sosNotificationId, String messageContent) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/sos/notifications/$sosNotificationId/reply'),
        headers: await getAuthHeaders(),
        body: jsonEncode({'message_content': messageContent}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        throw Exception('Sesiune expirată. Te rugăm să te autentifici din nou.');
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Eroare la trimiterea răspunsului către instalator');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  static Future<List<dynamic>> getPushNotificationHistory({int limit = 50}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/push/history?limit=$limit'),
        headers: await getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['notifications'] ?? [];
      } else if (response.statusCode == 401) {
        throw Exception('Sesiune expirată. Te rugăm să te autentifici din nou.');
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Eroare la obținerea notificărilor');
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
    String newTime
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/sos/notifications/$sosId/reschedule'),
        headers: await getAuthHeaders(),
        body: jsonEncode({
          'appointment_date': '${newDate.year}-${newDate.month.toString().padLeft(2, '0')}-${newDate.day.toString().padLeft(2, '0')}',
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
  static Future<Map<String, dynamic>> cancelSosAppointment(String sosId, bool reschedule) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/sos/notifications/$sosId/cancel'),
        headers: await getAuthHeaders(),
        body: jsonEncode({
          'action': reschedule ? 'reschedule' : 'cancel',
        }),
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
  static Future<Map<String, dynamic>> deletePushNotification(String notificationId) async {
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
  static Future<Map<String, dynamic>> deleteAllPushNotifications({String? type}) async {
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
        throw Exception(error['message'] ?? 'Eroare la ștergerea notificărilor');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  // Șterge un mesaj SOS specific
  static Future<Map<String, dynamic>> deleteSosMessage(String notificationId) async {
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
  static Future<Map<String, dynamic>> requestActivationCode(String email) async {
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
      return {
        'success': false,
        'message': 'Eroare de conexiune: $e'
      };
    }
  }

  //=== SHELLY: Switch ON/OFF via backend EMQX HTTP API ===
  static Future<Map<String, dynamic>> shellySwitch({required bool on, String? deviceId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // FOLOSIM CODUL HOPA (71BDA...) în loc de shelly_device_id
      String? hopaCode = deviceId ?? prefs.getString('hopa_device_code');
      
      // DEBUG
      print('🔍 DEBUG HOPA Device Code: $hopaCode');
      
      // Dacă nu e în cache, îl cerem de la backend
      if (hopaCode == null || hopaCode.isEmpty) {
        try {
          final response = await http.get(
            Uri.parse('$baseUrl/client/data'),
            headers: await getAuthHeaders(),
          ).timeout(const Duration(seconds: 5));
          
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
      final response = await http.post(
        Uri.parse('$baseUrl/shelly/switch'),
        headers: await getAuthHeadersWithDevice(), // Cu modelul telefonului
        body: jsonEncode({
          'id': hopaCode, // Folosim codul HOPA direct
          'on': on,
        }),
      ).timeout(
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
  static Future<Map<String, dynamic>> regenerateActivationCode(String email) async {
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
  static Future<Map<String, dynamic>> addInstallerClient(Map<String, dynamic> data) async {
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
        throw Exception(error['message'] ?? 'Eroare la crearea clientului');
      }
    } catch (e) {
      print('🔥 Exception in addInstallerClient: $e');
      throw Exception('Eroare de conexiune: $e');
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
        return jsonDecode(response.body.isNotEmpty ? response.body : '{"success": true}');
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Eroare la ștergerea clientului');
      }
    } catch (e) {
      throw Exception('Eroare de conexiune: $e');
    }
  }

  /// Update client with Shelly device_id after wizard completes
  static Future<Map<String, dynamic>> updateClientShellyDevice(int clientId, String shellyDeviceId) async {
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

  /// Add employee (sub-installer)
  static Future<Map<String, dynamic>> addEmployee(Map<String, dynamic> employeeData) async {
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
  static Future<Map<String, dynamic>> resolveInstallerSOS(int sosId, {String? notes}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/installer/sos/$sosId/resolve'),
        headers: await getAuthHeaders(),
        body: jsonEncode({
          if (notes != null) 'resolution_notes': notes,
        }),
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
  static Future<Map<String, dynamic>> acceptInstallationRequest(int requestId) async {
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
  static Future<Map<String, dynamic>> markAdminNotificationRead(int notificationId) async {
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
      final response = await http.get(
        Uri.parse('$baseUrl/provision/token/$clientId'),
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
  static Future<Map<String, dynamic>> getTechnicianActivity(int technicianId) async {
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