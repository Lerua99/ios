import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';

class Esp32WizardScreen extends StatefulWidget {
  final int clientId;
  const Esp32WizardScreen({Key? key, required this.clientId}) : super(key: key);

  @override
  State<Esp32WizardScreen> createState() => _Esp32WizardScreenState();
}

class _Esp32WizardScreenState extends State<Esp32WizardScreen> {
  int _step = 0;
  bool _busy = false;
  String? _error;
  String? _ssid;
  String _wifiPass = '';
  String? _provisionToken;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurare ESP32'),
        backgroundColor: const Color(0xFF20c997),
        foregroundColor: Colors.white,
      ),
      body: _buildStep(),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0: return _stepWifi();
      case 1: return _stepProvision();
      case 2: return _stepDone();
      default: return const SizedBox();
    }
  }

  Widget _stepWifi() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              labelText: 'SSID Wi-Fi',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => _ssid = v,
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Parolă Wi-Fi',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
            onChanged: (v) => _wifiPass = v,
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _busy || (_ssid == null || _ssid!.isEmpty || _wifiPass.isEmpty) ? null : _nextProvision,
            icon: _busy ? const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white)) : const Icon(Icons.wifi),
            label: Text(_busy ? 'Se pregătește...' : 'Continuă'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF20c997), foregroundColor: Colors.white),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ]
        ],
      ),
    );
  }

  Future<void> _nextProvision() async {
    setState(() { _busy = true; _error = null; });
    try {
      final resp = await ApiService.getProvisionToken(widget.clientId);
      _provisionToken = resp['token'] ?? resp['provision_token'];
      if (_provisionToken == null) {
        throw Exception('Token lipsă');
      }
      setState(() { _step = 1; _busy = false; });
    } catch (e) {
      setState(() { _busy = false; _error = 'Eroare: $e'; });
    }
  }

  Widget _stepProvision() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Trimite datele către ESP32', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('SSID: ${_ssid ?? '-'}'),
          Text('Token: ${_provisionToken ?? '-'}'),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _busy ? null : _sendToEsp,
            icon: _busy ? const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white)) : const Icon(Icons.send),
            label: Text(_busy ? 'Se trimite...' : 'Trimite la dispozitiv'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF20c997), foregroundColor: Colors.white),
          ),
          const SizedBox(height: 12),
          if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
      ),
    );
  }

  Future<void> _sendToEsp() async {
    setState(() { _busy = true; _error = null; });
    try {
      // Device local AP endpoint (firmware nostru): http://192.168.4.1/provision
      final resp = await http.post(
        Uri.parse('http://192.168.4.1/provision'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ssid': _ssid,
          'password': _wifiPass,
          'token': _provisionToken,
          'server': 'https://hopa.tritech.ro',
        }),
      ).timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        setState(() { _step = 2; _busy = false; });
      } else {
        throw Exception('Răspuns ESP32: ${resp.statusCode}');
      }
    } catch (e) {
      setState(() { _busy = false; _error = 'Eroare la trimitere: $e'; });
    }
  }

  Widget _stepDone() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 96),
          const SizedBox(height: 12),
          const Text('Provisionare finalizată!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Gata'),
          )
        ],
      ),
    );
  }
}

















































