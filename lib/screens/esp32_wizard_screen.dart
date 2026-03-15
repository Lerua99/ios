import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:app_settings/app_settings.dart';
import '../services/api_service.dart';

/// Wizard de configurare Modul HOPA (ESP32)
/// Flow identic cu Shelly:
///   Pas 0: Selectare rețea WiFi client
///   Pas 1: Conectare la AP-ul HOPA-M (192.168.4.1)
///   Pas 2: Trimitere WiFi + Token la ESP32
///   Pas 3: Test ON/OFF
///   Pas 4: Finalizare
class Esp32WizardScreen extends StatefulWidget {
  final int clientId;
  final String? hopaDeviceCode;

  const Esp32WizardScreen({
    Key? key,
    required this.clientId,
    this.hopaDeviceCode,
  }) : super(key: key);

  @override
  State<Esp32WizardScreen> createState() => _Esp32WizardScreenState();
}

class _Esp32WizardScreenState extends State<Esp32WizardScreen>
    with SingleTickerProviderStateMixin {
  int _currentStep = 0;
  bool _isProcessing = false;
  String? _errorMessage;
  bool _hasTestedDevice = false;
  bool _nextTestShouldOpen = true;
  bool _showPassword = true; // Implicit vizibilă pentru instalator

  // AnimationController pentru roți dințate
  late AnimationController _gearAnimationController;

  // Date colectate
  String? _selectedSSID;
  String _wifiPassword = '';
  String? _deviceMac;
  String? _hopaDeviceCode;
  String? _provisionToken;
  bool _provisioningComplete = false;
  List<String> _availableNetworks = [];
  
  // IP-ul ESP32 AP (fix: 192.168.4.1)
  static const String _espAPIP = '192.168.4.1';
  static const String _espAPSSID = 'HOPA-M';

  // Cache WiFi scan
  DateTime? _lastWiFiScan;
  static const _wifiCacheDuration = Duration(minutes: 2);

  @override
  void initState() {
    super.initState();
    _hopaDeviceCode = widget.hopaDeviceCode;
    _gearAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _scanWiFiNetworks();
    _loadProvisionToken();
  }

  @override
  void dispose() {
    _gearAnimationController.dispose();
    super.dispose();
  }

  Future<void> _loadProvisionToken() async {
    try {
      final resp = await ApiService.getProvisionToken(widget.clientId);
      if (resp['success'] == true && resp['token'] != null) {
        setState(() {
          _provisionToken = resp['token'];
        });
        debugPrint('✅ Provision token încărcat: $_provisionToken');
      } else {
        debugPrint('⚠️ Token invalid: $resp');
      }
    } catch (e) {
      debugPrint('⚠️ Nu am putut încărca token-ul: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  SCAN WIFI
  // ═══════════════════════════════════════════════════════════════
  Future<void> _scanWiFiNetworks() async {
    if (_lastWiFiScan != null &&
        DateTime.now().difference(_lastWiFiScan!) < _wifiCacheDuration &&
        _availableNetworks.isNotEmpty) {
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final status = await Permission.location.request();
      if (!status.isGranted) {
        setState(() => _errorMessage = 'Permisiune locație necesară pentru scanare WiFi');
        return;
      }

      final scanner = WiFiScan.instance;
      final canScan = await scanner.canStartScan();
      if (canScan == CanStartScan.yes) {
        await scanner.startScan();
        await Future.delayed(const Duration(seconds: 3));
        final results = await scanner.getScannedResults();

        setState(() {
          _availableNetworks = results
              .map((r) => r.ssid)
              .where((ssid) => ssid.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
          _lastWiFiScan = DateTime.now();
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'Eroare la scanare WiFi: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  PAS 2: TRIMITERE CONFIGURARE LA ESP32
  // ═══════════════════════════════════════════════════════════════
  Future<void> _sendConfigToESP32() async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      // Token-ul este obligatoriu pentru callback-ul de provisioning al ESP32.
      if ((_provisionToken ?? '').isEmpty) {
        await _loadProvisionToken();
      }
      if ((_provisionToken ?? '').isEmpty) {
        throw Exception(
          'Nu am putut obține token-ul de provisioning.\n'
          'Verifică internetul și drepturile instalatorului pentru client.',
        );
      }

      final url = 'http://$_espAPIP/provision';

      final body = jsonEncode({
        'ssid': _selectedSSID,
        'password': _wifiPassword,
        'token': _provisionToken ?? '',
        'server': 'https://hopa.tritech.ro',
      });

      debugPrint('📡 Trimit configurare la HOPA-M: $url');

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          debugPrint('✅ Configurare trimisă cu succes!');

          // Obține info ESP32 (încă pe AP)
          await _getDeviceInfo();

          // Trece direct la pasul de Test
          // Telefonul e ÎNCĂ pe HOPA-M → testul HTTP local funcționează
          setState(() {
            _currentStep = 3;
            _errorMessage = null;
          });
      } else {
        throw Exception(data['message'] ?? 'Eroare necunoscută');
      }
    } else {
      throw Exception('HTTP ${response.statusCode}');
    }
  } catch (e) {
    setState(() => _errorMessage = 'Eroare la configurare: $e\n\nVerifică:\n• Ești conectat la rețeaua HOPA-M?\n• ESP32 este pornit?');
  } finally {
    setState(() => _isProcessing = false);
  }
  }

  // ═══════════════════════════════════════════════════════════════
  //  POLLING PROVISIONING STATUS
  // ═══════════════════════════════════════════════════════════════
  bool _isProvisionedClient(Map<String, dynamic> client) {
    final hasProvisionTimestamp = client['provisioning_completed_at'] != null;
    final hasSerial = (client['device_serial_number'] ?? '').toString().isNotEmpty;
    final apiProvisioned = client['provisioned'] == true;
    return hasProvisionTimestamp || hasSerial || apiProvisioned;
  }

  Future<void> _refreshProvisioningStatusOnce() async {
    try {
      final resp = await ApiService.getInstallerClientDetails(widget.clientId);
      if (resp['success'] == true && resp['data'] != null) {
        final client = (resp['data'] as Map).cast<String, dynamic>();
        if (_isProvisionedClient(client)) {
          if (!mounted) return;
          setState(() => _provisioningComplete = true);
        }
      }
    } catch (_) {}
  }

  Future<void> _waitForProvisioning() async {
    debugPrint('🔄 Aștept confirmarea provisioning pe backend...');

    // Așteaptă ca telefonul să se reconecteze la WiFi normal (ieșire din AP)
    await Future.delayed(const Duration(seconds: 5));

    for (int i = 0; i < 9; i++) {
      if (!mounted) return;
      try {
        final resp = await ApiService.getInstallerClientDetails(widget.clientId);
        if (resp['success'] == true && resp['data'] != null) {
          final client = (resp['data'] as Map).cast<String, dynamic>();
          if (_isProvisionedClient(client)) {
            debugPrint('✅ Provisioning confirmat pe backend!');
            if (!mounted) return;
            setState(() => _provisioningComplete = true);
            return;
          }
        }
      } catch (e) {
        debugPrint('⚠️ Polling provisioning: $e');
      }
      await Future.delayed(const Duration(seconds: 5));
    }

    debugPrint('⚠️ Timeout polling provisioning (45s)');
  }

  // ═══════════════════════════════════════════════════════════════
  //  GET DEVICE INFO (echivalent Shelly.GetDeviceInfo)
  // ═══════════════════════════════════════════════════════════════
  Future<void> _getDeviceInfo() async {
    try {
      final resp = await http.get(
        Uri.parse('http://$_espAPIP/info'),
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() {
          _deviceMac = data['mac'] ?? '';
        });
        debugPrint('📋 Device MAC: $_deviceMac');
      }
    } catch (e) {
      debugPrint('⚠️ Nu am putut obține info dispozitiv: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  TRECERE LA FINALIZARE (oprește AP + pasul 4)
  // ═══════════════════════════════════════════════════════════════
  Future<void> _goToFinalize() async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    // Oprește AP-ul HOPA-M (telefonul revine la WiFi normal)
    try {
      await http.post(
        Uri.parse('http://$_espAPIP/ap/disable'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 3));
    } catch (_) {}

    await Future.delayed(const Duration(seconds: 3));

    setState(() {
      _isProcessing = false;
      _currentStep = 4;
      _errorMessage = null;
    });

    // Refresh imediat (fără delay) pentru statusul din UI.
    unawaited(_refreshProvisioningStatusOnce());

    // Polling backend în fundal pentru a actualiza statusul "Provisioned".
    unawaited(_waitForProvisioning());
  }

  // ═══════════════════════════════════════════════════════════════
  //  PAS 3: TEST ON/OFF (ca la Shelly)
  // ═══════════════════════════════════════════════════════════════
  Future<void> _testRelay() async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final action = 'open';
      bool testSuccess = false;

      // 1. HTTP local PRIMUL (telefonul e pe HOPA-M la acest pas!)
      try {
        debugPrint('📡 Test prin HTTP local (192.168.4.1)...');
        final resp = await http.post(
          Uri.parse('http://$_espAPIP/control'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'action': action}),
        ).timeout(const Duration(seconds: 5));

        if (resp.statusCode == 200) {
          debugPrint('✅ Test relay OK (HTTP local)');
          testSuccess = true;
        }
      } catch (e) {
        debugPrint('⚠️ HTTP local error: $e');
      }

      // 2. Fallback: MQTT backend (dacă telefonul a revenit la WiFi normal)
      if (!testSuccess) {
        try {
          debugPrint('📡 Fallback: installer gate control (MQTT)...');
          final resp = await ApiService.installerGateControl(widget.clientId, action);
          if (resp['success'] == true) {
            debugPrint('✅ Test relay OK (installer MQTT)');
            testSuccess = true;
          }
        } catch (e) {
          debugPrint('⚠️ MQTT error: $e');
        }
      }

      if (!testSuccess) {
        throw Exception('Nu s-a putut testa releul.\nVerifică că modulul HOPA e pornit.');
      }

      // Test reușit!
      setState(() {
        _hasTestedDevice = true;
        _nextTestShouldOpen = !_nextTestShouldOpen;
        _errorMessage = null;
      });

      // AUTO-SWITCH: oprește AP-ul HOPA-M → telefonul revine pe WiFi-ul instalatorului
      // → trece automat la Step 4 (Finalizare) cu verificare provisioning
      debugPrint('🔄 Test OK → auto-switch la WiFi-ul instalatorului...');
      await _goToFinalize();

    } catch (e) {
      setState(() {
        _isProcessing = false;
        _errorMessage = 'Eroare la test: $e';
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  PAS 4: FINALIZARE
  // ═══════════════════════════════════════════════════════════════
  Future<void> _finalize() async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    // Încercăm să salvăm în backend, dar NU blocăm finalizarea
    if (widget.clientId > 0) {
      var saved = false;
      for (var attempt = 1; attempt <= 3; attempt++) {
        try {
          await ApiService.updateClientDevice(widget.clientId, {
            'device_type': 'hopa',
            'device_mac': _deviceMac ?? '',
            'device_name': 'Modul HOPA',
            if ((_hopaDeviceCode ?? '').isNotEmpty)
              'hopa_device_code': _hopaDeviceCode,
          });
          final details = await ApiService.getInstallerClientDetails(widget.clientId);
          final savedCode = (details['data']?['hopa_device_code'] ?? '').toString();
          if (savedCode.isNotEmpty && mounted) {
            setState(() => _hopaDeviceCode = savedCode);
          }
          saved = true;
          debugPrint('✅ Device info salvat în backend (attempt $attempt)');
          break;
        } catch (e) {
          debugPrint('⚠️ Salvare backend eșuată (attempt $attempt): $e');
          if (attempt < 3) {
            await Future.delayed(const Duration(seconds: 2));
          }
        }
      }
      if (!saved) {
        debugPrint('⚠️ Nu s-a putut salva în backend după retry (WiFi/AP reconectare lentă?)');
        // Nu blocăm — se poate sincroniza mai târziu.
      }
    }

    if (!mounted) return;

    setState(() => _isProcessing = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Modul HOPA configurat cu succes!'),
        backgroundColor: Color(0xFF27ae60),
        duration: Duration(seconds: 3),
      ),
    );

    Navigator.of(context).pop({'success': true, 'device_mac': _deviceMac});
  }

  // ═══════════════════════════════════════════════════════════════
  //  RESETARE & REINSTALARE (identic Shelly wizard)
  // ═══════════════════════════════════════════════════════════════
  Future<void> _deleteClientAndRestart() async {
    setState(() => _isProcessing = true);

    try {
      final response = await ApiService.deleteClient(widget.clientId);

      if (response['success'] == true) {
        if (!mounted) return;

        Navigator.pop(context);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Clientul a fost șters. Poți reîncepe instalarea.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      } else {
        throw Exception(response['message'] ?? 'Eroare la ștergere');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Eroare la ștergere: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  BUILD UI
  // ═══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f172a),
      appBar: AppBar(
        title: const Text('Configurare Modul HOPA'),
        backgroundColor: const Color(0xFF111827),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _buildStepIndicator(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              child: _buildCurrentStep(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    final steps = ['WiFi', 'AP HOPA', 'Configurare', 'Test', 'Final'];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      color: const Color(0xFF111827),
      child: Row(
        children: List.generate(steps.length, (i) {
          final isActive = i == _currentStep;
          final isDone = i < _currentStep;

          return Expanded(
            child: Row(
              children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDone
                        ? const Color(0xFF27ae60)
                        : isActive
                            ? const Color(0xFF2563eb)
                            : Colors.grey[700],
                  ),
                  child: Center(
                    child: isDone
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : Text('${i + 1}',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    steps[i],
                    style: TextStyle(
                      color: isActive ? Colors.white : Colors.grey[500],
                      fontSize: 10,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (i < steps.length - 1) const SizedBox(width: 4),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0: return _buildStep0_SelectWiFi();
      case 1: return _buildStep1_ConnectAP();
      case 2: return _buildStep2_SendConfig();
      case 3: return _buildStep3_Test();
      case 4: return _buildStep4_Finalize();
      default: return const SizedBox();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  PAS 0: SELECTARE REȚEA WIFI CLIENT
  // ═══════════════════════════════════════════════════════════════
  Widget _buildStep0_SelectWiFi() {
    return _buildCard(
      icon: Icons.wifi,
      title: 'Selectează rețeaua WiFi',
      subtitle: 'Alege rețeaua WiFi a clientului la care va fi conectat modulul HOPA',
      child: Column(
        children: [
          if (_isProcessing)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Scanez rețele WiFi...', style: TextStyle(color: Colors.white70)),
                ],
              ),
            )
          else ...[
            if (_availableNetworks.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    const Icon(Icons.wifi_off, size: 40, color: Colors.grey),
                    const SizedBox(height: 8),
                    const Text('Nicio rețea detectată', style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _scanWiFiNetworks,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Rescanează'),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563eb)),
                    ),
                  ],
                ),
              )
            else
              ..._availableNetworks.map((ssid) => ListTile(
                leading: Icon(
                  Icons.wifi,
                  color: _selectedSSID == ssid ? const Color(0xFF27ae60) : Colors.grey,
                ),
                title: Text(ssid, style: const TextStyle(color: Colors.white)),
                trailing: _selectedSSID == ssid
                    ? const Icon(Icons.check_circle, color: Color(0xFF27ae60))
                    : null,
                selected: _selectedSSID == ssid,
                onTap: () => setState(() => _selectedSSID = ssid),
              )),
            const SizedBox(height: 12),
            if (_selectedSSID != null) ...[
              TextFormField(
                decoration: InputDecoration(
                  labelText: 'Parolă WiFi',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: const Color(0xFF111827),
                  labelStyle: const TextStyle(color: Colors.white70),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showPassword ? Icons.visibility : Icons.visibility_off,
                      color: Colors.white54,
                    ),
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
                obscureText: !_showPassword,
                onChanged: (v) => setState(() => _wifiPassword = v),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _wifiPassword.isNotEmpty
                      ? () => setState(() => _currentStep = 1)
                      : null,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Continuă'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563eb),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ],
          if (_errorMessage != null)
            _buildErrorBox(_errorMessage!),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  PAS 1: CONECTARE LA AP-UL HOPA-M
  // ═══════════════════════════════════════════════════════════════
  Widget _buildStep1_ConnectAP() {
    return _buildCard(
      icon: Icons.router,
      title: 'Conectează-te la HOPA-M',
      subtitle: 'Deschide setările WiFi și conectează-te la rețeaua "$_espAPSSID"',
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1e3a5f),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2563eb), width: 1),
            ),
            child: Column(
              children: [
                RotationTransition(
                  turns: _gearAnimationController,
                  child: const Icon(Icons.settings, size: 60, color: Color(0xFF2563eb)),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Pași:',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _buildInstructionRow('1', 'Deschide Setări WiFi pe telefon'),
                _buildInstructionRow('2', 'Caută rețeaua "$_espAPSSID"'),
                _buildInstructionRow('3', 'Conectează-te (fără parolă)'),
                _buildInstructionRow('4', 'Revino în aplicație'),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0f172a),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Color(0xFFfbbf24), size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'IP-ul modulului: 192.168.4.1\nRețeaua este deschisă (fără parolă)',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isProcessing ? null : _verifyAPConnection,
              icon: _isProcessing
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check),
              label: Text(_isProcessing ? 'Verific conexiunea...' : 'Am conectat, verifică!'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF27ae60),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (_errorMessage != null)
            _buildErrorBox(_errorMessage!),
        ],
      ),
    );
  }

  Future<void> _verifyAPConnection() async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final resp = await http.get(
        Uri.parse('http://$_espAPIP/status'),
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() {
          _deviceMac = data['mac'];
          _currentStep = 2;
          _errorMessage = null;
        });
        debugPrint('✅ Conectat la HOPA-M! MAC: $_deviceMac');
      } else {
        throw Exception('Răspuns neașteptat: ${resp.statusCode}');
      }
    } catch (e) {
      setState(() => _errorMessage = 'Nu sunt conectat la HOPA-M!\n\nVerifică:\n• Ești conectat la rețeaua "$_espAPSSID"?\n• Modulul HOPA este pornit?');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  PAS 2: TRIMITERE CONFIGURARE
  // ═══════════════════════════════════════════════════════════════
  Widget _buildStep2_SendConfig() {
    return _buildCard(
      icon: Icons.send,
      title: 'Configurare Modul HOPA',
      subtitle: 'Trimite datele WiFi și token-ul la modul',
      child: Column(
        children: [
          _buildInfoRow('Rețea WiFi', _selectedSSID ?? '-'),
          _buildInfoRow('Parolă', '••••••••'),
          _buildInfoRow(
            'Token',
            (_provisionToken ?? '').isNotEmpty
                ? '${_provisionToken!.substring(0, 8)}...'
                : '⚠️ Lipsește',
          ),
          _buildInfoRow('MAC modul', _deviceMac ?? '-'),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isProcessing ? null : _sendConfigToESP32,
              icon: _isProcessing
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send),
              label: Text(_isProcessing ? 'Trimit configurarea...' : 'Trimite configurarea'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563eb),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (_errorMessage != null)
            _buildErrorBox(_errorMessage!),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  PAS 3: TEST ON/OFF (identic Shelly)
  // ═══════════════════════════════════════════════════════════════
  Widget _buildStep3_Test() {
    return _buildCard(
      icon: Icons.bolt,
      title: 'Test Funcționalitate',
      subtitle: 'Testează deschiderea/închiderea porții',
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1e3a5f),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(
                  _isProcessing ? Icons.sync : Icons.touch_app,
                  size: 60,
                  color: _isProcessing ? const Color(0xFFfbbf24) : const Color(0xFF2563eb),
                ),
                const SizedBox(height: 12),
                Text(
                  _isProcessing
                      ? 'Se testează... după test, telefonul revine automat pe WiFi-ul tău.'
                      : 'Apasă butonul pentru a testa\nDupă test reușit, se trece automat la finalizare.',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _testRelay,
                  icon: _isProcessing
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Icon(_nextTestShouldOpen ? Icons.lock_open : Icons.lock),
                  label: Text(_isProcessing
                      ? 'Se testează și se reconectează...'
                      : (_nextTestShouldOpen ? '⚡ DESCHIDE' : '⚡ ÎNCHIDE')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _nextTestShouldOpen
                        ? const Color(0xFF27ae60)
                        : const Color(0xFFe74c3c),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
          if (_errorMessage != null)
            _buildErrorBox(_errorMessage!),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  PAS 4: FINALIZARE
  // ═══════════════════════════════════════════════════════════════
  Widget _buildStep4_Finalize() {
    return _buildCard(
      icon: Icons.celebration,
      title: 'Finalizare Instalare',
      subtitle: 'Modulul HOPA este configurat!',
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF164e36), Color(0xFF0f3a2a)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Icon(Icons.check_circle, size: 60, color: Color(0xFF27ae60)),
                const SizedBox(height: 12),
                const Text(
                  'Instalare completă! 🎉',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _buildInfoRow('Rețea WiFi', _selectedSSID ?? '-'),
                _buildInfoRow('MAC', _deviceMac ?? '-'),
                _buildInfoRow('Cod HOPA', _hopaDeviceCode ?? '-'),
                _buildInfoRow('Test', _hasTestedDevice ? '✅ OK' : '⚠️ Neefectuat'),
                _buildInfoRow('Provisioned', _provisioningComplete ? '✅ DA' : '⚠️ NU'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isProcessing ? null : _finalize,
              icon: _isProcessing
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.done_all),
              label: Text(_isProcessing ? 'Finalizez...' : 'Finalizează instalarea'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF27ae60),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (_errorMessage != null)
            _buildErrorBox(_errorMessage!),
          const SizedBox(height: 16),
          // Buton Resetare & Reinstalare
          TextButton.icon(
            onPressed: _isProcessing ? null : () async {
              final confirm = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (context) => AlertDialog(
                  backgroundColor: const Color(0xFF1e293b),
                  title: const Text('⚠️ Resetare completă',
                      style: TextStyle(color: Colors.white)),
                  content: const Text(
                    'Ești sigur? Se va șterge clientul complet din baza de date '
                    '(inclusiv contul utilizatorului). Vei putea reîncepe instalarea de la zero.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Anulează', style: TextStyle(color: Colors.grey)),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      child: const Text('Șterge și reinstalează',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                await _deleteClientAndRestart();
              }
            },
            icon: const Icon(Icons.refresh, color: Colors.red),
            label: const Text(
              'Resetează & Reinstalează',
              style: TextStyle(color: Colors.red, fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  WIDGET HELPERS
  // ═══════════════════════════════════════════════════════════════
  Widget _buildCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Card(
      color: const Color(0xFF1e293b),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563eb).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: const Color(0xFF2563eb), size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      Text(subtitle, style: TextStyle(color: Colors.grey[400], fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('$label: ', style: TextStyle(color: Colors.grey[400], fontSize: 14)),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionRow(String number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 24, height: 24,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF2563eb),
            ),
            child: Center(
              child: Text(number, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBox(String message) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF7f1d1d),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFef4444)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFef4444), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
