import 'dart:convert';
import 'package:http/http.dart' as http;

/// Service minimal pentru control direct ESP32
/// End-point-uri implementate în firmware:
///   POST /gate/open  – deschide poarta
///   POST /gate/close – închide poarta
///   GET  /status     – status rapid (opțional)
class GateControlService {
  static const String _esp32IP = '192.168.1.138';
  static const String _baseUrl = 'http://$_esp32IP';

  static const Duration _timeout = Duration(seconds: 5);

  static Future<_Result> _post(String path) async {
    try {
      final resp = await http
          .post(Uri.parse('$_baseUrl$path'))
          .timeout(_timeout);
      if (resp.statusCode == 200) {
        return _Result.success(jsonDecode(resp.body));
      }
      return _Result.error('HTTP ${resp.statusCode}');
    } catch (e) {
      return _Result.error('Conexiune eșuată: $e');
    }
  }

  static Future<_Result> openGate() => _post('/gate/open');
  static Future<_Result> closeGate() => _post('/gate/close');

  /// Generic control: action = 'open' / 'close' / 'toggle'
  static Future<_Result> controlGate(String action) async {
    if (action == 'open') return openGate();
    if (action == 'close') return closeGate();
    // toggle – trimitem la /control
    try {
      final resp = await http
          .post(Uri.parse('$_baseUrl/control'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'action': action}))
          .timeout(_timeout);
      if (resp.statusCode == 200) {
        return _Result.success(jsonDecode(resp.body));
      }
      return _Result.error('HTTP ${resp.statusCode}');
    } catch (e) {
      return _Result.error('Conexiune eșuată: $e');
    }
  }
}

class _Result {
  final bool success;
  final String? message;
  final Map<String, dynamic>? data;
  _Result.success(this.data)
      : success = true,
        message = null;
  _Result.error(this.message)
      : success = false,
        data = null;
} 