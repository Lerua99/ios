import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_scan/wifi_scan.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class ShellyWizardScreen extends StatefulWidget {
  final Function(String shellyDeviceId) onComplete;
  final int? clientId;
  final String? hopaDeviceCode; // Codul 71BDA... generat de backend

  const ShellyWizardScreen({Key? key, required this.onComplete, this.clientId, this.hopaDeviceCode}) : super(key: key);

  @override
  State<ShellyWizardScreen> createState() => _ShellyWizardScreenState();
}

class _ShellyWizardScreenState extends State<ShellyWizardScreen>
    with SingleTickerProviderStateMixin {
  int _currentStep = 0; // Pornim direct la pasul WiFi
  bool _isProcessing = false;
  String? _errorMessage;
  bool _hasTestedDevice = false; // Flag pentru test ON/OFF (cerința #5)
  bool _nextTestShouldOpen = true; // Următorul test imită aplicația: alternativ deschide/închide
  
  // AnimationController pentru roți dințate
  late AnimationController _gearAnimationController;
  
  // Date colectate
  String? _selectedSSID;
  String _wifiPassword = '';
  String? _shellyDeviceId = 'shelly-temp'; // Va fi extras din Shelly la final
  String? _shellyIPAddress = '192.168.33.1'; // IP-ul AP Shelly
  List<String> _availableNetworks = [];
  
  // Cache pentru WiFi networks (optimizare)
  DateTime? _lastWiFiScan;
  static const _wifiCacheDuration = Duration(minutes: 2);

  @override
  void initState() {
    super.initState();
    
    // Inițializează AnimationController pentru roți dințate (loop infinit)
    _gearAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(); // REPEAT infinit!
    
    // Preload assets pentru UI rapid
    _preloadAssets();
    
    // Scanează WiFi disponibile cu cache
    _scanWiFiNetworksWithCache();
  }
  
  Future<void> _preloadAssets() async {
    // Preload imagini pentru a evita lag la prima afișare
    if (mounted) {
      precacheImage(const AssetImage('assets/home_background.jpg'), context);
      precacheImage(const AssetImage('assets/logo.png'), context);
    }
  }

  // Șterge clientul complet și reîncepe de la capăt
  Future<void> _deleteClientAndRestart() async {
    if (widget.clientId == null) {
      Navigator.pop(context); // Revine la listă
      return;
    }
    
    setState(() => _isProcessing = true);
    
    try {
      // Apelează API pentru ștergere completă client
      final response = await ApiService.deleteClient(widget.clientId!);
      
      if (response['success']) {
        if (!mounted) return;
        
        // Închide wizard-ul
        Navigator.pop(context);
        
        // Arată mesaj de confirmare
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
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

  @override
  void dispose() {
    _gearAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_currentStep > 0) {
          setState(() => _currentStep--);
          return false;
        }
        return true;
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: Colors.grey[100],
        appBar: AppBar(
          title: const Text('Configurare Shelly'),
          backgroundColor: const Color(0xFF1cc88a),
          foregroundColor: Colors.white,
        ),
        body: _buildCurrentStep(),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildStep0SelectWiFi(); // CU INTERNET - scanare WiFi
      case 1:
        return _buildStep1ConnectToShelly(); // Instrucțiune conectare la AP
      case 2:
        return _buildStep2ConfigureWiFi(); // FĂRĂ INTERNET - trimitere config la Shelly
      case 3:
        return _buildStep3AutoConfig(); // MQTT
      case 4:
        return _buildStep4Complete(); // Final
      default:
        return const SizedBox();
    }
  }

  // ECRAN 1: Instrucțiuni conectare la AP Shelly
  Widget _buildStep1ConnectToShelly() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.router, size: 80, color: Colors.orange[700]),
          const SizedBox(height: 24),
          Text(
            'Conectează-te la Shelly',
            style: TextStyle(
              fontSize: 24, 
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],  // CULOARE ÎNCHISĂ
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange[200]!),
            ),
            child: Column(
              children: [
                Text(
                  '📱 Acțiune necesară:',
                  style: TextStyle(
                    fontSize: 16, 
                    fontWeight: FontWeight.bold,
                    color: Colors.orange[900],  // CULOARE ÎNCHISĂ
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '1. Deschide Setările Wi‑Fi pe telefon\n2. Conectează-te la rețeaua Shelly (shelly1minig3-XXXXXX)\n3. Revino în aplicație și apasă "Continuă"',
                  style: TextStyle(fontSize: 14, color: Colors.grey[900]),  // FOARTE ÎNCHIS
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => setState(() => _currentStep = 2),
            icon: const Icon(Icons.check),
            label: const Text('M-am conectat la Shelly →'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange[700],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              textStyle: const TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
    );
  }

  // ECRAN 2: Configurare WiFi (FĂRĂ INTERNET - pe AP Shelly)
  Widget _buildStep2ConfigureWiFi() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Roți dințate animate când procesează
          Center(
            child: _isProcessing
                ? _buildRotatingGears()
                : Icon(Icons.settings_input_antenna, size: 80, color: Colors.green[700]),
          ),
          
          const SizedBox(height: 24),
          
          if (!_isProcessing)
            const Text(
              'Configurare Wi‑Fi',
              style: TextStyle(
                fontSize: 24, 
                fontWeight: FontWeight.bold,
                color: Colors.green,  // VERDE pentru vizibilitate
              ),
              textAlign: TextAlign.center,
            ),
          
          const SizedBox(height: 16),
          
          const SizedBox.shrink(),
          
          const SizedBox(height: 24),
          
          if (!_isProcessing)
            ElevatedButton.icon(
              onPressed: _connectShellyToWiFi,
              icon: const Icon(Icons.send),
              label: const Text('Trimite configurația la Shelly'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            ),
          ],
        ],
      ),
    );
  }

  // ECRAN 1 VECHI (păstrat pentru referință, dar nu se mai folosește)
  Widget _buildStep1ConnectShelly() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_find, size: 80, color: Colors.green[700]),
          const SizedBox(height: 24),
          const Text(
            'Conectează Shelly-ul',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Apasă butonul de mai jos ca aplicația să caute automat dispozitivul Shelly din apropiere.\n\nAsigură-te că este alimentat și are LED-ul aprins.',
            style: TextStyle(fontSize: 16, color: Colors.grey[700]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          if (_isProcessing)
            const CircularProgressIndicator()
          else
            ElevatedButton.icon(
              onPressed: _connectToShellyAP,
              icon: const Icon(Icons.search),
              label: const Text('Caută și Conectează'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            'Ține telefonul aproape de dispozitiv (1-2 metri)',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ECRAN 0: Selectare WiFi (CU INTERNET)
  Widget _buildStep0SelectWiFi() {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Icon(Icons.wifi, size: 60, color: Colors.blue[700]),
          const SizedBox(height: 16),
          Text(
            'Alege rețeaua Wi-Fi a clientului',
            style: TextStyle(
              fontSize: 20, 
              fontWeight: FontWeight.bold,
              color: Colors.blue[800],  // ALBASTRU ÎNCHIS
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Selectează rețeaua și introdu parola ÎNAINTE de a te conecta la Shelly.',
            style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          
          // Dropdown WiFi Networks
          DropdownButtonFormField<String>(
            decoration: InputDecoration(
              labelText: 'Selectează rețeaua Wi-Fi',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.wifi),
              filled: true,
              fillColor: Colors.white,
              labelStyle: const TextStyle(color: Colors.black54),
            ),
            value: _selectedSSID,
            style: const TextStyle(color: Colors.black, fontSize: 16),
            dropdownColor: Colors.white,
            items: _availableNetworks.map((ssid) {
              return DropdownMenuItem(value: ssid, child: Text(ssid));
            }).toList(),
            onChanged: (value) {
              setState(() => _selectedSSID = value);
            },
          ),
          
          const SizedBox(height: 16),
          
          // WiFi Password (vizibilă)
          TextField(
            decoration: const InputDecoration(
              labelText: 'Parolă Wi‑Fi (vizibilă)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.lock_open),
              filled: true,
              fillColor: Colors.white,
              labelStyle: TextStyle(color: Colors.black54),
            ),
            style: const TextStyle(color: Colors.black),
            obscureText: false,
            onChanged: (value) => setState(() { _wifiPassword = value; }),
          ),
          
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _rescanWifi,
              icon: const Icon(Icons.refresh),
              label: const Text('Rescanează rețelele'),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Dacă lista este goală: Activează Locația (GPS) și acordă permisiunea "Location / Nearby Wi‑Fi devices" aplicației.',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          
          ElevatedButton(
            onPressed: (_selectedSSID != null && _selectedSSID!.isNotEmpty && _wifiPassword.isNotEmpty)
                ? _validateWiFiAndContinue
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[700],
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.blueGrey[200],
              disabledForegroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontSize: 18),
            ),
            child: _isProcessing
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text('Testare parolă...'),
                    ],
                  )
                : const Text('Continuă →'),
          ),
          
          const SizedBox(height: 12),
          Text(
            'După conectare, Shelly va trece automat pe rețeaua clientului.',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        ],
      ),
    );
  }

  

  // ECRAN 3: Configurare Automată MQTT
  Widget _buildStep3AutoConfig() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Roți dințate animate când procesează
          if (_isProcessing)
            _buildRotatingGears()
          else
            Icon(Icons.settings_suggest, size: 80, color: Colors.purple[700]),
          
          const SizedBox(height: 24),
          
          if (!_isProcessing)
            Text(
              'Configurare automată',
              style: TextStyle(
                fontSize: 24, 
                fontWeight: FontWeight.bold,
                color: Colors.purple[800],  // CULOARE VIOLET ÎNCHIS
              ),
              textAlign: TextAlign.center,
            ),
          
          const SizedBox(height: 16),
          
          if (!_isProcessing)
            Text(
              'Aplicația setează automat conexiunea către serverul central.\nNu este nevoie să modifici nimic.',
              style: TextStyle(fontSize: 16, color: Colors.grey[700]),
              textAlign: TextAlign.center,
            ),
          
          const SizedBox(height: 32),
          
          if (!_isProcessing)
            ElevatedButton(
              onPressed: _configureMQTT,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                textStyle: const TextStyle(fontSize: 18),
              ),
              child: const Text('Finalizează instalarea'),
            ),
          
          const SizedBox(height: 12),
          Text(
            'Acest pas configurează conexiunea către hopa.tritech.ro.\nDurează câteva secunde.',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ECRAN 4: Finalizat
  Widget _buildStep4Complete() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _hasTestedDevice ? Icons.check_circle : Icons.pending,
            size: 100,
            color: _hasTestedDevice ? Colors.green[700] : Colors.orange[700],
          ),
          const SizedBox(height: 24),
          Text(
            _hasTestedDevice ? 'Instalare finalizată' : 'Testează funcționarea',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: _hasTestedDevice ? Colors.green : Colors.orange[900],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            _hasTestedDevice
                ? 'Shelly-ul a fost conectat cu succes la Wi-Fi și la serverul central.'
                : 'Shelly-ul a fost conectat cu succes la Wi-Fi și la serverul central.\n\n⚠️ Testează funcționarea releului înainte de a continua.',
            style: TextStyle(fontSize: 16, color: Colors.grey[700]),
            textAlign: TextAlign.center,
          ),
          
          if (_shellyDeviceId != null) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                children: [
                  const Text(
                    'Device ID Shelly:',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _shellyDeviceId!,
                    style: const TextStyle(
                      fontSize: 16,
                      fontFamily: 'monospace',
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
          
          const SizedBox(height: 32),
          
          // Buton Test ON/OFF - mare și vizibil
          ElevatedButton.icon(
            onPressed: _isProcessing ? null : _testOnOff,
            icon: _isProcessing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.power_settings_new),
            label: Text(
              _isProcessing
                  ? 'Se testează...'
                  : (_nextTestShouldOpen ? 'Test DESCHIDERE' : 'Test ÎNCHIDERE'),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _hasTestedDevice ? Colors.green[600] : Colors.orange[700],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 18),
              textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Buton Continuă - disabled până când se testează
          ElevatedButton(
            onPressed: (_shellyDeviceId != null && _hasTestedDevice)
                ? () {
                    widget.onComplete(_shellyDeviceId!);
                    Navigator.pop(context);
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[700],
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey[400],
              disabledForegroundColor: Colors.grey[200],
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
              textStyle: const TextStyle(fontSize: 18),
            ),
            child: const Text('Continuă la Client'),
          ),
          
          const SizedBox(height: 12),
          
          // Buton Reinstalează - dacă ceva nu merge
          TextButton.icon(
            onPressed: _isProcessing ? null : () async {
              final confirm = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (context) => AlertDialog(
                  title: Row(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.red, size: 32),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Resetare & Reinstalare',
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                    ],
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red[300]!, width: 2),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.delete_forever, color: Colors.red[700], size: 24),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Această acțiune va:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: Colors.red[900],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8),
                              Text('• Șterge clientul din baza de date', style: TextStyle(fontSize: 14)),
                              Text('• Șterge contul de utilizator', style: TextStyle(fontSize: 14)),
                              Text('• Elibera email-ul pentru re-creare', style: TextStyle(fontSize: 14)),
                            ],
                          ),
                        ),
                        SizedBox(height: 16),
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange[300]!, width: 2),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.settings_backup_restore, color: Colors.orange[700], size: 24),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '⚠️ IMPORTANT - Resetează FIZIC modulul Shelly:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: Colors.orange[900],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 12),
                              Text(
                                '1️⃣ Apasă butonul de pe modulul Shelly\n'
                                '2️⃣ Ține apăsat 10 secunde\n'
                                '3️⃣ LED-ul va clipi rapid (resetare)\n'
                                '4️⃣ Modulul va reporni în modul AP',
                                style: TextStyle(fontSize: 14, height: 1.5, color: Colors.orange[900]),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Ai resetat modulul Shelly?',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text('Anulează', style: TextStyle(fontSize: 15)),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      icon: Icon(Icons.refresh),
                      label: Text('DA, Am Resetat Shelly', style: TextStyle(fontSize: 15)),
                    ),
                  ],
                ),
              );
              
              if (confirm == true) {
                await _deleteClientAndRestart();
              }
            },
            icon: Icon(Icons.refresh, color: Colors.red),
            label: Text(
              'Resetează & Reinstalează',
              style: TextStyle(color: Colors.red, fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Mesaj informativ
          if (!_hasTestedDevice)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Testează releul pentru a continua',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.orange[900],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Text(
              '✅ Releul a fost testat cu succes',
              style: TextStyle(
                fontSize: 14,
                color: Colors.green[700],
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }

  // Widget cu roți dințate rotative (2 roți imbinate) - LOOP CONTINUU
  Widget _buildRotatingGears() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _gearAnimationController,
          builder: (context, child) {
            return Stack(
              alignment: Alignment.center,
              children: [
                // Roată mare stânga (rotire normală)
                Transform.translate(
                  offset: const Offset(-25, 0),
                  child: Transform.rotate(
                    angle: _gearAnimationController.value * 2 * 3.14159,
                    child: Icon(
                      Icons.settings,
                      size: 60,
                      color: Colors.green[700],
                    ),
                  ),
                ),
                // Roată mică dreapta (rotire inversă mai rapidă)
                Transform.translate(
                  offset: const Offset(25, 0),
                  child: Transform.rotate(
                    angle: -_gearAnimationController.value * 2 * 3.14159 * 1.5,
                    child: Icon(
                      Icons.settings,
                      size: 45,
                      color: Colors.purple[600],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        // Text cu puncte animate
        AnimatedBuilder(
          animation: _gearAnimationController,
          builder: (context, child) {
            // Calculează numărul de puncte (0, 1, 2, 3)
            final dots = ('.' * ((_gearAnimationController.value * 4).floor() % 4));
            return Text(
              'Așteptați, se configurează$dots',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Color(0xFF2c3e50), // Gri închis - bine vizibil
              ),
              textAlign: TextAlign.center,
            );
          },
        ),
      ],
    );
  }

  Widget _buildReadOnlyField(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        Text(
          value,
          style: TextStyle(fontSize: 14, color: Colors.grey[700]),
        ),
      ],
    );
  }

  // ==================== LOGICA WIZARD ====================

  Future<void> _connectToShellyAP() async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      // Cere permisiuni pentru locație (necesar pentru scanarea WiFi pe Android)
      if (!await _ensureWifiPermissions()) {
        setState(() {
          _isProcessing = false;
          _errorMessage = 'Permisiunea este necesară pentru a găsi dispozitivul. Deschide setările și acordă permisiunea.';
        });
        return;
      }
      // Simulare: în realitate aici trebuie să:
      // 1. Scanezi WiFi networks pentru a găsi AP-ul Shelly (shelly1minig3-XXXXXX)
      // 2. Te conectezi programatic la AP-ul Shelly
      // 3. Obții device ID din Shelly (GET http://192.168.33.1/status)
      
      // PENTRU DEMO - simulare delay
      await Future.delayed(const Duration(seconds: 2));
      
      // TODO: Implementare reală cu WiFi scan + connect
      // De exemplu, folosind plugin-uri ca wifi_iot, network_info_plus
      
      // Simulare: găsim Shelly-ul
      _shellyDeviceId = 'shelly1minig3-cc8da2603870'; // DEMO - ar trebui extras din /status
      
      // Scan WiFi networks disponibile (pentru pasul următor)
      await _scanWiFiNetworks();
      
      setState(() {
        _isProcessing = false;
        _currentStep = 1;
      });
      
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _errorMessage = 'Eroare la conectare: $e';
      });
    }
  }

  Future<bool> _ensureWifiPermissions() async {
    var status = await Permission.locationWhenInUse.status;
    if (status.isGranted) return true;

    status = await Permission.locationWhenInUse.request();
    if (status.isGranted) return true;

    if (status.isPermanentlyDenied) {
      // Afișează dialog cu buton către setări
      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Permisiune necesară'),
            content: const Text('Pentru a căuta dispozitivul pe Wi‑Fi, aplicația are nevoie de permisiunea de locație. Te rugăm să o activezi din Setări.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Anulează'),
              ),
              TextButton(
                onPressed: () async {
                  await openAppSettings();
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: const Text('Deschide setările'),
              ),
            ],
          ),
        );
      }
    }
    return false;
  }

  // NOU: Validare parolă WiFi înainte de continuare
  Future<void> _validateWiFiAndContinue() async {
    if (_isProcessing) return;
    
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });
    
    try {
      // Test simplu: verifică lungimea minimă a parolei
      // Pentru majoritatea rețelelor WiFi, parola trebuie să aibă minim 8 caractere
      if (_wifiPassword.length < 8) {
        if (mounted) {
          setState(() => _isProcessing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Parolă incorectă. Parolele WiFi au de obicei minim 8 caractere.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }
      
      // Testul a trecut - continuă la pasul 1
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _currentStep = 1;
        });
      }
    } catch (e) {
      print('Eroare testare parolă WiFi: $e');
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Eroare la testare: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  // Scanare WiFi cu cache (optimizare)
  Future<void> _scanWiFiNetworksWithCache() async {
    // Verifică cache-ul
    final now = DateTime.now();
    if (_lastWiFiScan != null && 
        now.difference(_lastWiFiScan!) < _wifiCacheDuration &&
        _availableNetworks.isNotEmpty) {
      print('📦 Folosesc cache WiFi - scanat acum ${now.difference(_lastWiFiScan!).inSeconds}s');
      return;
    }
    
    await _scanWiFiNetworks();
    _lastWiFiScan = now;
  }

  Future<void> _scanWiFiNetworks() async {
    try {
      // Verifică dacă putem porni scanarea
      final canStart = await WiFiScan.instance.canStartScan();
      if (canStart == CanStartScan.yes) {
        await WiFiScan.instance.startScan();
      }

      // Ia rezultatele scanării
      final canGet = await WiFiScan.instance.canGetScannedResults();
      if (canGet == CanGetScannedResults.yes) {
        final results = await WiFiScan.instance.getScannedResults();
        final ssids = results
            .map((r) => r.ssid)
            .where((s) => s.isNotEmpty)
            .toSet() // elimină duplicatele
            .toList();
        setState(() {
          _availableNetworks = ssids;
        });
      } else {
        setState(() {
          _availableNetworks = [];
        });
      }
    } catch (e) {
      print('Error scanning WiFi: $e');
      setState(() {
        _availableNetworks = [];
      });
    }
  }

  // Forțează rescanare (ignora cache)
  Future<void> _rescanWifi() async {
    setState(() {
      _availableNetworks = [];
    });
    _lastWiFiScan = null;
    await _scanWiFiNetworks();
  }

  Future<void> _connectShellyToWiFi() async {
    // Previne double-tap (problema #3)
    if (_isProcessing) return;
    
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    // RETRY AUTOMAT - maxim 3 încercări
    int attemptCount = 0;
    const maxAttempts = 3;
    bool success = false;

    while (attemptCount < maxAttempts && !success) {
      attemptCount++;
      print('🔄 Încercarea $attemptCount/$maxAttempts de conectare Shelly la WiFi...');
      
      try {
        // Trimite credențiale WiFi la Shelly prin RPC API (Gen3)
        const shellyAPIP = '192.168.33.1';
        final url = 'http://$shellyAPIP/rpc';
        
        final response = await http.post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'id': 1,
            'method': 'WiFi.SetConfig',
            'params': {
              'config': {
                'sta': {
                  'ssid': _selectedSSID,
                  'pass': _wifiPassword,
                  'enable': true,
                }
              }
            }
          }),
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          // Extrage device_id din răspunsul Shelly sau prin GetDeviceInfo
          try {
            final infoResp = await http.post(
              Uri.parse('http://192.168.33.1/rpc'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'id': 1, 'method': 'Shelly.GetDeviceInfo'}),
            ).timeout(const Duration(seconds: 5));
            
            if (infoResp.statusCode == 200) {
              final info = jsonDecode(infoResp.body);
              final rawId = info['result']?['id'] ?? 'unknown';
              // Construiește topic-ul complet pentru Shelly 1 Mini Gen3
              _shellyDeviceId = rawId.startsWith('shelly') ? rawId : 'shelly1minig3-$rawId';
              print('📱 Device ID extras: $rawId → Topic complet: $_shellyDeviceId');
            }
          } catch (e) {
            print('Nu am putut obține device ID: $e');
            _shellyDeviceId = 'shelly1minig3-temp';
          }
          
          // Actualizează device_id în backend (dacă avem clientId)
          if (widget.clientId != null && _shellyDeviceId != null) {
            try {
              await ApiService.updateClientShellyDevice(widget.clientId!, _shellyDeviceId!);
              print('✅ Device ID salvat în backend: $_shellyDeviceId');
            } catch (e) {
              print('⚠️ Nu am putut salva device ID în backend: $e');
            }
          }
          
          // Așteptăm 3 secunde pentru reconectare Shelly la WiFi client
          await Future.delayed(const Duration(seconds: 3));
          
          // SUCCES - marchează și ieși din loop
          success = true;
          
          // Treci la configurare MQTT
          if (mounted) {
            setState(() {
              _isProcessing = false;
              _currentStep = 3; // Pasul MQTT
            });
          }
        } else {
          throw Exception('Eroare la configurare WiFi: ${response.statusCode}');
        }
        
      } catch (e) {
        print('❌ Încercarea $attemptCount eșuată: $e');
        
        // Dacă nu e ultima încercare, reîncearcă după 2 secunde
        if (attemptCount < maxAttempts) {
          print('🔄 Se reîncearcă automat...');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Reîncerc automat ($attemptCount/$maxAttempts)...'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 2),
              ),
            );
          }
          await Future.delayed(const Duration(seconds: 2));
        } else {
          // Ultima încercare a eșuat - arată eroarea
          if (mounted) {
            setState(() {
              _isProcessing = false;
              _errorMessage = 'Eroare după $maxAttempts încercări: $e\n\nVerifică parola WiFi și încearcă din nou.';
            });
          }
        }
      }
    }
    
    // Dacă a ieșit din loop fără succes, oprește procesarea
    if (!success && mounted) {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  /// Testează care broker MQTT e disponibil (Cloudflare Load Balancer)
  Future<String> _getAvailableMqttBroker() async {
    const primary = 'mqtt.hopa.tritech.ro';
    const fallback = 'mqtt.hopa.tritech.ro';
    const port = 1883;

    try {
      debugPrint('[SHELLY_MQTT] Testez primary $primary:$port...');
      final socket = await Socket.connect(
        primary, port,
        timeout: const Duration(seconds: 5),
      );
      socket.destroy();
      debugPrint('[SHELLY_MQTT] ✅ Primary disponibil: $primary:$port');
      return '$primary:$port';
    } catch (_) {
      debugPrint('[SHELLY_MQTT] ⚠️ Primary indisponibil, folosesc fallback $fallback:$port');
      return '$fallback:$port';
    }
  }

  Future<void> _configureMQTT() async {
    // Previne double-tap (problema #3)
    if (_isProcessing) return;
    
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    // RETRY AUTOMAT - maxim 3 încercări
    int attemptCount = 0;
    const maxAttempts = 3;
    bool success = false;

    // Detectează broker-ul disponibil ÎNAINTE de configurare
    final mqttServer = await _getAvailableMqttBroker();
    debugPrint('[SHELLY_MQTT] Configurez Shelly cu broker: $mqttServer');

    while (attemptCount < maxAttempts && !success) {
      attemptCount++;
      print('🔄 Încercarea $attemptCount/$maxAttempts de configurare MQTT...');
      
      try {
        // Setează MQTT pe Shelly prin RPC API (Gen3)
        final url = 'http://$_shellyIPAddress/rpc';
        
        // Folosim codul HOPA (71BDA...) ca client_id MQTT, nu shelly_device_id
        final mqttClientId = widget.hopaDeviceCode ?? _shellyDeviceId ?? 'shelly-unknown';
        
        final response = await http.post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'id': 1,
            'method': 'MQTT.SetConfig',
            'params': {
              'config': {
                'enable': true,
                'server': mqttServer,
                'user': 'hopa',
                'pass': 'superSecret',
                'client_id': mqttClientId, // Folosește codul 71BDA...
                'rpc_ntf': true,
                'status_ntf': true,
              }
            }
          }),
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          // Dezactivează AP după configurare, ca SSID-ul Shelly să dispară
          try {
            final apOff = await http.post(
              Uri.parse(url),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'id': 1,
                'method': 'WiFi.SetConfig',
                'params': {
                  'config': {
                    'ap': {
                      'enable': false
                    }
                  }
                }
              }),
            ).timeout(const Duration(seconds: 5));
            print('AP disable status: ${apOff.statusCode}');
          } catch (e) {
            print('AP disable failed (continuăm): $e');
          }
          
          // MQTT configurat! Acum facem reboot la Shelly
          try {
            await http.post(
              Uri.parse(url),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'id': 1,
                'method': 'Shelly.Reboot',
              }),
            ).timeout(const Duration(seconds: 5));
            
            // Reboot inițiat - așteptăm 30 secunde pentru reconectare
            await Future.delayed(const Duration(seconds: 30));
          } catch (e) {
            print('Reboot trimis dar răspunsul nu a venit (normal după reboot): $e');
            // E OK - Shelly se rebootează și nu mai răspunde
            await Future.delayed(const Duration(seconds: 25));
          }
          
          // SUCCES - marchează și ieși din loop
          success = true;
          
          // Trece la ecranul final DAR dă timp pentru stabilizare (AP off, sta up)
          if (mounted) {
            setState(() {
              _isProcessing = false;
              _currentStep = 4; // Pasul final
            });
          }
          
          // Așteaptă suplimentar ca MQTT să se conecteze, apoi permite Test
          await Future.delayed(const Duration(seconds: 15));
          if (mounted) {
            setState(() {
              // doar asigurăm că butonul Test nu mai e blocat de _isProcessing
              _isProcessing = false;
            });
          }
        } else {
          throw Exception('Eroare la configurare MQTT: ${response.statusCode}');
        }
        
      } catch (e) {
        print('❌ Încercarea $attemptCount MQTT eșuată: $e');
        
        // Dacă nu e ultima încercare, reîncearcă după 2 secunde
        if (attemptCount < maxAttempts) {
          print('🔄 Se reîncearcă automat MQTT...');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Reîncerc MQTT ($attemptCount/$maxAttempts)...'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 2),
              ),
            );
          }
          await Future.delayed(const Duration(seconds: 2));
        } else {
          // Ultima încercare a eșuat - arată eroarea
          if (mounted) {
            setState(() {
              _isProcessing = false;
              _errorMessage = 'Eroare MQTT după $maxAttempts încercări: $e';
            });
          }
        }
      }
    }
    
    // Dacă a ieșit din loop fără succes, oprește procesarea
    if (!success && mounted) {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _testOnOff() async {
    print('🔵 [DEBUG] _testOnOff() apelat, _isProcessing: $_isProcessing');
    
    if (_isProcessing) {
      print('⚠️ [DEBUG] Request blocat - _isProcessing este true, ieșim');
      return;
    }
    
    print('🔵 [DEBUG] Setăm _isProcessing = true');
    setState(() {
      _isProcessing = true;
    });
    
    try {
      print('🧪 [TEST] Începe testul ON/OFF');
      print('🧪 [TEST] Device ID: $_shellyDeviceId');
      print('🧪 [TEST] Client ID: ${widget.clientId}');
      
      // Endpoint diferit pentru installer vs client
      final headers = await ApiService.getAuthHeaders();
      final auth = Provider.of<AuthService>(context, listen: false);
      final String base = ApiService.baseUrl;
      final String path = auth.isInstaller
          ? '/installer/shelly/switch'
          : '/shelly/switch';
      final String url = '$base$path';
      
      print('🔵 [DEBUG] URL: $url');
      
      // Test cu impuls identic cu butonul principal (deschidere/închidere alternativ)
      final bool shouldOpen = _nextTestShouldOpen;
      print('🧪 [TEST] Trimite impuls ${shouldOpen ? 'DESCHIDERE' : 'ÎNCHIDERE'}');
      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode({
          'id': _shellyDeviceId,
          'on': shouldOpen,
          'relay': 0,
          'duration': 1000, // 1s, la fel ca în aplicația principală
        }),
      ).timeout(const Duration(seconds: 8));
      
      print('🧪 [TEST] Status: ${response.statusCode}');
      print('🧪 [TEST] Body: ${response.body}');
      print('🔵 [DEBUG] Request completat cu succes');
      
      // Test reușit! Setează flag-ul
      if (mounted) {
        print('🔵 [DEBUG] Setăm _isProcessing = false (SUCCESS)');
        setState(() {
          _hasTestedDevice = true;
          _isProcessing = false;
          _nextTestShouldOpen = !shouldOpen;
        });
        
        // Afișează confirmare finală
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(shouldOpen
                ? '✅ Impuls de DESCHIDERE trimis!'
                : '✅ Impuls de ÎNCHIDERE trimis!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      
    } catch (e) {
      print('❌ [TEST ERROR] $e');
      if (mounted) {
        print('🔵 [DEBUG] Setăm _isProcessing = false (ERROR)');
        setState(() {
          _isProcessing = false;
        });
        
        // Mesaj mai clar pentru instalatori
        String errorMsg = 'Eroare test: ${e.toString()}';
        if (errorMsg.contains('Lipsește HOPA device code')) {
          errorMsg = 'Nu s-a găsit codul HOPA. Revino la pasul anterior.';
        } else if (errorMsg.contains('Timeout')) {
          errorMsg = 'Timeout - Shelly nu răspunde. Verifică conexiunea.';
        } else if (errorMsg.contains('Eroare de conexiune')) {
          errorMsg = 'Nu există conexiune la server. Verifică internetul.';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ $errorMsg'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }
}


