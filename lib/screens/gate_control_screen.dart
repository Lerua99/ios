import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/theme_service.dart';
import '../services/notification_service.dart';
import '../widgets/logo_widget.dart';
import '../widgets/remotio_button.dart';
import '../widgets/pedestrian_button.dart';
import '../widgets/garage_button.dart';
import 'settings_screen.dart';
import 'contact_installer_screen.dart';
import '../services/api_service.dart';
import '../services/gate_control_service.dart';
// import '../services/shelly_cloud_service.dart'; // ELIMINAT - folosim doar MQTT/EMQX
import 'statistics_screen.dart';
import 'package:http/http.dart' as http;
import 'shelly_devices_screen.dart';
import '../providers/gate_provider.dart';
import 'guest_invitation_screen.dart';
import 'messages_screen.dart';
import 'notification_settings_screen.dart'; // NOU: Importăm ecranul cu mesajele SOS

// Tipurile de porți
enum GateType { principal, pedestrian, garage }

// Enum pentru statusurile de conexiune
enum ConnectionStatus {
  connected, // Verde - totul OK
  error, // Roșu - probleme
  unavailable, // Gri - indisponibil
}

class GateControlScreen extends StatefulWidget {
  const GateControlScreen({super.key});

  @override
  State<GateControlScreen> createState() => _GateControlScreenState();
}

class _GateControlScreenState extends State<GateControlScreen>
    with TickerProviderStateMixin {
  GateType _activeGate = GateType.principal;
  bool _isAnimating = false;
  bool _isActivating = false;
  bool _isLoading = true;
  // Starea precedentă pentru a detecta tranziții și a afișa SnackBar
  String _prevGateState = '';
  String _lastSnackState = '';
  DateTime? _lastActivationTime; // Pentru debounce

  // Lista porților disponibile (se încarcă de la server)
  List<GateType> _availableGates = [];
  // Mapare GateType -> gateId din backend (pentru apelul API)
  final Map<GateType, String> _gateIds = {};

  // Animații
  late AnimationController _rotationController;
  late AnimationController _scaleController;
  late AnimationController _arrowController;
  late Animation<double> _rotationAnimation;
  late Animation<double> _scaleAnimation;

  // Informații despre porți
  final Map<GateType, Map<String, dynamic>> _gateInfo = {
    GateType.principal: {
      'name': 'Poartă Principală',
      'displayName': 'Poartă\nPrincipală',
      'icon': Icons.other_houses,
      'color': Colors.blue,
    },
    GateType.pedestrian: {
      'name': 'Poartă Pietonală',
      'displayName': 'Poartă\nPietonală',
      'icon': Icons.directions_walk,
      'color': Colors.green,
    },
    GateType.garage: {
      'name': 'Ușă de Garaj',
      'displayName': 'Ușă\nde Garaj',
      'icon': Icons.garage,
      'color': Colors.orange,
    },
  };

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _arrowController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    _rotationAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _rotationController,
        curve: Curves.easeInOutCubic,
      ),
    );

    _scaleAnimation = Tween<double>(begin: 1, end: 1.1).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );

    // Încarcă configurația porților de la server
    _loadGatesConfiguration();
  }

  // Încarcă configurația porților de la server
  Future<void> _loadGatesConfiguration() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final token = authService.token;

      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/client/gates-config'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          final client = data['data']['client'];
          final gatesConfig = client['gates_config'];

          List<GateType> availableGates = [];

          // Verifică poarta principală (întotdeauna există dacă gates_config există)
          if (gatesConfig['primary_gate'] != null) {
            final primaryGate = gatesConfig['primary_gate'];
            final primaryType = primaryGate['type'];
            if (primaryType == 'batanta') {
              availableGates.add(GateType.principal);
              _gateIds[GateType.principal] =
                  primaryGate['id']?.toString() ?? 'principal';
            } else if (primaryType == 'pietonala') {
              availableGates.add(GateType.pedestrian);
              _gateIds[GateType.pedestrian] =
                  primaryGate['id']?.toString() ?? 'pedestrian';
            } else if (primaryType == 'garaj') {
              availableGates.add(GateType.garage);
              _gateIds[GateType.garage] =
                  primaryGate['id']?.toString() ?? 'garage';
            }
          }

          // Verifică porțile secundare (max 2)
          if (gatesConfig['secondary_gates'] != null &&
              gatesConfig['secondary_gates'] is List) {
            final secondaryGates = gatesConfig['secondary_gates'] as List;
            for (var gate in secondaryGates) {
              final gateType = gate['type'];
              if (gateType == 'batanta') {
                if (!availableGates.contains(GateType.principal))
                  availableGates.add(GateType.principal);
                _gateIds[GateType.principal] ??=
                    gate['id']?.toString() ?? 'principal';
              } else if (gateType == 'pietonala') {
                if (!availableGates.contains(GateType.pedestrian))
                  availableGates.add(GateType.pedestrian);
                _gateIds[GateType.pedestrian] ??=
                    gate['id']?.toString() ?? 'pedestrian';
              } else if (gateType == 'garaj') {
                if (!availableGates.contains(GateType.garage))
                  availableGates.add(GateType.garage);
                _gateIds[GateType.garage] ??=
                    gate['id']?.toString() ?? 'garage';
              }
            }
          }

          setState(() {
            _availableGates = availableGates;
            if (availableGates.isNotEmpty) {
              _activeGate = availableGates.first;
            }
            _isLoading = false;
          });

          print('✅ Porți disponibile: ${availableGates.length}');
        }
      } else {
        // Răspuns non-200 ⇒ foloseşte configuraţia implicită şi opreşte spinner-ul
        setState(() {
          _availableGates = [GateType.principal];
          _isLoading = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Eroare server (${response.statusCode}). Se foloseşte configuraţia implicită.',
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      print('🔴 Eroare încărcare configurație: $e');
      // În caz de eroare, folosește configurația implicită
      setState(() {
        _availableGates = [GateType.principal]; // doar poarta principală
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _scaleController.dispose();
    _arrowController.dispose();
    super.dispose();
  }

  // Obține porțile inactive (cele care apar jos)
  List<GateType> get _inactiveGates {
    return _availableGates.where((gate) => gate != _activeGate).toList();
  }

  // Schimbă poarta activă cu animație
  Future<void> _switchGate(GateType newGate) async {
    if (_isAnimating || newGate == _activeGate) return;

    setState(() {
      _isAnimating = true;
    });

    HapticFeedback.lightImpact();

    // Animație de rotație
    await _rotationController.forward();

    setState(() {
      _activeGate = newGate;
    });

    await _rotationController.reverse();

    setState(() {
      _isAnimating = false;
    });
  }

  // Status-ul porții este acum gestionat de GateProvider

  // Activează poarta curentă
  Future<void> _activateGate() async {
    // Verifică dacă provider-ul e inițializat (previne primul click în gol)
    if (!_gate.isInitialized) {
      print('⚠️ GateProvider nu e încă inițializat, reîncearcă...');
      await _gate.refresh();
      // Dacă starea încă nu e disponibilă, anulează
      if (!_gate.isInitialized) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Se încarcă starea porții, te rog reîncearcă...'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }
    }

    // ELIMINAT TOATE BLOCAJELE - permitem click instant
    // Nu mai verificăm _isActivating sau _isBusy

    // DEBOUNCE MINIM - doar 100ms pentru a evita dubluri accidentale
    if (_lastActivationTime != null) {
      final timeSinceLastActivation = DateTime.now().difference(
        _lastActivationTime!,
      );
      if (timeSinceLastActivation.inMilliseconds < 100) {
        print('⏱️ Debounce: Ignorăm dublura (<100ms)');
        return;
      }
    }
    _lastActivationTime = DateTime.now();

    // Identifică gateId pentru poarta activă
    final String? gateId = _gateIds[_activeGate];

    // NU mai setăm _isActivating pentru a nu bloca
    // setState(() {
    //   _isActivating = true;
    // });

    HapticFeedback.mediumImpact();

    // Animație de scalare și rotire
    _scaleController.forward();
    _arrowController.forward(from: 0);

    try {
      // Verifică tipul dispozitivului pentru control
      final prefs = await SharedPreferences.getInstance();
      final deviceType = prefs.getString('device_type') ?? 'esp32';

      // DETERMINĂM ACȚIUNEA bazat pe starea CURENTĂ din provider
      final bool isCurrentlyOpen = _gate.isOpen;
      final String action = _gate.isInitialized
          ? (isCurrentlyOpen ? 'close' : 'open')
          : 'toggle';
      final String currentState = _gate.isInitialized
          ? (isCurrentlyOpen ? "DESCHISĂ" : "ÎNCHISĂ")
          : "NECUNOSCUTĂ";
      print(
        '🎯 Control $deviceType - Stare: $currentState → Comandă: ${action.toUpperCase()}',
      );

      Map<String, dynamic> apiResp;

      if (deviceType == 'shelly') {
        // 🌐 CONTROL SHELLY prin EMQX/MQTT (backend)
        print('🌐 Control SHELLY prin EMQX/MQTT!');
        apiResp = await ApiService.shellySwitch(on: action == 'open');

        // Logging deja se face în backend
      } else {
        // 📡 CONTROL ESP32 prin backend (MQTT)
        print('📡 Control ESP32 prin backend MQTT!');
        apiResp = await ApiService.controlGate(gateId, action);
      }

      // Considerăm succes dacă nu aruncă exception (API-ul Shelly răspunde)
      print('✅ Gate control $deviceType trimis');
    } catch (e) {
      print('🔴 Eroare backend: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Eroare: ${e.toString().replaceAll('Exception: ', '').replaceAll('TimeoutException: ', '')}',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }

    // ACTUALIZARE INSTANTĂ LOCAL pentru click rapid
    if (_gate.isInitialized) {
      _gate.toggleLocalState();
    }

    _scaleController.reverse();

    // Refresh în background după 1 secundă (nu blochează)
    Future.delayed(Duration(seconds: 1), () {
      if (mounted) {
        _gate.refresh();
      }
    });

    if (!mounted) return;

    // Eliminat snackbar-ul de feedback pentru open/close
  }

  // Funcție pentru a deschide poarta (buton DESCHIDE)
  Future<void> _openGate() async {
    // Verifică dacă provider-ul e inițializat
    if (!_gate.isInitialized) {
      print('⚠️ GateProvider nu e încă inițializat pentru _openGate');
      await _gate.refresh();
      if (!_gate.isInitialized) return;
    }

    final String? gateId = _gateIds[_activeGate];

    // PERMITEM COMANDĂ RAPIDĂ - verificăm doar dacă poarta e deja deschisă
    if (_isGateOpenProvider || _isBusy) return;

    HapticFeedback.mediumImpact();

    try {
      Map<String, dynamic> apiResp;
      if (_activeGate == GateType.pedestrian) {
        // control local ESP direct
        final res = await GateControlService.controlGate('open');
        apiResp = {'success': res.success, 'message': res.message};
      } else {
        apiResp = await ApiService.controlGate(gateId, 'open');
      }
      if (apiResp['success'] == true) {
        await _gate.refresh();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 10),
                Text('Poarta s-a deschis!'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(apiResp['message'] ?? 'Eroare la deschiderea porții'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Eroare de conexiune'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Funcție pentru a închide poarta (buton ÎNCHIDE)
  Future<void> _closeGate() async {
    // Verifică dacă provider-ul e inițializat
    if (!_gate.isInitialized) {
      print('⚠️ GateProvider nu e încă inițializat pentru _closeGate');
      await _gate.refresh();
      if (!_gate.isInitialized) return;
    }

    // PERMITEM COMANDĂ RAPIDĂ - verificăm doar dacă poarta e deja închisă
    if (!_isGateOpenProvider || _isBusy) return;

    HapticFeedback.mediumImpact();

    try {
      Map<String, dynamic> apiResp;
      if (_activeGate == GateType.pedestrian) {
        final res = await GateControlService.controlGate('close');
        apiResp = {'success': res.success, 'message': res.message};
      } else {
        apiResp = await ApiService.controlGate(null, 'close');
      }
      if (apiResp['success'] == true) {
        await _gate.refresh();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 10),
                Text('Poarta s-a închis!'),
              ],
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(apiResp['message'] ?? 'Eroare la închiderea porții'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Eroare de conexiune'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Funcție pentru dialog SOS
  void _showSOSDialog() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ContactInstallerScreen()),
    );
    return;
    String selectedGate = _gateInfo[_activeGate]!['name'];
    String problemDescription = '';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: Colors.grey[900],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header cu iconița de warning
                    Row(
                      children: [
                        Icon(Icons.warning, color: Colors.red, size: 30),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Contactează Instalatorul',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Selector poartă
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Selectează poarta cu probleme:',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 15),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.teal, width: 2),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: DropdownButton<String>(
                        value: selectedGate,
                        isExpanded: true,
                        dropdownColor: Colors.grey[800],
                        style: TextStyle(color: Colors.white, fontSize: 16),
                        underline: SizedBox(),
                        icon: Icon(Icons.arrow_drop_down, color: Colors.white),
                        items: _gateInfo.values.map((gate) {
                          return DropdownMenuItem<String>(
                            value: gate['name'],
                            child: Text(gate['name']),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          setState(() {
                            selectedGate = newValue!;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Descriere problemă
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Descrie problema:',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      maxLines: 4,
                      style: TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Ex: Ușa de garaj nu se deschide complet...',
                        hintStyle: TextStyle(color: Colors.grey),
                        filled: true,
                        fillColor: Colors.grey[800],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (value) {
                        problemDescription = value;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Info box
                    Container(
                      padding: EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info, color: Colors.blue, size: 24),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Instalatorul va primi notificare și vă va programa pentru intervenție.',
                              style: TextStyle(
                                color: Colors.blue,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Butoane
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                            child: Text(
                              'Anulează',
                              style: TextStyle(
                                color: Colors.teal,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              // Aici ar fi logica de trimitere SOS
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('SOS trimis către instalator!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              padding: EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.play_arrow, color: Colors.white),
                                const SizedBox(width: 5),
                                Text(
                                  'Trimite SOS',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Funcție pentru dialog notificări
  void _showNotificationsDialog() {
    // Navigare la ecranul separat de notificări
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const NotificationSettingsScreen(),
      ),
    );
  }

  void _showNotificationsDialogOLD() {
    // VECHIUL DIALOG - PĂSTRAT CA BACKUP
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  children: [
                    Icon(Icons.notifications, color: Colors.amber, size: 30),
                    const SizedBox(width: 10),
                    Text(
                      'Setări Notificări',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Notificare familie
                Container(
                  padding: EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.family_restroom, color: Colors.blue, size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Notificări Familie',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Primește notificări când un membru al familiei deschide poarta',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Consumer<NotificationService>(
                        builder: (context, notificationService, child) {
                          return Switch(
                            value: notificationService.familyNotifications,
                            onChanged: (value) async {
                              await notificationService.setFamilyNotifications(
                                value,
                              );
                            },
                            activeColor: Colors.blue,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // Notificări Push (master)
                Container(
                  padding: EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.notifications_active,
                        color: Colors.amber,
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Notificări Push',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Activează/dezactivează toate notificările',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Consumer<NotificationService>(
                        builder: (context, notificationService, child) {
                          return Switch(
                            value: notificationService.pushNotifications,
                            onChanged: (value) async {
                              await notificationService.setPushNotifications(
                                value,
                              );
                            },
                            activeColor: Colors.amber,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Notificare probleme tehnice
                Container(
                  padding: EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning, color: Colors.orange, size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Probleme Tehnice',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Alertă pentru dispozitiv offline sau temperatură mare',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Consumer<NotificationService>(
                        builder: (context, notificationService, child) {
                          return Switch(
                            value: notificationService.technicalProblems,
                            onChanged: (value) async {
                              await notificationService.setTechnicalProblems(
                                value,
                              );
                            },
                            activeColor: Colors.orange,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // Notificări Marketing
                Container(
                  padding: EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.campaign, color: Colors.purple, size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Notificări Marketing',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Primește oferte promoționale și reduceri',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Consumer<NotificationService>(
                        builder: (context, notificationService, child) {
                          return Switch(
                            value: notificationService.marketingNotifications,
                            onChanged: (value) async {
                              await notificationService
                                  .setMarketingNotifications(value);
                            },
                            activeColor: Colors.purple,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Notificare service
                Container(
                  padding: EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.build, color: Colors.green, size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Service Necesar',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Notificare după numărul de cicluri setat',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Consumer<NotificationService>(
                        builder: (context, notificationService, child) {
                          return Switch(
                            value: notificationService.serviceRequired,
                            onChanged: (value) async {
                              await notificationService.setServiceRequired(
                                value,
                              );
                            },
                            activeColor: Colors.green,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Buton închidere
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    padding: EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: Text(
                    'Salvează',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final themeService = Provider.of<ThemeService>(context);
    final userName = authService.userData?['name'] ?? 'Client';

    return Consumer<GateProvider>(
      builder: (context, gateProvider, _) {
        // Inițializez _lastSnackState la prima redare pentru a evita SnackBar la pornire
        if (_lastSnackState.isEmpty) {
          _lastSnackState = gateProvider.state;
        }

        // Elimin notificările vizuale Snackbar pentru schimbarea stării porții

        _prevGateState = gateProvider.state;

        // Calculez flaguri de stare pentru UI
        final isBusy =
            gateProvider.state == 'opening' ||
            gateProvider.state == 'closing' ||
            gateProvider.state == 'stopped' ||
            gateProvider.sensorActive;
        final isOpen = gateProvider.state == 'open';

        return PopScope(
          canPop: true,
          onPopInvoked: (didPop) {
            if (!didPop) {
              SystemNavigator.pop();
            }
          },
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: themeService.getBackgroundWidget(
              Stack(
                children: [
                  // Pentru temele cu gradient nu mai avem nevoie de overlay
                  if (!themeService.currentThemeData.hasGradient) ...[
                    // Background image pentru temele fără gradient
                    Container(
                      decoration: const BoxDecoration(
                        image: DecorationImage(
                          image: AssetImage('assets/home_background.jpg'),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    // Dark overlay pentru temele fără gradient
                    Container(color: Colors.black.withOpacity(0.4)),
                  ],
                  // Content
                  SafeArea(
                    child: _isLoading
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const LogoWidget(size: 95, showText: false),
                                const SizedBox(height: 30),
                                CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 3,
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  'Se încarcă configurația...',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Column(
                            children: [
                              // Main content with logo and welcome text
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // Large HOPA logo
                                    const LogoWidget(size: 90, showText: false),
                                    const SizedBox(height: 18),
                                    // Welcome text personalizat cu numele utilizatorului (pe două linii)
                                    Column(
                                      children: [
                                        Text(
                                          'Bine ai venit',
                                          style: TextStyle(
                                            color: _getTextColor(),
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                            shadows: [
                                              Shadow(
                                                blurRadius: 6,
                                                color: Colors.black,
                                                offset: Offset(1, 1),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          userName,
                                          style: TextStyle(
                                            color: _getTextColor(),
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            shadows: [
                                              Shadow(
                                                blurRadius: 6,
                                                color: Colors.black,
                                                offset: Offset(1, 1),
                                              ),
                                            ],
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 28),
                                    // (Text status poartă eliminat - revenire la design anterior)
                                    // Active gate indicator
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.3),
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        _gateInfo[_activeGate]!['name'],
                                        style: TextStyle(
                                          color: _getTextColor(),
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 30),
                                    // Indicator de inițializare (dacă provider-ul nu e gata)
                                    if (!gateProvider.isInitialized)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 10,
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white.withOpacity(
                                                  0.7,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Se încarcă starea...',
                                              style: TextStyle(
                                                color: Colors.white.withOpacity(
                                                  0.7,
                                                ),
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    // Buton specific porții active
                                    (_activeGate == GateType.pedestrian)
                                        ? PedestrianButton(
                                            onPressed:
                                                (isBusy ||
                                                    !gateProvider.isInitialized)
                                                ? null
                                                : _activateGate,
                                            label: isBusy
                                                ? 'SE MIȘCĂ...'
                                                : 'HOPA',
                                            size: 200,
                                          )
                                        : (_activeGate == GateType.garage)
                                        ? GarageButton(
                                            onPressed:
                                                (isBusy ||
                                                    !gateProvider.isInitialized)
                                                ? null
                                                : _activateGate,
                                            label: isBusy
                                                ? 'SE MIȘCĂ...'
                                                : 'HOPA',
                                            size: 200,
                                          )
                                        : RemotioButton(
                                            onPressed:
                                                (isBusy ||
                                                    !gateProvider.isInitialized)
                                                ? null
                                                : _activateGate,
                                            label: isBusy
                                                ? 'SE MIȘCĂ...'
                                                : 'HOPA',
                                            size: 200,
                                          ),
                                    const SizedBox(height: 30),
                                  ],
                                ),
                              ),

                              // Bottom navigation cu butoane pentru porți (doar dacă sunt mai multe porți)
                              if (_availableGates.length > 1)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 20,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.3),
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(24),
                                      topRight: Radius.circular(24),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: _inactiveGates.map((gateType) {
                                      return _buildGateNavigationButton(
                                        gateType,
                                      );
                                    }).toList(),
                                  ),
                                ),

                              // Bară de navigație cu 6 icoane colorate
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.15),
                                  border: Border(
                                    top: BorderSide(
                                      color: Colors.white.withOpacity(0.2),
                                      width: 1,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    // Setări - primul din stânga
                                    IconButton(
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                const SettingsScreen(),
                                          ),
                                        );
                                      },
                                      icon: Icon(
                                        Icons.settings,
                                        color: Colors.blue.shade400,
                                        size: 32,
                                      ),
                                    ),
                                    // Statistici - doar pentru PRO (lazy loaded)
                                    if (Provider.of<AuthService>(context).isPro)
                                      IconButton(
                                        onPressed: () async {
                                          // Lazy load - ecranul se încarcă doar când e necesar
                                          await Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  const StatisticsScreen(),
                                            ),
                                          );
                                        },
                                        icon: Icon(
                                          Icons.history,
                                          color: Colors.green.shade400,
                                          size: 32,
                                        ),
                                      ),
                                    // SOS / Cheie tehnică
                                    IconButton(
                                      onPressed: _showSOSDialog,
                                      icon: Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: Text(
                                            'SOS',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    // NOU: Buton pentru Cererile mele SOS
                                    IconButton(
                                      icon: Icon(
                                        Icons.list_alt,
                                        color: Colors.cyan.shade400,
                                        size: 32,
                                      ),
                                      onPressed: () async {
                                        await Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (context) => MessagesScreen(
                                              onRead: () {
                                                // TODO: aici poți adăuga refresh badge messages dacă e implementat
                                              },
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    // Notificări - doar PRO
                                    if (Provider.of<AuthService>(context).isPro)
                                      IconButton(
                                        onPressed: _showNotificationsDialog,
                                        icon: Icon(
                                          Icons.notifications,
                                          color: Colors.amber.shade400,
                                          size: 32,
                                        ),
                                      ),
                                    // Guest Invitations - doar PRO
                                    if (Provider.of<AuthService>(context).isPro)
                                      IconButton(
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  GuestInvitationScreen(),
                                            ),
                                          );
                                        },
                                        icon: Icon(
                                          Icons.people,
                                          color: Colors.purple.shade400,
                                          size: 32,
                                        ),
                                      ),
                                    // Ieșire
                                    IconButton(
                                      onPressed: () {
                                        authService.logout();
                                        Navigator.popUntil(
                                          context,
                                          (route) => route.isFirst,
                                        );
                                      },
                                      icon: Icon(
                                        Icons.logout,
                                        color: Colors.orange.shade400,
                                        size: 32,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ), // Închidere pentru getBackgroundWidget
          ),
        );
      }, // Închidere Consumer<GateProvider>
    );
  }

  Widget _buildGateNavigationButton(GateType gateType) {
    final gateInfo = _gateInfo[gateType]!;
    final isInactive = gateType != _activeGate;

    return GestureDetector(
      onTap: () => _switchGate(gateType),
      child: Container(
        width: 140,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
        ),
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  gateInfo['icon'],
                  size: 42,
                  color: isInactive
                      ? Colors.white.withOpacity(0.5)
                      : Colors.white,
                ),
                const SizedBox(height: 10),
                Text(
                  gateInfo['displayName'] ?? gateInfo['name'],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isInactive
                        ? Colors.white.withOpacity(0.5)
                        : Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                ),
              ],
            ),
            // Badge pentru porțile inactive
            if (isInactive)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.lock, size: 12, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionStatusBar() {
    return Row(
      children: [
        // Bluetooth Status (HOPA connectivity)
        _buildStatusIcon(
          icon: Icons.bluetooth,
          status: _getBluetoothStatus(),
          tooltip: 'Status HOPA Bluetooth',
        ),
        const SizedBox(width: 8),

        // WiFi Status (Internet connectivity)
        _buildStatusIcon(
          icon: Icons.wifi,
          status: _getWiFiStatus(),
          tooltip: 'Status conexiune internet',
        ),
        const SizedBox(width: 8),

        // ESP32 Access Point Status (Local connectivity)
        _buildStatusIcon(
          icon: Icons.router,
          status: _getEsp32Status(),
          tooltip: 'Status ESP32 local',
        ),
      ],
    );
  }

  Widget _buildStatusIcon({
    required IconData icon,
    required ConnectionStatus status,
    required String tooltip,
  }) {
    Color color;
    switch (status) {
      case ConnectionStatus.connected:
        color = Colors.green;
        break;
      case ConnectionStatus.error:
        color = Colors.red;
        break;
      case ConnectionStatus.unavailable:
        color = Colors.grey;
        break;
    }

    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }

  // Verifică statusul real Bluetooth/HOPA
  ConnectionStatus _getBluetoothStatus() {
    // Verifică dacă Bluetooth-ul este activ și disponibil
    try {
      // În realitate ar verifica starea Bluetooth-ului și conexiunea HOPA
      // Pentru acum simulez o logică de bază
      return ConnectionStatus.connected; // Status funcțional
    } catch (e) {
      return ConnectionStatus.error;
    }
  }

  // Verifică statusul real WiFi/Internet
  ConnectionStatus _getWiFiStatus() {
    // În realitate ar folosi connectivity_plus package pentru verificare
    try {
      // Simulez o verificare de conectivitate
      return ConnectionStatus.connected; // Status funcțional
    } catch (e) {
      return ConnectionStatus.error;
    }
  }

  // Verifică statusul real ESP32
  ConnectionStatus _getEsp32Status() {
    // În realitate ar face ping sau API call la ESP32
    try {
      // Simulez o verificare de conectivitate ESP32
      return ConnectionStatus.unavailable; // ESP32 offline
    } catch (e) {
      return ConnectionStatus.error;
    }
  }

  // Funcțiile _getButtonColor și _getStateText nu mai sunt necesare
  // Logica de culoare și text se face direct în Consumer<GateProvider>

  Color _getTextColor() {
    // Pentru contul Standard - text alb pentru contrast mai bun
    final authService = Provider.of<AuthService>(context, listen: false);
    final accountType = authService.userData?['account_type'] ?? 'Standard';

    if (accountType == 'Standard') {
      return Colors.white;
    }

    // Pentru alte conturi - culoare normală
    return Colors.white;
  }

  // --- Helper pentru acces GateProvider rapid ---
  GateProvider get _gate => Provider.of<GateProvider>(context, listen: false);

  bool get _isGateOpenProvider => _gate.state == 'open';
  bool get _isBusy =>
      _gate.state == 'opening' ||
      _gate.state == 'closing' ||
      _gate.state == 'stopped' ||
      _gate.sensorActive;

  /// Notifică backend-ul despre acțiunea de control pentru logging
  void _notifyBackendAboutAction(String? gateId, String action) async {
    try {
      // Logging asyncron - nu așteptăm răspuns
      ApiService.controlGate(gateId, action)
          .then((result) {
            print('📊 Logging la backend: ${result['success']}');
          })
          .catchError((e) {
            print('⚠️ Logging la backend eșuat: $e');
          });
    } catch (e) {
      print('⚠️ Eroare la notificare backend: $e');
    }
  }
}
