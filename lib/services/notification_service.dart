import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class NotificationService extends ChangeNotifier {
  bool _familyNotifications = true;      // gate_actions
  bool _technicalProblems = true;        // sos_alerts
  bool _serviceRequired = false;         // general
  bool _voiceCommands = true;
  bool _pushNotifications = true;        // master
  bool _marketingNotifications = true;   // marketing
  
  // Getters
  bool get familyNotifications => _familyNotifications;
  bool get technicalProblems => _technicalProblems;
  bool get serviceRequired => _serviceRequired;
  bool get voiceCommands => _voiceCommands;
  bool get pushNotifications => _pushNotifications;
  bool get marketingNotifications => _marketingNotifications;
  
  NotificationService() {
    _loadNotificationSettings();
  }
  
  // Încarcă setările salvate
  Future<void> _loadNotificationSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _familyNotifications = prefs.getBool('family_notifications') ?? true;
    _technicalProblems = prefs.getBool('technical_problems') ?? true;
    _serviceRequired = prefs.getBool('service_required') ?? false;
    _voiceCommands = prefs.getBool('voice_commands') ?? true;
    _pushNotifications = prefs.getBool('push_notifications') ?? true;
    _marketingNotifications = prefs.getBool('marketing_notifications') ?? true;
    notifyListeners();
  }
  
  // Actualizează setările notificărilor familie
  Future<void> setFamilyNotifications(bool value) async {
    _familyNotifications = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('family_notifications', value);
    try {
      await ApiService.updateNotificationSettings({
        'push_notifications_enabled': _pushNotifications,
        'gate_actions': value,
      });
    } catch (_) {}
    notifyListeners();
  }
  
  // Actualizează setările pentru probleme tehnice
  Future<void> setTechnicalProblems(bool value) async {
    _technicalProblems = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('technical_problems', value);
    try {
      await ApiService.updateNotificationSettings({
        'push_notifications_enabled': _pushNotifications,
        'sos_alerts': value,
      });
    } catch (_) {}
    notifyListeners();
  }
  
  // Actualizează setările pentru service necesar
  Future<void> setServiceRequired(bool value) async {
    _serviceRequired = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('service_required', value);
    try {
      await ApiService.updateNotificationSettings({
        'push_notifications_enabled': _pushNotifications,
        'general': value,
      });
    } catch (_) {}
    notifyListeners();
  }
  
  // Actualizează setările pentru comenzi vocale
  Future<void> setVoiceCommands(bool value) async {
    _voiceCommands = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voice_commands', value);
    notifyListeners();
    
    print('Voice commands ${value ? 'enabled' : 'disabled'}');
  }

  Future<void> setPushNotifications(bool value) async {
    _pushNotifications = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('push_notifications', value);
    try {
      await ApiService.updateNotificationSettings({
        'push_notifications_enabled': value,
        'gate_actions': value ? _familyNotifications : false,
        'sos_alerts': value ? _technicalProblems : false,
        'general': value ? _serviceRequired : false,
        'marketing_notifications': value ? _marketingNotifications : false,
      });
    } catch (_) {}
    notifyListeners();
  }

  Future<void> setMarketingNotifications(bool value) async {
    _marketingNotifications = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('marketing_notifications', value);
    try {
      await ApiService.updateNotificationSettings({
        'push_notifications_enabled': _pushNotifications,
        'marketing_notifications': value,
      });
    } catch (_) {}
    notifyListeners();
  }
  
  // Resetează toate setările la valori implicite
  Future<void> resetToDefaults() async {
    _familyNotifications = true;
    _technicalProblems = true;
    _serviceRequired = false;
    _voiceCommands = true;
    _pushNotifications = true;
    _marketingNotifications = true;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('family_notifications', _familyNotifications);
    await prefs.setBool('technical_problems', _technicalProblems);
    await prefs.setBool('service_required', _serviceRequired);
    await prefs.setBool('voice_commands', _voiceCommands);
    await prefs.setBool('push_notifications', _pushNotifications);
    await prefs.setBool('marketing_notifications', _marketingNotifications);
    
    notifyListeners();
  }
} 