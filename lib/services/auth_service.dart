import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
// import 'shelly_cloud_service.dart'; - ELIMINAT, nu mai folosim cloud Shelly
import 'package:firebase_messaging/firebase_messaging.dart';

class AuthService extends ChangeNotifier {
  bool _isAuthenticated = false;
  Map<String, dynamic>? _userData;
  String? _userRole; // 'client' sau 'installer'
  
  bool get isAuthenticated => _isAuthenticated;
  Map<String, dynamic>? get userData => _userData;
  String? get token => _userData?['token'];
  String? get userRole => _userRole;
  bool get isInstaller => _userRole == 'installer';
  bool get isClient => _userRole == 'client';
  
  AuthService() {
    _checkAuthStatus();
  }
  
  Future<void> _checkAuthStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final role = prefs.getString('user_role') ?? 'client';
    final userName = prefs.getString('user_name');
    final userPhone = prefs.getString('user_phone');
    final userAddress = prefs.getString('user_address');
    final activationCode = prefs.getString('activation_code');
    final accountType = prefs.getString('account_type') ?? 'Standard';
    final clientId = prefs.getInt('client_id');
    final installerId = prefs.getInt('installer_id');
    final systemType = prefs.getString('system_type');
    
    // ✅ RESTAUREAZĂ datele instalatorului
    final installerCompany = prefs.getString('installer_company');
    final canCreateSubInstallers = prefs.getBool('can_create_sub_installers') ?? false;
    final parentInstallerId = prefs.getInt('parent_installer_id') ?? 0;
    final deviceName = prefs.getString('device_name');
    final trialStarted = prefs.getString('trial_started');
    final trialExpires = prefs.getString('trial_expires');
    
    if (token != null) {
      _isAuthenticated = true;
      _userRole = role;
      _userData = {
        'name': (userName ?? (role == 'installer' ? 'Instalator' : 'Client')).toUpperCase(),
        'account_type': accountType,
        'activation_code': activationCode ?? '',
        'phone': userPhone ?? 'N/A',
        'address': (userAddress ?? 'N/A').toUpperCase(),
        'system_type': (systemType?.isEmpty == true || systemType == '-') ? '' : (systemType ?? ''),
        'device': deviceName ?? 'Poartă Principală',
        'token': token,
        'client_id': clientId,
        'installer_id': installerId,
        'role': role,
      };
      
      // ✅ RESTAUREAZĂ datele instalatorului dacă există
      if (role == 'installer' && installerCompany != null) {
        _userData!['can_create_sub_installers'] = canCreateSubInstallers;
        _userData!['installer'] = {
          'company_name': installerCompany,
          'parent_installer_id': parentInstallerId > 0 ? parentInstallerId : null,
        };
      }
      
      // Adaugă datele de trial dacă există
      if (trialStarted != null) _userData!['trial_started'] = trialStarted;
      if (trialExpires != null) _userData!['trial_expires'] = trialExpires;
      
      // Verifică dacă trial-ul a expirat (doar pentru clienți)
      if (role == 'client') {
        await checkTrialExpiry();
      }
      
      notifyListeners();
    }
  }
  
  Future<bool> loginWithCode(String code) async {
    try {
      // Apelează API-ul real pentru autentificare cu codul de activare
      // Încearcă mai întâi login client, apoi installer
      var response = await ApiService.loginWithCode(code.toUpperCase());

      // Dacă nu merge ca client, încearcă ca installer
      if (response['success'] != true) {
        response = await ApiService.loginInstallerWithCode(code.toUpperCase());
      }

      if (response['success'] == true) {
        _isAuthenticated = true;

        // Extrage datele utilizatorului din răspuns
        final user = response['user'] ?? {};
        final role = user['role'] ?? 'client';
        _userRole = role;

        _userData = {
          'name': (user['name'] ?? (role == 'installer' ? 'Instalator' : 'Client')).toUpperCase(),
          'account_type': user['account_type'] ?? 'Standard',
          'activation_code': user['activation_code'] ?? code.toUpperCase(),
          'phone': user['phone'] ?? '',
          'address': (user['address'] ?? '').toUpperCase(),
          'system_type': (user['system_type']?.isEmpty == true || user['system_type'] == '-') ? '' : (user['system_type'] ?? ''),
          'device': user['device'] ?? 'Poartă Principală',
          'token': response['token'],
          'client_id': user['client_id'],
          'installer_id': user['installer_id'],
          'id': user['id'],
          'role': role,
          'company_name': user['company_name'], // Pentru instalatori
          'is_parent': user['is_parent'] ?? false, // Dacă e instalator principal
          'can_create_sub_installers': user['can_create_sub_installers'] ?? false,
          // Adaugă informații despre installer pentru tehnicieni
          'installer': user['installer'],
        };

        // Salvează detalii minime în SharedPreferences pentru sesiuni viitoare
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', response['token']);
        await prefs.setString('user_role', role);
        await prefs.setString('user_name', _userData!['name']);
        await prefs.setString('user_phone', _userData!['phone']);
        await prefs.setString('user_address', _userData!['address']);
        await prefs.setString('activation_code', _userData!['activation_code']);
        await prefs.setString('account_type', _userData!['account_type']);
        await prefs.setString('system_type', _userData!['system_type']);
        await prefs.setString('device_name', _userData!['device']);
        await prefs.setInt('client_id', user['client_id'] ?? 0);
        await prefs.setInt('installer_id', user['installer_id'] ?? 0);
        
        // ✅ SALVEAZĂ și datele instalatorului pentru persistență
        if (role == 'installer' && _userData!['installer'] != null) {
          await prefs.setString('installer_company', _userData!['installer']['company_name'] ?? '');
          await prefs.setBool('can_create_sub_installers', _userData!['can_create_sub_installers'] ?? false);
          await prefs.setInt('parent_installer_id', _userData!['installer']['parent_installer_id'] ?? 0);
        }

        // Inițializează serviciul de device specific dacă există credențiale (doar pentru clienți)
        if (role == 'client' && response.containsKey('device')) {
          final deviceCredentials = response['device'] as Map<String, dynamic>;

          // Persistă tipul dispozitivului imediat
          final deviceType = (deviceCredentials['device_type'] ?? 'esp32').toString();
          await prefs.setString('device_type', deviceType);

          // Persistă explicit ID-ul Shelly pentru fluxul EMQX, independent de serviciul Cloud
          if (deviceType == 'shelly') {
            // SALVĂM CODUL HOPA (71BDA...) pentru control MQTT
            final hopaCode = (deviceCredentials['hopa_device_code'] ?? '').toString();
            debugPrint('🔍 DEBUG AuthService - hopa_device_code din backend: $hopaCode');
            if (hopaCode.isNotEmpty) {
              await prefs.setString('hopa_device_code', hopaCode);
              debugPrint('✅ HOPA device code salvat: $hopaCode');
            }
            
            // Salvăm și shelly_device_id dacă există (opțional)
            final shellyId = (deviceCredentials['shelly_device_id'] ?? '').toString();
            if (shellyId.isNotEmpty) {
              await prefs.setString('shelly_device_id', shellyId);
              debugPrint('✅ Shelly device ID salvat: $shellyId');
            }
          }
        }

        // Trimite FCM token către backend după login
        await _sendFcmToken();

        notifyListeners();
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('Login error: $e');
      return false;
    }
  }
  
  Future<void> updateSystemType(String systemType) async {
    if (_userData != null) {
      // Validează că sistemul nu e gol sau "-"
      final validSystem = (systemType.isEmpty || systemType == '-') ? 'BFT' : systemType;
      
      _userData!['system_type'] = validSystem;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('system_type', validSystem);
      notifyListeners();
      
      debugPrint('System type updated to: $validSystem');
    }
  }

  Future<void> updateDeviceName(String deviceName) async {
    if (_userData != null) {
      _userData!['device'] = deviceName;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('device_name', deviceName);
      notifyListeners();
    }
  }

  Future<void> updatePhoneNumber(String phoneNumber) async {
    if (_userData != null) {
      _userData!['phone'] = phoneNumber;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_phone', phoneNumber);
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _isAuthenticated = false;
    _userData = null;
    _userRole = null;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    
    notifyListeners();
  }

  // Activează trial PRO prin backend (înlocuiește sistemul local)
  Future<void> startProTrial() async {
    try {
      final response = await ApiService.activateProTrialBackend();
      
      if (response['success'] == true) {
        // Marchează LOCAL imediat PRO_TRIAL pentru a evita a doua apăsare
        if (_userData != null) {
          final now = DateTime.now();
          final expiryDate = now.add(const Duration(days: 15));
          _userData!['account_type'] = 'PRO_TRIAL';
          _userData!['trial_started'] = now.toIso8601String();
          _userData!['trial_expires'] = expiryDate.toIso8601String();
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('account_type', 'PRO_TRIAL');
          await prefs.setString('trial_started', now.toIso8601String());
          await prefs.setString('trial_expires', expiryDate.toIso8601String());
          notifyListeners();
        }
        
        // Actualizează statusul local cu datele de la backend
        await syncSubscriptionStatus();
        
        // Trimite sau reîmprospătează token-ul imediat după activarea trial-ului
        await _sendFcmToken();

        debugPrint('🌟 PRO Trial activat prin backend!');
      } else {
        throw Exception(response['message'] ?? 'Eroare necunoscută');
      }
    } catch (e) {
      debugPrint('❌ Eroare la activarea trial PRO: $e');
      
      // Fallback: activează local dacă backend-ul nu răspunde
      await _activateTrialLocal();
    }
  }
  
  // Activare trial locală (fallback)
  Future<void> _activateTrialLocal() async {
    if (_userData != null) {
      final now = DateTime.now();
      final expiryDate = now.add(Duration(days: 15)); // Trial 15 zile
      
      _userData!['account_type'] = 'PRO_TRIAL';
      _userData!['trial_started'] = now.toIso8601String();
      _userData!['trial_expires'] = expiryDate.toIso8601String();
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('account_type', 'PRO_TRIAL');
      await prefs.setString('trial_started', now.toIso8601String());
      await prefs.setString('trial_expires', expiryDate.toIso8601String());
      
      // Trimite/actualizează token-ul și local
      await _sendFcmToken();

      notifyListeners();
      
      debugPrint('🌟 PRO Trial activat local pentru 15 zile până la: ${expiryDate.toString()}');
    }
  }
  
  // Verifică dacă trial-ul PRO este activ
  bool get isProTrialActive {
    if (_userData == null) return false;
    
    final accountType = _userData!['account_type'];
    if (accountType != 'PRO_TRIAL') return false;
    
    final expiryString = _userData!['trial_expires'];
    if (expiryString == null) return false;
    
    final expiryDate = DateTime.parse(expiryString);
    return DateTime.now().isBefore(expiryDate);
  }
  
  // Obține zilele rămase în trial (backend preferred, fallback local)
  int get trialDaysRemaining {
    if (!isProTrialActive) return 0;
    
    // Folosește datele de la backend dacă sunt disponibile
    final backendDays = _userData!['trial_days_remaining'];
    if (backendDays != null && backendDays is int) {
      return backendDays;
    }
    
    // Fallback: calculează local
    final expiryString = _userData!['trial_expires'];
    if (expiryString == null) return 0;
    
    try {
      final expiryDate = DateTime.parse(expiryString);
      final now = DateTime.now();
      final difference = expiryDate.difference(now);
      
      return difference.inDays;
    } catch (e) {
      return 0;
    }
  }
  
  // Toți utilizatorii sunt PRO permanent
  bool get isPro {
    return true;
  }
  
  // Verifică dacă trial-ul expiră în curând
  bool get isTrialExpiringSoon {
    if (!isProTrialActive) return false;
    return trialDaysRemaining <= 3;
  }
  
  // Expiră trial-ul și revine la Standard
  Future<void> expireProTrial() async {
    if (_userData != null) {
      _userData!['account_type'] = 'Standard';
      _userData!.remove('trial_started');
      _userData!.remove('trial_expires');
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('account_type', 'Standard');
      await prefs.remove('trial_started');
      await prefs.remove('trial_expires');
      
      notifyListeners();
      
      debugPrint('🔚 PRO Trial expirat - revenit la Standard');
    }
  }
  
  // Sincronizează status abonament cu backend
  Future<void> syncSubscriptionStatus() async {
    try {
      final data = await ApiService.getSubscriptionStatus();
      if (data['success'] == true) {
        final sub = data['data'] ?? {};

        _userData ??= {};
        _userData!['account_type'] = sub['account_type'];
        _userData!['subscription_status'] = sub['subscription_status'];
        if (sub['expires_at'] != null) {
          _userData!['trial_expires'] = sub['expires_at'];
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('account_type', sub['account_type'] ?? 'Standard');
        if (sub['expires_at'] != null) {
          await prefs.setString('trial_expires', sub['expires_at']);
        }
        notifyListeners();
      }
    } catch (_) {}
  }

  // Verifică la fiecare deschidere app dacă trial-ul a expirat
  Future<void> checkTrialExpiry() async {
    if (_userData == null) return;
    
    // Încearcă să sincronizeze cu backend-ul întâi
    await syncSubscriptionStatus();
    
    // Verifică local doar dacă backend-ul nu e disponibil
    final accountType = _userData!['account_type'];
    if (accountType == 'PRO_TRIAL' && !isProTrialActive) {
      await expireProTrial();
    }
  }

  // Activează PRO permanent (după plată)
  Future<void> activateProPermanent() async {
    if (_userData != null) {
      _userData!['account_type'] = 'PRO';
      _userData!.remove('trial_started');
      _userData!.remove('trial_expires');
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('account_type', 'PRO');
      await prefs.remove('trial_started');
      await prefs.remove('trial_expires');
      
      notifyListeners();
    }
  }

  Future<void> _sendFcmToken() async {
    try {
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null) {
        await ApiService.updateFcmToken(fcmToken);
        debugPrint('FCM Token trimis către backend: $fcmToken');
      }
    } catch (e) {
      debugPrint('Eroare la trimiterea FCM token: $e');
    }
  }
}
