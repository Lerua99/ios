import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/theme_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../services/api_service.dart';
import '../services/security_service.dart';
import 'help_screen.dart';

enum _TagSyncResult { notPairedOnHub, alreadyInApp, enrolledNow, failed }

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const String _cameraMacPrefsKey = 'hopa_camera_mac';

  final TextEditingController _deviceNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  // ignore: unused_field
  String? _fcmToken; // token local - folosit în _registerToken
  // ignore: unused_field
  final bool _sendingToken = false; // status - folosit în _registerToken
  // ignore: unused_field
  List<dynamic> _plans = [];
  // ignore: unused_field
  bool _loadingPlans = false;
  bool _loadingHopaDevices = false;
  bool _startingPairing = false;
  bool _restartingHub = false;
  bool _rf433Busy = false;
  bool _loadingRf433Status = false;
  bool _securityBusy = false;
  List<Map<String, dynamic>> _hopaDevices = [];
  int _hopaLimit = 0;
  int _hopaTagCount = 0;
  int _hopaModuleCount = 0;
  int _hopaTotalCount = 0;
  int _rf433RemoteLimit = 1;
  int _rf433RemoteCount = 0;
  int _rf433RemoteFree = 1;
  int _rf433SlotMask = 0;
  int _rf433ClearSlot = 0; // 0 = nimic selectat
  bool _canEnrollMore = true;
  String _clientModuleType = 'unknown';
  DateTime? _hubPairingUntil;
  Timer? _hubPairingTimer;
  bool _pairingAttempted = false;
  bool _tagSyncInProgress = false;
  bool _pairingWatcherRunning = false;
  bool _moduleSyncInProgress = false;
  bool _modulePairingWatcherRunning = false;
  final Set<int> _offlineAlertInFlight = <int>{};
  final Map<int, DateTime> _offlineAlertCooldown = <int, DateTime>{};
  bool _biometricSupported = false;
  bool _biometricEnabled = false;
  bool _hasSecurityPin = false;
  String _protectionMode = SecurityService.modeAllSensitive;
  final TextEditingController _rf433LimitController = TextEditingController(
    text: '1',
  );

  @override
  void initState() {
    super.initState();
    // Obține tokenul FCM pentru afișare rapidă
    FirebaseMessaging.instance
        .getToken()
        .then((token) {
          if (mounted) setState(() => _fcmToken = token);
        })
        .catchError((error) {
          // Ignorăm eroarea Firebase - nu e critică pentru funcționarea aplicației
          debugPrint('⚠️ Nu s-a putut obține FCM token: $error');
        });
    _fetchPlans();
    _initSecurity();
    _loadClientModuleType();
  }

  Future<void> _fetchPlans() async {
    setState(() => _loadingPlans = true);
    try {
      _plans = await ApiService.getSubscriptionPlans();
    } catch (_) {}
    setState(() => _loadingPlans = false);
  }

  // ignore: unused_element
  Future<void> _upgradePlan(int planId) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    Navigator.pop(context); // close dialog
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Se activează abonamentul...')),
    );
    try {
      await ApiService.upgradeSubscription(planId, 0);
      await authService.syncSubscriptionStatus();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.green,
          content: Text('Abonament activat cu succes!'),
        ),
      );
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('Eroare la upgrade: $e'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _hubPairingTimer?.cancel();
    _deviceNameController.dispose();
    _phoneController.dispose();
    _rf433LimitController.dispose();
    super.dispose();
  }

  Future<int> _getClientId() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final value = authService.userData?['client_id'];
    if (value is int) {
      return value;
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  Future<void> _initSecurity() async {
    final supported = await SecurityService.isBiometricAvailable();
    final enabled = await SecurityService.isBiometricEnabled();
    final hasPin = await SecurityService.hasPin();
    final mode = await SecurityService.getProtectionMode();

    if (!mounted) return;
    setState(() {
      _biometricSupported = supported;
      _biometricEnabled = enabled && supported;
      _hasSecurityPin = hasPin;
      _protectionMode = mode;
    });
  }

  int _toInt(dynamic value, [int fallback = 0]) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? fallback;
    if (value is num) return value.toInt();
    return fallback;
  }

  bool _toBool(dynamic value, [bool fallback = false]) {
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    if (value is num) return value != 0;
    return fallback;
  }

  String _normalizeMacAddress(String raw) {
    final cleaned = raw.trim().toUpperCase().replaceAll('-', ':');
    if (!RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$').hasMatch(cleaned)) {
      return '';
    }
    return cleaned;
  }

  String _normalizeClientModuleType(String raw) {
    final v = raw.trim().toLowerCase();
    if (v == 'shelly') return 'shelly';
    if (v == 'hopa' || v == 'esp32') return 'hopa';
    return 'hopa';
  }

  bool get _isHopaModule => _clientModuleType == 'hopa';

  Future<void> _loadClientModuleType() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('device_type') ?? '';
      final normalized = _normalizeClientModuleType(raw);
      if (!mounted) return;
      setState(() => _clientModuleType = normalized);
    } catch (_) {
      if (mounted) {
        setState(() => _clientModuleType = 'hopa');
      }
    }

    if (_isHopaModule) {
      await _loadHopaDevices(showErrors: false);
      unawaited(_refreshRf433Status(showErrors: false));
    }
  }

  bool get _hubPairingActive =>
      _hubPairingUntil != null && _hubPairingUntil!.isAfter(DateTime.now());

  int get _hubPairingSecondsLeft {
    if (!_hubPairingActive) return 0;
    return _hubPairingUntil!
        .difference(DateTime.now())
        .inSeconds
        .clamp(0, 9999);
  }

  int _rf433LimitMask(int limit) {
    if (limit <= 0) return 0;
    if (limit >= 30) return 0x3FFFFFFF;
    return (1 << limit) - 1;
  }

  List<int> _rf433UsedSlots() {
    final used = <int>[];
    for (int i = 0; i < _rf433RemoteLimit; i++) {
      if ((_rf433SlotMask & (1 << i)) != 0) {
        used.add(i + 1);
      }
    }
    return used;
  }

  Future<void> _refreshRf433Status({bool showErrors = false}) async {
    if (_loadingRf433Status) return;
    _loadingRf433Status = true;
    try {
      final local = await ApiService.getHopaHubStatusLocal();

      int parsedLimit = _toInt(local['rf433_remote_limit'], _rf433RemoteLimit);
      if (parsedLimit < 1) parsedLimit = 1;
      if (parsedLimit > 9) parsedLimit = 9;

      int parsedCount = _toInt(local['rf433_remote_count'], _rf433RemoteCount);
      if (parsedCount < 0) parsedCount = 0;
      if (parsedCount > parsedLimit) parsedCount = parsedLimit;

      int parsedFree = _toInt(
        local['rf433_remote_free'],
        parsedLimit - parsedCount,
      );
      if (parsedFree < 0) parsedFree = 0;
      if (parsedFree > parsedLimit) parsedFree = parsedLimit;

      int parsedMask = _toInt(local['rf433_slot_mask'], _rf433SlotMask);
      if (parsedMask <= 0 && parsedCount > 0) {
        parsedMask = (1 << parsedCount) - 1;
      }
      parsedMask = parsedMask & _rf433LimitMask(parsedLimit);

      int clearSlot = _rf433ClearSlot;
      if (clearSlot > 0) {
        final used = (parsedMask & (1 << (clearSlot - 1))) != 0;
        if (clearSlot > parsedLimit || !used) {
          clearSlot = 0;
        }
      }

      if (!mounted) return;
      setState(() {
        _rf433RemoteLimit = parsedLimit;
        _rf433RemoteCount = parsedCount;
        _rf433RemoteFree = parsedFree;
        _rf433SlotMask = parsedMask;
        _rf433ClearSlot = clearSlot;
        _rf433LimitController.text = parsedLimit.toString();
      });
    } catch (e) {
      if (!mounted || !showErrors) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('Nu am putut citi status RF433: $e'),
        ),
      );
    } finally {
      _loadingRf433Status = false;
    }
  }

  DateTime? _parseIsoDate(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return null;
    try {
      return DateTime.parse(raw).toLocal();
    } catch (_) {
      return null;
    }
  }

  void _startHubPairingMonitor({required int duration, DateTime? expiresAt}) {
    _hubPairingTimer?.cancel();

    final now = DateTime.now();
    final fallbackUntil = now.add(Duration(seconds: duration));
    final effectiveUntil = (expiresAt != null && expiresAt.isAfter(now))
        ? expiresAt
        : fallbackUntil;

    setState(() {
      _pairingAttempted = true;
      _hubPairingUntil = effectiveUntil;
    });

    _hubPairingTimer = Timer.periodic(const Duration(seconds: 2), (
      timer,
    ) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (!_hubPairingActive) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _hubPairingUntil = null;
          });
        }
        await _loadHopaDevices(showErrors: false);
        return;
      }

      await _loadHopaDevices(showErrors: false);
      if (mounted) {
        setState(() {});
      }
    });
  }

  List<Map<String, dynamic>> _devicesByType(String type) {
    return _hopaDevices.where((device) {
      final name = (device['device_name'] ?? '').toString();
      return _normalizeDeviceType(device['device_type'], name) == type;
    }).toList();
  }

  Map<String, dynamic>? _deviceByTypeIndex(String type, int index) {
    final items = _devicesByType(type);
    if (index < 0 || index >= items.length) return null;
    return items[index];
  }

  Future<void> _triggerOfflineAlerts(List<Map<String, dynamic>> devices) async {
    // Dezactivat: nu mai trimitem push-uri de tip offline pentru module.
    return;
  }

  Future<_TagSyncResult> _syncLocalPairedTagIfMissing(
    int clientId,
    List<Map<String, dynamic>> devices, {
    bool showSuccess = false,
    bool showAlreadyInApp = false,
    bool showErrors = false,
  }) async {
    if (_tagSyncInProgress) return _TagSyncResult.failed;

    _tagSyncInProgress = true;
    try {
      final local = await ApiService.getHopaHubStatusLocal();
      final paired = _toBool(local['tag_paired'], false);
      final localMac = _normalizeMacAddress(
        (local['tag_mac'] ?? '').toString(),
      );

      if (!paired || localMac.isEmpty) {
        return _TagSyncResult.notPairedOnHub;
      }

      final exists = devices.any((d) {
        final mac = _normalizeMacAddress((d['mac_address'] ?? '').toString());
        return mac == localMac;
      });
      if (exists) {
        if (showAlreadyInApp && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.blueGrey,
              content: Text('TAG-ul este deja în aplicație'),
            ),
          );
        }
        return _TagSyncResult.alreadyInApp;
      }

      final suffixRaw = localMac.replaceAll(':', '');
      final suffix = suffixRaw.length >= 5
          ? suffixRaw.substring(suffixRaw.length - 5)
          : suffixRaw;

      final enrollResp = await ApiService.enrollHopaDevice(
        clientId: clientId,
        macAddress: localMac,
        deviceType: 'tag',
        deviceName: 'TAG $suffix',
        rssi: -45,
      );

      final ok = _toBool(enrollResp['success'], false);
      if (ok) {
        await _loadHopaDevices(showErrors: false);
        if (showSuccess && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.green,
              content: Text('✅ TAG împerecheat și adăugat în aplicație'),
            ),
          );
        }
        return _TagSyncResult.enrolledNow;
      }
      return _TagSyncResult.failed;
    } catch (e) {
      if (showErrors && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('Nu s-a putut sincroniza TAG-ul: $e'),
          ),
        );
      }
      return _TagSyncResult.failed;
    } finally {
      _tagSyncInProgress = false;
    }
  }

  Future<void> _watchPairingForTagSync(int clientId, int durationSec) async {
    if (_pairingWatcherRunning) return;
    _pairingWatcherRunning = true;

    final deadline = DateTime.now().add(Duration(seconds: durationSec + 8));
    try {
      while (mounted && DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(seconds: 2));
        final snapshot = List<Map<String, dynamic>>.from(_hopaDevices);
        final result = await _syncLocalPairedTagIfMissing(
          clientId,
          snapshot,
          showSuccess: true,
        );
        if (result == _TagSyncResult.enrolledNow ||
            result == _TagSyncResult.alreadyInApp) {
          return;
        }
      }
    } finally {
      _pairingWatcherRunning = false;
    }
  }

  Future<bool> _syncLocalPairedModulesIfMissing(
    int clientId,
    List<Map<String, dynamic>> devices, {
    bool showSuccess = false,
    bool showErrors = false,
  }) async {
    if (_moduleSyncInProgress) return false;

    _moduleSyncInProgress = true;
    try {
      final local = await ApiService.getHopaHubStatusLocal();
      final candidates = <Map<String, dynamic>>[];

      final cameraPaired = _toBool(local['camera_paired'], false);
      final cameraMac = _normalizeMacAddress(
        (local['camera_mac'] ?? '').toString(),
      );
      if (cameraPaired && cameraMac.isNotEmpty) {
        candidates.add({
          'type': 'camera',
          'mac': cameraMac,
          'name': 'CAMERA ${cameraMac.substring(cameraMac.length - 5)}',
        });
      }

      final switch1Paired = _toBool(local['switch_1_paired'], false);
      final switch1Mac = _normalizeMacAddress(
        (local['switch_1_mac'] ?? '').toString(),
      );
      if (switch1Paired && switch1Mac.isNotEmpty) {
        candidates.add({
          'type': 'switch',
          'mac': switch1Mac,
          'name': 'SWITCH 1 ${switch1Mac.substring(switch1Mac.length - 5)}',
        });
      }

      final switch2Paired = _toBool(local['switch_2_paired'], false);
      final switch2Mac = _normalizeMacAddress(
        (local['switch_2_mac'] ?? '').toString(),
      );
      if (switch2Paired && switch2Mac.isNotEmpty) {
        candidates.add({
          'type': 'switch',
          'mac': switch2Mac,
          'name': 'SWITCH 2 ${switch2Mac.substring(switch2Mac.length - 5)}',
        });
      }

      bool enrolledAny = false;
      for (final candidate in candidates) {
        final mac = candidate['mac'].toString();
        final exists = devices.any((d) {
          final dbMac = _normalizeMacAddress(
            (d['mac_address'] ?? '').toString(),
          );
          return dbMac == mac;
        });
        if (exists) continue;

        final enrollResp = await ApiService.enrollHopaDevice(
          clientId: clientId,
          macAddress: mac,
          deviceType: candidate['type'].toString(),
          deviceName: candidate['name'].toString(),
          rssi: -45,
        );

        final ok = _toBool(enrollResp['success'], false);
        if (ok) {
          enrolledAny = true;
        }
      }

      if (enrolledAny) {
        await _loadHopaDevices(showErrors: false);
        if (showSuccess && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.green,
              content: Text('✅ Module sincronizate automat din HUB'),
            ),
          );
        }
      }

      return enrolledAny;
    } catch (e) {
      if (showErrors && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('Nu s-au putut sincroniza modulele: $e'),
          ),
        );
      }
      return false;
    } finally {
      _moduleSyncInProgress = false;
    }
  }

  Future<void> _watchPairingForModuleSync(int clientId, int durationSec) async {
    if (_modulePairingWatcherRunning) return;
    _modulePairingWatcherRunning = true;

    final deadline = DateTime.now().add(Duration(seconds: durationSec + 8));
    try {
      while (mounted && DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(seconds: 2));
        final snapshot = List<Map<String, dynamic>>.from(_hopaDevices);
        final enrolled = await _syncLocalPairedModulesIfMissing(
          clientId,
          snapshot,
          showSuccess: true,
        );
        if (enrolled) {
          return;
        }
      }
    } finally {
      _modulePairingWatcherRunning = false;
    }
  }

  Future<void> _loadHopaDevices({bool showErrors = true}) async {
    final clientId = await _getClientId();
    if (clientId <= 0) return;
    if (_loadingHopaDevices) return;

    if (mounted) {
      setState(() => _loadingHopaDevices = true);
    }

    try {
      final response = await ApiService.getHopaDevices(clientId);
      final List<dynamic> devicesRaw = response['devices'] ?? [];
      final client = response['client'] ?? {};
      final devices = devicesRaw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      final activeTagCountFromList = devices.where((device) {
        final name = (device['device_name'] ?? '').toString();
        final type = _normalizeDeviceType(device['device_type'], name);
        return type == 'tag' && _toBool(device['is_active'], true);
      }).length;

      final activeModuleCountFromList = devices.where((device) {
        final name = (device['device_name'] ?? '').toString();
        final type = _normalizeDeviceType(device['device_type'], name);
        return (type == 'camera' || type == 'switch') &&
            _toBool(device['is_active'], true);
      }).length;

      final parsedLimit = _toInt(client['hopa_limit']);
      final parsedTagCount = _toInt(
        client['hopa_tag_count'],
        _toInt(client['hopa_count'], activeTagCountFromList),
      );
      final parsedModuleCount = _toInt(
        client['hopa_module_count'],
        activeModuleCountFromList,
      );
      final parsedTotalCount = _toInt(
        client['hopa_total_count'],
        parsedTagCount + parsedModuleCount,
      );
      final canEnrollTag = _toBool(
        client['can_enroll_tag'],
        _toBool(
          client['can_enroll_more'],
          parsedLimit > 0 ? parsedTagCount < parsedLimit : false,
        ),
      );

      if (!mounted) return;
      setState(() {
        _hopaDevices = devices;
        _hopaLimit = parsedLimit;
        _hopaTagCount = parsedTagCount;
        _hopaModuleCount = parsedModuleCount;
        _hopaTotalCount = parsedTotalCount;
        _canEnrollMore = canEnrollTag;
      });
      unawaited(_cacheCameraMac(devices));
      unawaited(_refreshRf433Status(showErrors: false));
      // Offline alert push dezactivat la cererea clientului.
      // unawaited(_triggerOfflineAlerts(devices));
    } catch (e) {
      if (!mounted || !showErrors) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('Eroare la încărcarea dispozitivelor: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _loadingHopaDevices = false);
      }
    }
  }

  Future<void> _cacheCameraMac(List<Map<String, dynamic>> devices) async {
    final prefs = await SharedPreferences.getInstance();
    String cameraMac = '';
    for (final device in devices) {
      final name = (device['device_name'] ?? '').toString();
      final type = _normalizeDeviceType(device['device_type'], name);
      if (type != 'camera') continue;
      final mac = _normalizeMacAddress(
        (device['mac_address'] ?? '').toString(),
      );
      if (mac.isEmpty) continue;
      cameraMac = mac;
      break;
    }

    if (cameraMac.isNotEmpty) {
      await prefs.setString(_cameraMacPrefsKey, cameraMac);
    }
  }

  Future<String?> _askPin({
    required String title,
    required String actionLabel,
  }) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'PIN (4-6 cifre)',
              labelStyle: TextStyle(color: Colors.grey[400]),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.grey[600]!),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.teal),
              ),
            ),
            validator: (v) {
              final pin = (v ?? '').trim();
              if (pin.length < 4 || pin.length > 6) {
                return 'PIN invalid';
              }
              if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
                return 'Doar cifre';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anulează', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(context, controller.text.trim());
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            child: Text(actionLabel),
          ),
        ],
      ),
    );

    controller.dispose();
    return value;
  }

  Future<bool> _configurePin() async {
    final pin1 = await _askPin(
      title: 'Setează PIN de securitate',
      actionLabel: 'Continuă',
    );
    if (pin1 == null) return false;
    final pin2 = await _askPin(title: 'Confirmă PIN', actionLabel: 'Salvează');
    if (pin2 == null) return false;

    if (pin1 != pin2) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('PIN-urile nu coincid'),
        ),
      );
      return false;
    }

    await SecurityService.savePin(pin1);
    if (!mounted) return true;
    setState(() => _hasSecurityPin = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Colors.green,
        content: Text('PIN salvat'),
      ),
    );
    return true;
  }

  Future<bool> _verifyPin() async {
    final pin = await _askPin(title: 'Confirmă PIN', actionLabel: 'Confirmă');
    if (pin == null) return false;
    final ok = await SecurityService.verifyPin(pin);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('PIN greșit'),
        ),
      );
    }
    return ok;
  }

  Future<void> _setProtectionMode(String mode) async {
    await SecurityService.setProtectionMode(mode);
    if (!mounted) return;
    setState(() => _protectionMode = mode);
  }

  Future<bool> _authorizeSensitiveAction(
    String reason, {
    bool isDelete = false,
  }) async {
    if (_protectionMode == SecurityService.modeDeleteOnly && !isDelete) {
      return true;
    }

    if (_securityBusy) return false;
    _securityBusy = true;

    try {
      if (_biometricEnabled) {
        final bioOk = await SecurityService.authenticateWithBiometrics(reason);
        if (bioOk) return true;
      }

      if (!_hasSecurityPin) {
        final configured = await _configurePin();
        if (!configured) return false;
      }

      return _verifyPin();
    } finally {
      _securityBusy = false;
    }
  }

  Future<void> _toggleBiometric(bool enabled) async {
    if (!enabled) {
      await SecurityService.setBiometricEnabled(false);
      if (!mounted) return;
      setState(() => _biometricEnabled = false);
      return;
    }

    if (!_biometricSupported) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orange,
          content: Text('Biometria nu este disponibilă pe acest dispozitiv'),
        ),
      );
      return;
    }

    if (!_hasSecurityPin) {
      final configured = await _configurePin();
      if (!configured) return;
    }

    final bioOk = await SecurityService.authenticateWithBiometrics(
      'Confirmă activarea autentificării biometrice',
    );
    if (!bioOk) return;

    await SecurityService.setBiometricEnabled(true);
    if (!mounted) return;
    setState(() => _biometricEnabled = true);
  }

  Future<void> _startHopaPairing({
    String target = 'tag',
    String? deviceType,
  }) async {
    final clientId = await _getClientId();
    if (clientId <= 0) return;

    if (target == 'tag' && !_canEnrollMore) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orange,
          content: Text(
            'Limita de TAG-uri este atinsă. Șterge un TAG și încearcă din nou.',
          ),
        ),
      );
      return;
    }

    final authorized = await _authorizeSensitiveAction(
      'Confirmă pornirea pairing-ului HOPA',
      isDelete: false,
    );
    if (!authorized) return;

    if (target == 'tag') {
      final preSyncResult = await _syncLocalPairedTagIfMissing(
        clientId,
        List<Map<String, dynamic>>.from(_hopaDevices),
        showSuccess: true,
        showAlreadyInApp: true,
        showErrors: false,
      );
      if (preSyncResult == _TagSyncResult.enrolledNow ||
          preSyncResult == _TagSyncResult.alreadyInApp) {
        await _loadHopaDevices(showErrors: false);
        return;
      }
    }

    if (!mounted) return;
    setState(() => _startingPairing = true);

    try {
      final response = await ApiService.startHopaPairing(
        clientId: clientId,
        duration: 60,
        target: target,
        deviceType: deviceType,
      );
      final duration = _toInt(response['duration'], 60).clamp(30, 300);
      final expiresAt = _parseIsoDate(response['expires_at']);
      _startHubPairingMonitor(duration: duration, expiresAt: expiresAt);
      await _loadHopaDevices(showErrors: false);
      if (target == 'tag') {
        unawaited(_watchPairingForTagSync(clientId, duration));
      } else if (target == 'module') {
        unawaited(_watchPairingForModuleSync(clientId, duration));
      }

      if (!mounted) return;
      final msg = (response['message'] ?? 'Pairing pornit').toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.green, content: Text('✅ $msg')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('Pairing eșuat: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _startingPairing = false);
      }
    }
  }

  Future<void> _setRf433LimitOnly() async {
    if (_rf433Busy) return;
    final clientId = await _getClientId();
    if (clientId <= 0) return;

    final parsedLimit = int.tryParse(_rf433LimitController.text.trim());
    if (parsedLimit == null || parsedLimit < 1 || parsedLimit > 9) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orange,
          content: Text('Limita telecomenzi trebuie să fie între 1 și 9.'),
        ),
      );
      return;
    }

    if (parsedLimit < _rf433RemoteCount) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.orange,
          content: Text(
            'Ai deja $_rf433RemoteCount telecomenzi. Limita nu poate fi mai mică.',
          ),
        ),
      );
      return;
    }

    final authorized = await _authorizeSensitiveAction(
      'Confirmă schimbarea limitei RF433',
      isDelete: false,
    );
    if (!authorized) return;

    if (!mounted) return;
    setState(() => _rf433Busy = true);
    try {
      final response = await ApiService.startHopaPairing(
        clientId: clientId,
        duration: 0,
        target: 'remote',
        deviceType: 'rf433',
        remoteLimit: parsedLimit,
      );
      await _refreshRf433Status(showErrors: false);

      if (!mounted) return;
      final msg = (response['message'] ?? 'Limita RF433 actualizată')
          .toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.green, content: Text('✅ $msg')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('Setare limită eșuată: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _rf433Busy = false);
      }
    }
  }

  Future<void> _startRf433Pairing() async {
    if (_rf433Busy) return;
    final clientId = await _getClientId();
    if (clientId <= 0) return;

    final parsedLimit = int.tryParse(_rf433LimitController.text.trim());
    if (parsedLimit == null || parsedLimit < 1 || parsedLimit > 9) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orange,
          content: Text('Limita telecomenzi trebuie să fie între 1 și 9.'),
        ),
      );
      return;
    }

    if (parsedLimit < _rf433RemoteCount) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.orange,
          content: Text(
            'Ai deja $_rf433RemoteCount telecomenzi. Mărește limita înainte de pairing.',
          ),
        ),
      );
      return;
    }

    if ((_rf433RemoteCount >= parsedLimit) &&
        parsedLimit == _rf433RemoteLimit) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orange,
          content: Text(
            'Nu există slot liber. Mărește limita sau șterge un slot.',
          ),
        ),
      );
      return;
    }

    final authorized = await _authorizeSensitiveAction(
      'Confirmă împerecherea telecomenzii RF433',
      isDelete: false,
    );
    if (!authorized) return;

    if (!mounted) return;
    setState(() => _rf433Busy = true);
    try {
      final response = await ApiService.startHopaPairing(
        clientId: clientId,
        duration: 60,
        target: 'remote',
        deviceType: 'rf433',
        remoteLimit: parsedLimit,
      );
      await _refreshRf433Status(showErrors: false);

      if (!mounted) return;
      final msg = (response['message'] ?? 'Pairing telecomandă pornit')
          .toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.green, content: Text('✅ $msg')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('Pairing telecomandă eșuat: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _rf433Busy = false);
      }
    }
  }

  Future<void> _clearRf433Pairing({int? slot}) async {
    if (_rf433Busy) return;

    final title = slot == null
        ? 'Confirmă ștergerea tuturor telecomenzilor RF433'
        : 'Confirmă ștergerea telecomenzii din slotul $slot';
    final authorized = await _authorizeSensitiveAction(title, isDelete: true);
    if (!authorized) return;

    if (!mounted) return;
    setState(() => _rf433Busy = true);
    try {
      final response = await ApiService.clearHopaPairingLocal(
        deviceType: 'remote',
        remoteSlot: slot,
      );
      await _refreshRf433Status(showErrors: false);

      if (!mounted) return;
      final msg = (response['message'] ?? 'Telecomandă RF433 ștearsă')
          .toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.green, content: Text('✅ $msg')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('Ștergere telecomandă eșuată: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _rf433Busy = false);
      }
    }
  }

  Future<void> _restartHubAndRefresh() async {
    if (_restartingHub) return;

    final authorized = await _authorizeSensitiveAction(
      'Confirmă restart modul HUB',
      isDelete: false,
    );
    if (!authorized) return;

    if (!mounted) return;
    setState(() => _restartingHub = true);

    try {
      final response = await ApiService.restartHopaHubLocal();
      if (!mounted) return;

      final message = (response['message'] ?? 'Restart trimis').toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.orange[700],
          content: Text('🔄 $message'),
        ),
      );

      await Future.delayed(const Duration(seconds: 8));
      await _loadHopaDevices(showErrors: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('Restart eșuat: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _restartingHub = false);
      }
    }
  }

  Future<void> _toggleHopaDeviceActive(Map<String, dynamic> device) async {
    final deviceId = device['id'];
    if (deviceId is! int) return;
    final active = device['is_active'] == true;
    final action = active ? 'blochează' : 'deblochează';

    final ok = await _authorizeSensitiveAction(
      'Confirmă că vrei să $action acest tag',
      isDelete: false,
    );
    if (!ok) return;

    try {
      await ApiService.updateHopaDevice(deviceId, {'is_active': !active});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green,
          content: Text(active ? 'Tag blocat' : 'Tag deblocat'),
        ),
      );
      await _loadHopaDevices();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('Eroare la actualizare: $e'),
        ),
      );
    }
  }

  Future<void> _removeHopaDevice(Map<String, dynamic> device) async {
    final deviceId = device['id'];
    if (deviceId is! int) return;
    final name = (device['device_name'] ?? 'Device').toString();
    final mac = (device['mac_address'] ?? '').toString();
    final type = _normalizeDeviceType(device['device_type'], name);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Șterge dispozitiv',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Sigur vrei să ștergi "$name"?',
          style: TextStyle(color: Colors.grey[300]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anulează', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Șterge'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final ok = await _authorizeSensitiveAction(
      'Confirmă ștergerea dispozitivului',
      isDelete: true,
    );
    if (!ok) return;

    try {
      String? localUnpairError;
      if (type == 'tag' || type == 'camera' || type == 'switch') {
        try {
          await ApiService.clearHopaPairingLocal(
            tagMac: type == 'tag' ? mac : null,
            deviceType: type,
            deviceMac: mac,
          );
        } catch (e) {
          // Nu blocăm ștergerea din backend dacă HUB local nu răspunde.
          localUnpairError = e.toString().replaceAll('Exception: ', '');
        }
      }

      await ApiService.removeHopaDevice(deviceId);
      if (!mounted) return;
      if (localUnpairError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.orange[700],
            content: Text(
              'Dispozitiv șters din aplicație. HUB local nu a confirmat desperecherea: $localUnpairError',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            content: Text(
              type == 'tag' ? 'TAG șters definitiv' : 'Dispozitiv șters',
            ),
          ),
        );
      }
      await _loadHopaDevices();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            type == 'tag'
                ? 'Eroare la ștergere TAG: $e'
                : 'Eroare la ștergere: $e',
          ),
        ),
      );
    }
  }

  Future<void> _changeHopaDeviceType(Map<String, dynamic> device) async {
    final deviceId = device['id'];
    if (deviceId is! int) return;
    final name = (device['device_name'] ?? 'HOPA Device').toString();
    final currentType = _normalizeDeviceType(device['device_type'], name);

    final selectedType = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Text(
              'Tip dispozitiv pentru "$name"',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            ...['tag', 'camera', 'switch'].map((type) {
              final selected = type == currentType;
              return ListTile(
                leading: Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selected ? Colors.teal : Colors.grey,
                ),
                title: Text(
                  _deviceTypeLabel(type),
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(context, type),
              );
            }),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    if (selectedType == null || selectedType == currentType) return;

    final ok = await _authorizeSensitiveAction(
      'Confirmă schimbarea tipului dispozitivului',
      isDelete: false,
    );
    if (!ok) return;

    try {
      await ApiService.updateHopaDevice(deviceId, {
        'device_type': selectedType,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green,
          content: Text('Tip actualizat la ${_deviceTypeLabel(selectedType)}'),
        ),
      );
      await _loadHopaDevices();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('Eroare la schimbarea tipului: $e'),
        ),
      );
    }
  }

  Future<void> _editDeviceName(String currentName) async {
    _deviceNameController.text = currentName;

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Editează numele dispozitivului',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: _deviceNameController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Nume dispozitiv',
            labelStyle: TextStyle(color: Colors.grey[400]),
            hintText: 'Ex: Poartă spate, Poartă vecin',
            hintStyle: TextStyle(color: Colors.grey[600]),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.grey[600]!),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.teal),
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anulează', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context, _deviceNameController.text.trim());
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            child: const Text('Salvează'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      if (!mounted) return;
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.updateDeviceName(result);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nume dispozitiv actualizat!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _changePhoneNumber(String currentPhone) async {
    _phoneController.text = currentPhone;

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Schimbă numărul de telefon',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'După schimbare vei primi un nou cod!',
                      style: TextStyle(color: Colors.orange[700], fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Număr telefon nou',
                labelStyle: TextStyle(color: Colors.grey[400]),
                hintText: '+40 7XX XXX XXX',
                hintStyle: TextStyle(color: Colors.grey[600]),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey[600]!),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.orange),
                ),
              ),
              keyboardType: TextInputType.phone,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anulează', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context, _phoneController.text.trim());
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Schimbă și trimite cod'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      if (!mounted) return;
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.updatePhoneNumber(result);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Număr de telefon actualizat!'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _changeAutomationSystem(String currentSystem) async {
    final systems = [
      'BFT',
      'FAAC',
      'Nice',
      'CAME',
      'Beninca',
      'Motorline',
      'Sommer',
      'Hörmann',
    ];

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange, size: 24),
            const SizedBox(width: 10),
            Text(
              'Selectează marca (OBLIGATORIU)',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (currentSystem.isEmpty || currentSystem == '-') ...[
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error, color: Colors.red[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'TREBUIE să selectezi marca pentru a continua!',
                        style: TextStyle(
                          color: Colors.red[700],
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            SizedBox(
              width: double.maxFinite,
              height: 300,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: systems.length,
                itemBuilder: (context, index) {
                  final system = systems[index];
                  final isSelected = system == currentSystem;

                  return Container(
                    margin: EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: isSelected ? Colors.teal : Colors.grey[700]!,
                        width: isSelected ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListTile(
                      title: Text(
                        system,
                        style: TextStyle(
                          color: isSelected ? Colors.teal : Colors.white,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontSize: 16,
                        ),
                      ),
                      trailing: isSelected
                          ? Icon(
                              Icons.check_circle,
                              color: Colors.teal,
                              size: 24,
                            )
                          : Icon(
                              Icons.radio_button_unchecked,
                              color: Colors.grey[500],
                              size: 24,
                            ),
                      onTap: () => Navigator.pop(context, system),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        actions: [
          if (currentSystem.isNotEmpty && currentSystem != '-') ...[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Anulează', style: TextStyle(color: Colors.grey)),
            ),
          ],
        ],
      ),
    );

    if (result != null) {
      if (!mounted) return;
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.updateSystemType(result);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sistem schimbat în $result'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // ignore: unused_element
  void _showVoiceCommandsInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Row(
          children: [
            Icon(
              Platform.isIOS ? Icons.mic : Icons.assistant,
              color: Platform.isIOS ? Colors.blue : Colors.orange,
              size: 28,
            ),
            const SizedBox(width: 10),
            Text(
              Platform.isIOS ? 'Comenzi Siri' : 'Comenzi Google Assistant',
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Comenzile vocale activate:',
              style: TextStyle(
                color: Colors.grey[300],
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            _buildVoiceCommand(
              '🔓',
              'Deschide poarta',
              '"Hey ${Platform.isIOS ? 'Siri' : 'Google'}, Hopa"',
            ),
            _buildVoiceCommand(
              '🔒',
              'Închide poarta',
              '"Hey ${Platform.isIOS ? 'Siri' : 'Google'}, Hopa închide"',
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Platform.isIOS ? Colors.blue : Colors.orange,
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceCommand(String emoji, String action, String command) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(emoji, style: TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  command,
                  style: TextStyle(
                    color: Platform.isIOS
                        ? Colors.blue[300]
                        : Colors.orange[300],
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // _registerToken păstrat pentru viitor - dezactivat momentan
  // Future<void> _registerToken() async {
  //   setState(() => _sendingToken = true);
  //   try {
  //     final token = await FirebaseMessaging.instance.getToken();
  //     if (token != null) {
  //       await ApiService.updateFcmToken(token);
  //       setState(() => _fcmToken = token);
  //       if (mounted) {
  //         ScaffoldMessenger.of(context).showSnackBar(
  //           const SnackBar(content: Text('✅ Token FCM trimis la server')),
  //         );
  //       }
  //     } else if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         const SnackBar(content: Text('❌ Nu s-a putut obține token FCM')),
  //       );
  //     }
  //   } catch (e) {
  //     if (!mounted) return;
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(content: Text('Eroare: $e')),
  //     );
  //   } finally {
  //     if (mounted) setState(() => _sendingToken = false);
  //   }
  // }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final themeService = Provider.of<ThemeService>(context);
    final userData = authService.userData;
    final isClient = authService.isClient;

    final name = userData?['name'] ?? 'N/A';
    final accountType = userData?['account_type'] ?? 'Standard';
    final clientCode = userData?['activation_code'] ?? 'N/A';
    final phone = userData?['phone'] ?? 'N/A';
    final address = userData?['address'] ?? 'N/A';
    final systemType = userData?['system_type'] ?? '';
    final displaySystemType = systemType.isEmpty || systemType == '-'
        ? 'OBLIGATORIU - Selectează marca'
        : systemType;
    final device = userData?['device'] ?? 'Poartă Principală';

    final formattedAddress = address
        .replaceAll('CT', 'Constanța')
        .replaceAll('JUDETUL', 'Județul');

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Setări',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: themeService.getBackgroundWidget(
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Secțiunea CONT
                _buildSectionTitle('Cont'),
                const SizedBox(height: 20),

                _buildInfoRow('Nume', name),
                _buildInfoRow('Tip cont', accountType),

                // Trial countdown ascuns - toți utilizatorii sunt PRO
                _buildInfoRow('Cod client', clientCode),
                _buildEditableRow(
                  'Telefon',
                  phone,
                  Icons.phone,
                  () => _changePhoneNumber(phone),
                ),
                _buildInfoRow('Adresă', formattedAddress),
                _buildEditableRow(
                  'Sistem automatizare',
                  displaySystemType,
                  Icons.settings_remote,
                  () => _changeAutomationSystem(systemType),
                ),
                _buildEditableRow(
                  'Dispozitiv',
                  device,
                  Icons.door_sliding,
                  () => _editDeviceName(device),
                ),

                const SizedBox(height: 40),

                // Secțiunea NOTIFICĂRI eliminată la cerere
                const SizedBox(height: 40),

                // Secțiunea COMENZI VOCALE mutată în Setări Notificări
                const SizedBox(height: 40),

                if (isClient && _isHopaModule) ...[
                  _buildSectionTitle('Împerechere HUB'),
                  const SizedBox(height: 20),
                  _buildHopaSecurityCard(),
                  const SizedBox(height: 16),
                  _buildHubPairingCard(),
                  const SizedBox(height: 16),
                  _buildInstalledModulesCard(),
                  const SizedBox(height: 16),
                  _buildRf433RemotesCard(),
                  const SizedBox(height: 16),
                  _buildHopaDevicesCard(),
                  const SizedBox(height: 40),
                ],

                // Secțiunea AJUTOR
                _buildSectionTitle('Ajutor'),
                const SizedBox(height: 20),

                // Buton Help - deschide ecran cu FAQ
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const HelpScreen(),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.deepPurple.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.help_outline,
                          color: Colors.deepPurple,
                          size: 28,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Întrebări Frecvente',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[800],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Ghid complet de utilizare',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          color: Colors.grey[400],
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 40),

                // Secțiunea DESPRE
                _buildSectionTitle('Despre'),
                const SizedBox(height: 20),

                _buildInfoRow('Versiune', '1.90'),
                _buildInfoRow('Dezvoltator', 'Casa Luminii Balasa S.R.L.'),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHopaSecurityCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.teal.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.security, color: Colors.teal),
              const SizedBox(width: 8),
              Text(
                'Securitate acțiuni sensibile',
                style: TextStyle(
                  color: Colors.grey[900],
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Alege când să ceară autentificare biometrică/PIN.',
            style: TextStyle(color: Colors.grey[700], fontSize: 13),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                selected: _protectionMode == SecurityService.modeAllSensitive,
                label: const Text('Toate acțiunile sensibile'),
                onSelected: (_) =>
                    _setProtectionMode(SecurityService.modeAllSensitive),
              ),
              ChoiceChip(
                selected: _protectionMode == SecurityService.modeDeleteOnly,
                label: const Text('Doar ștergere'),
                onSelected: (_) =>
                    _setProtectionMode(SecurityService.modeDeleteOnly),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Biometrie',
                  style: TextStyle(color: Colors.grey[800], fontSize: 14),
                ),
              ),
              Switch(
                value: _biometricEnabled,
                onChanged: _biometricSupported ? _toggleBiometric : null,
                activeThumbColor: Colors.teal,
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _securityBusy
                ? null
                : () async {
                    await _configurePin();
                  },
            icon: const Icon(Icons.pin, size: 18),
            label: Text(_hasSecurityPin ? 'Schimbă PIN' : 'Setează PIN'),
          ),
        ],
      ),
    );
  }

  Widget _buildHopaDevicesCard() {
    final tagDevices = _devicesByType('tag');
    final limitText = _hopaLimit > 0 ? '$_hopaLimit' : '-';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.key, color: Colors.deepPurple),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Taguri împerecheate',
                  style: TextStyle(
                    color: Colors.grey[900],
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadingHopaDevices ? null : _loadHopaDevices,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Taguri în listă: ${tagDevices.length}',
            style: TextStyle(color: Colors.grey[700], fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            'Sloturi TAG active: $_hopaTagCount / $limitText',
            style: TextStyle(
              color: _canEnrollMore ? Colors.grey[700] : Colors.red[700],
              fontSize: 12,
              fontWeight: _canEnrollMore ? FontWeight.w400 : FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Module active: $_hopaModuleCount • Total active: $_hopaTotalCount',
            style: TextStyle(color: Colors.grey[600], fontSize: 11),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_startingPairing || !_canEnrollMore)
                  ? null
                  : () => _startHopaPairing(target: 'tag'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
              icon: const Icon(Icons.add_link),
              label: const Text('Adaugă TAG'),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'După pairing, TAG-ul se adaugă automat în listă.',
            style: TextStyle(color: Colors.grey[700], fontSize: 12),
          ),
          if (!_canEnrollMore) ...[
            const SizedBox(height: 6),
            Text(
              'Limita este atinsă. Pentru un TAG nou, șterge mai întâi un TAG din listă.',
              style: TextStyle(
                color: Colors.red[700],
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (_loadingHopaDevices)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: CircularProgressIndicator(),
              ),
            )
          else if (tagDevices.isEmpty)
            Text(
              'Nu există încă taguri împerecheate.',
              style: TextStyle(color: Colors.grey[700]),
            )
          else
            ...tagDevices.map(_buildHopaDeviceTile),
        ],
      ),
    );
  }

  Widget _buildHubPairingCard() {
    final active = _hubPairingActive;
    final secondsLeft = _hubPairingSecondsLeft;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active
              ? Colors.green.withValues(alpha: 0.45)
              : Colors.teal.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                active ? Icons.hub : Icons.device_hub,
                color: active ? Colors.green : Colors.teal,
              ),
              const SizedBox(width: 8),
              Text(
                'Pairing HUB',
                style: TextStyle(
                  color: Colors.grey[900],
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: _startingPairing
                ? null
                : () => _startHopaPairing(target: 'module'),
            style: ElevatedButton.styleFrom(
              backgroundColor: active ? Colors.green : Colors.teal,
            ),
            icon: _startingPairing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(active ? Icons.check_circle : Icons.link),
            label: Text(
              active
                  ? 'Pairing HUB activ (${secondsLeft}s)'
                  : 'Start Pairing HUB',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Flow sigur: te apropii de poartă, apeși Start Pairing HUB și aplicația caută automat modulele.',
            style: TextStyle(color: Colors.grey[700], fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildInstalledModulesCard() {
    final switch1 = _deviceByTypeIndex('switch', 0);
    final switch2 = _deviceByTypeIndex('switch', 1);
    final camera = _deviceByTypeIndex('camera', 0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.indigo.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.settings_input_component, color: Colors.indigo),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Module instalate',
                  style: TextStyle(
                    color: Colors.grey[900],
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Verifică status',
                icon: const Icon(Icons.refresh),
                onPressed: _loadingHopaDevices
                    ? null
                    : () => _loadHopaDevices(showErrors: false),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _restartingHub ? null : _restartHubAndRefresh,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueGrey[700],
              ),
              icon: _restartingHub
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.restart_alt),
              label: const Text('Restart HUB + verifică module'),
            ),
          ),
          const SizedBox(height: 8),
          _buildModuleStatusTile(
            title: 'Switch 1',
            icon: Icons.sensors,
            device: switch1,
            pairingType: 'switch',
          ),
          const SizedBox(height: 8),
          _buildModuleStatusTile(
            title: 'Switch 2',
            icon: Icons.sensors_outlined,
            device: switch2,
            pairingType: 'switch',
          ),
          const SizedBox(height: 8),
          _buildModuleStatusTile(
            title: 'Cameră web',
            icon: Icons.videocam,
            device: camera,
            pairingType: 'camera',
          ),
          const SizedBox(height: 8),
          Text(
            'Statusul modulelor (switch/cameră) este vizibil în aplicație.',
            style: TextStyle(color: Colors.grey[700], fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildRf433RemotesCard() {
    final desiredLimitRaw = int.tryParse(_rf433LimitController.text.trim());
    final desiredLimit = desiredLimitRaw == null
        ? _rf433RemoteLimit
        : desiredLimitRaw.clamp(1, 9);
    final usedSlotsCurrent = _rf433UsedSlots();
    final freeSlotsAfterLimit = <int>[];
    for (int i = 0; i < desiredLimit; i++) {
      final used = (_rf433SlotMask & (1 << i)) != 0;
      if (!used) {
        freeSlotsAfterLimit.add(i + 1);
      }
    }
    final limitTooLow = desiredLimit < _rf433RemoteCount;
    final canPair = !limitTooLow && freeSlotsAfterLimit.isNotEmpty;
    final nextFreeSlot = canPair ? freeSlotsAfterLimit.first : null;
    final clearSlotOptions = usedSlotsCurrent;
    final int? safeClearValue = clearSlotOptions.contains(_rf433ClearSlot)
        ? _rf433ClearSlot
        : (clearSlotOptions.isNotEmpty ? clearSlotOptions.first : null);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.deepOrange.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.settings_remote, color: Colors.deepOrange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Telecomenzi RF433',
                  style: TextStyle(
                    color: Colors.grey[900],
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Refresh status RF433',
                icon: const Icon(Icons.refresh),
                onPressed: (_rf433Busy || _loadingRf433Status)
                    ? null
                    : () => _refreshRf433Status(showErrors: true),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Actual: $_rf433RemoteCount / $_rf433RemoteLimit • Libere acum: $_rf433RemoteFree',
            style: TextStyle(
              color: limitTooLow ? Colors.red[700] : Colors.grey[700],
              fontSize: 12,
              fontWeight: limitTooLow ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'După limita nouă ($desiredLimit) sloturi libere: ${limitTooLow ? 0 : freeSlotsAfterLimit.length}',
            style: TextStyle(
              color: limitTooLow ? Colors.red[700] : Colors.grey[700],
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Flexible(
                flex: 2,
                child: TextField(
                  controller: _rf433LimitController,
                  keyboardType: TextInputType.number,
                  enabled: !_rf433Busy,
                  decoration: const InputDecoration(
                    labelText: 'Limită telecomenzi (1-9)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: ElevatedButton(
                  onPressed: _rf433Busy ? null : _setRf433LimitOnly,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey[700],
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Setează limită'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Limită = câte telecomenzi maxime permiți.',
            style: TextStyle(color: Colors.grey[700], fontSize: 12),
          ),
          if (limitTooLow) ...[
            const SizedBox(height: 8),
            Text(
              'Limita nouă nu poate fi mai mică decât numărul deja împerecheat ($_rf433RemoteCount).',
              style: TextStyle(
                color: Colors.red[700],
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_rf433Busy || !canPair) ? null : _startRf433Pairing,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
              ),
              icon: _rf433Busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.link),
              label: const Text('Împerechează telecomandă nouă'),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            nextFreeSlot != null
                ? 'La pairing se ocupă automat slotul $nextFreeSlot (primul liber).'
                : 'Nu ai slot liber. Mărește limita sau șterge un slot.',
            style: TextStyle(
              color: nextFreeSlot != null ? Colors.grey[700] : Colors.red[700],
              fontSize: 12,
              fontWeight: nextFreeSlot != null
                  ? FontWeight.w400
                  : FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: safeClearValue,
                  decoration: const InputDecoration(
                    labelText: 'Slot de șters',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: clearSlotOptions
                      .map(
                        (slot) => DropdownMenuItem<int>(
                          value: slot,
                          child: Text('Slot $slot'),
                        ),
                      )
                      .toList(),
                  onChanged: (_rf433Busy || clearSlotOptions.isEmpty)
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() => _rf433ClearSlot = value);
                        },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: (_rf433Busy || safeClearValue == null)
                      ? null
                      : () => _clearRf433Pairing(
                          slot: _rf433ClearSlot > 0
                              ? _rf433ClearSlot
                              : safeClearValue,
                        ),
                  icon: const Icon(Icons.link_off, size: 16),
                  label: const Text('Șterge slot'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _rf433Busy
                  ? null
                  : () => _clearRf433Pairing(slot: null),
              icon: const Icon(Icons.delete_forever, size: 16),
              label: const Text('Șterge toate telecomenzile'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Pași: 1) Setezi limită, 2) Împerechezi telecomanda nouă, 3) dacă vrei scoți slotul X.',
            style: TextStyle(color: Colors.grey[700], fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            'Pairing-ul RF433 pornește doar la comandă din aplicație (nu mai învață automat).',
            style: TextStyle(color: Colors.grey[700], fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildModuleStatusTile({
    required String title,
    required IconData icon,
    required Map<String, dynamic>? device,
    required String pairingType,
  }) {
    final paired = device != null;
    final online =
        paired &&
        (_toBool(device['is_online_live']) ||
            _toBool(device['is_recently_detected']));
    final searching = _hubPairingActive && !paired;
    final failed = !_hubPairingActive && _pairingAttempted && !paired;

    Color statusColor;
    String statusText;
    Widget statusIcon;

    if (searching) {
      statusColor = Colors.orange[700]!;
      statusText = 'Caut dispozitiv...';
      statusIcon = const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (paired && online) {
      statusColor = Colors.green[700]!;
      statusText = 'Împerecheat • Online';
      statusIcon = Icon(Icons.check_circle, size: 17, color: statusColor);
    } else if (paired && !online) {
      statusColor = Colors.red[700]!;
      statusText = 'Împerecheat • Offline';
      statusIcon = Icon(
        Icons.fiber_manual_record,
        size: 14,
        color: statusColor,
      );
    } else if (failed) {
      statusColor = Colors.red[700]!;
      statusText = 'Eroare: nu s-a împerecheat';
      statusIcon = Icon(Icons.error, size: 17, color: statusColor);
    } else {
      statusColor = Colors.orange[700]!;
      statusText = 'Neîmperecheat';
      statusIcon = Icon(
        Icons.remove_circle_outline,
        size: 17,
        color: statusColor,
      );
    }

    final mac = (device?['mac_address'] ?? '-').toString();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: statusColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Colors.blueGrey[800]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              statusIcon,
              const SizedBox(width: 6),
              Text(
                statusText,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'MAC: $mac',
            style: TextStyle(
              color: Colors.grey[700],
              fontFamily: 'monospace',
              fontSize: 11,
            ),
          ),
          if (device != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loadingHopaDevices
                        ? null
                        : () => _loadHopaDevices(showErrors: false),
                    icon: const Icon(Icons.wifi_tethering, size: 16),
                    label: const Text('Verifică'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _removeHopaDevice(device),
                    icon: const Icon(Icons.link_off, size: 16),
                    label: const Text('Elimină'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: (_startingPairing || _hubPairingActive)
                    ? null
                    : () => _startHopaPairing(
                        target: 'module',
                        deviceType: pairingType,
                      ),
                icon: const Icon(Icons.link, size: 16),
                label: Text('Împerechează ${_deviceTypeLabel(pairingType)}'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _normalizeDeviceType(dynamic value, String name) {
    final raw = (value ?? '').toString().trim().toLowerCase();
    if (raw == 'tag' || raw == 'camera' || raw == 'switch') {
      return raw;
    }

    final loweredName = name.toLowerCase();
    if (loweredName.contains('camera')) return 'camera';
    if (loweredName.contains('switch')) return 'switch';
    return 'tag';
  }

  String _deviceTypeLabel(String type) {
    switch (type) {
      case 'camera':
        return 'CAMERA';
      case 'switch':
        return 'SWITCH';
      default:
        return 'TAG';
    }
  }

  Widget _buildHopaDeviceTile(Map<String, dynamic> device) {
    final active = device['is_active'] == true;
    final name = (device['device_name'] ?? 'HOPA Device').toString();
    final mac = (device['mac_address'] ?? '-').toString();
    final deviceType = _normalizeDeviceType(device['device_type'], name);
    final deviceTypeText = _deviceTypeLabel(deviceType);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: active
              ? Colors.green.withValues(alpha: 0.5)
              : Colors.orange.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                active ? Icons.check_circle : Icons.block,
                color: active ? Colors.green : Colors.orange,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  deviceTypeText,
                  style: TextStyle(
                    color: Colors.blueGrey[800],
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                active ? 'ACTIV' : 'BLOCAT',
                style: TextStyle(
                  color: active ? Colors.green[700] : Colors.orange[800],
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            mac,
            style: TextStyle(
              color: Colors.grey[700],
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 460;

              final tipButton = OutlinedButton.icon(
                onPressed: () => _changeHopaDeviceType(device),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
                icon: const Icon(Icons.tune, size: 16),
                label: const Text(
                  'Tip dispozitiv',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );

              final lockButton = OutlinedButton.icon(
                onPressed: () => _toggleHopaDeviceActive(device),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
                icon: Icon(active ? Icons.lock : Icons.lock_open, size: 16),
                label: Text(
                  active ? 'Blochează TAG' : 'Deblochează TAG',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );

              final removeButton = ElevatedButton.icon(
                onPressed: () => _removeHopaDevice(device),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  minimumSize: const Size.fromHeight(44),
                ),
                icon: const Icon(Icons.delete, size: 16),
                label: const Text(
                  'Șterge TAG',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );

              if (compact) {
                return Column(
                  children: [
                    SizedBox(width: double.infinity, child: tipButton),
                    const SizedBox(height: 8),
                    SizedBox(width: double.infinity, child: lockButton),
                    const SizedBox(height: 8),
                    SizedBox(width: double.infinity, child: removeButton),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: tipButton),
                  const SizedBox(width: 8),
                  Expanded(child: lockButton),
                  const SizedBox(width: 8),
                  Expanded(child: removeButton),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: Colors.grey[600],
        fontSize: 14,
        fontWeight: FontWeight.bold,
        letterSpacing: 1,
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[500], fontSize: 16),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableRow(
    String label,
    String value,
    IconData icon,
    VoidCallback onTap,
  ) {
    final isSystemRequired =
        label == 'Sistem automatizare' &&
        (value.contains('OBLIGATORIU') || value == '-');

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: isSystemRequired
            ? BoxDecoration(
                border: Border.all(color: Colors.orange, width: 2),
                borderRadius: BorderRadius.circular(8),
                color: Colors.orange.withValues(alpha: 0.1),
              )
            : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  if (isSystemRequired) ...[
                    Icon(Icons.warning, color: Colors.orange, size: 16),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: isSystemRequired
                            ? Colors.orange
                            : Colors.grey[500],
                        fontSize: 16,
                        fontWeight: isSystemRequired
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      value,
                      style: TextStyle(
                        color: isSystemRequired ? Colors.orange : Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.edit,
                    color: isSystemRequired ? Colors.orange : Colors.teal,
                    size: 18,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // _buildSwitchRow păstrat pentru viitor - dezactivat momentan
  // Widget _buildSwitchRow(String label, bool value, Function(bool) onChanged) {
  //   return Padding(
  //     padding: const EdgeInsets.symmetric(vertical: 12),
  //     child: Row(
  //       crossAxisAlignment: CrossAxisAlignment.start,
  //       children: [
  //         Expanded(
  //           flex: 2,
  //           child: Text(
  //             label,
  //             style: TextStyle(
  //               color: Colors.grey[500],
  //               fontSize: 16,
  //             ),
  //           ),
  //         ),
  //         Expanded(
  //           flex: 3,
  //           child: Switch(
  //             value: value,
  //             onChanged: onChanged,
  //             activeThumbColor: Colors.teal,
  //           ),
  //         ),
  //       ],
  //     ),
  //   );
  // }

  Widget _buildUpgradeToProCard() {
    // Toți utilizatorii sunt afișați ca PRO - trial-ul rămâne în cod dar nu se afișează
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.purple.shade800, Colors.purple.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.star, color: Colors.amber, size: 28),
              const SizedBox(width: 10),
              Text(
                'HOPA PRO Activ',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Beneficiile tale PRO active:',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          _buildProFeature('🎨', 'Tema PRO'),
          _buildProFeature('📡', 'Detectare HOPA automată'),
          _buildProFeature('🚪', 'Control complet poartă'),
          _buildProFeature('🔔', 'Notificări avansate'),
          _buildProFeature('📊', 'Statistici detaliate'),
        ],
      ),
    );
  }

  Widget _buildProFeature(String icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(icon, style: TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Text(
            text,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // _startProTrial păstrat pentru viitor - dezactivat momentan
  // Future<void> _startProTrial() async {
  //   final authService = Provider.of<AuthService>(context, listen: false);
  //   if (!mounted) return;
  //   ScaffoldMessenger.of(context).showSnackBar(
  //     SnackBar(
  //       content: const Text('Se activează trial-ul PRO...'),
  //       backgroundColor: Colors.blueGrey,
  //       duration: const Duration(seconds: 2),
  //     ),
  //   );
  //   try {
  //     await authService.startProTrial();
  //     if (authService.isPro) {
  //       final themeService = Provider.of<ThemeService>(context, listen: false);
  //       await themeService.setTheme(AppTheme.current);
  //     }
  //     if (!mounted) return;
  //     setState(() {});
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(
  //         content: const Text('Trial PRO activat pentru 15 zile!'),
  //         backgroundColor: Colors.green,
  //       ),
  //     );
  //   } catch (e) {
  //     if (!mounted) return;
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(
  //         content: Text('Eroare activare PRO: $e'),
  //         backgroundColor: Colors.red,
  //       ),
  //     );
  //   }
  // }
}
