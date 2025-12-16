import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  // Test conexiune la API
  print('🔍 Test conexiune API...\n');
  
  // 1. Test health check
  try {
    final healthResponse = await http.get(
      Uri.parse('http://192.168.1.132:8000/api/v1/health'),
    );
    print('✅ Health Check: ${healthResponse.statusCode}');
    if (healthResponse.statusCode == 200) {
      final data = jsonDecode(healthResponse.body);
      print('   Status: ${data['status']}');
      print('   Timestamp: ${data['timestamp']}');
      print('   API: ${data['api']}');
    }
  } catch (e) {
    print('❌ Health Check Error: $e');
  }
  
  print('\n' + '-' * 50 + '\n');
  
  // 2. Test login cu cod
  try {
    print('🔑 Test login cu codul TEST12...');
    final loginResponse = await http.post(
      Uri.parse('http://192.168.1.132:8000/api/v1/login-code'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({'code': 'TEST12'}),
    );
    
    print('   Status: ${loginResponse.statusCode}');
    if (loginResponse.statusCode == 200) {
      final data = jsonDecode(loginResponse.body);
      print('✅ Login reușit!');
      print('   Token: ${data['token']?.substring(0, 20)}...');
      print('   User: ${data['user']['name']}');
      
      // 3. Test gate control cu token
      if (data['token'] != null) {
        print('\n🚪 Test control poartă...');
        final controlResponse = await http.post(
          Uri.parse('http://192.168.1.132:8000/api/v1/gate/control'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Authorization': 'Bearer ${data['token']}',
          },
          body: jsonEncode({
            'action': 'open',
          }),
        );
        
        print('   Status: ${controlResponse.statusCode}');
        if (controlResponse.statusCode == 200) {
          final controlData = jsonDecode(controlResponse.body);
          print('✅ Control reușit!');
          print('   Success: ${controlData['success']}');
          print('   Message: ${controlData['message']}');
          print('   Method: ${controlData['method']}');
        } else {
          print('❌ Control eșuat: ${controlResponse.body}');
        }
      }
    } else {
      print('❌ Login eșuat: ${loginResponse.body}');
    }
  } catch (e) {
    print('❌ Login Error: $e');
  }
  
  print('\n✅ Test complet!');
} 