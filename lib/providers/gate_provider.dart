import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../services/api_service.dart';

class GateProvider extends ChangeNotifier {
  String _state = 'closed';
  bool _sensorActive = false;
  bool _isPolling = false; // previne cereri paralele
  bool _isInitialized = false; // indicator că am primit prima stare reală
  
  // Cache pentru API responses (optimizare)
  DateTime? _lastApiCall;
  static const _apiCacheDuration = Duration(milliseconds: 500); // 500ms cache

  String get state => _state;
  bool get sensorActive => _sensorActive;
  bool get isInitialized => _isInitialized; // expune pentru UI
  bool get isOpen => _state == 'open' || _state == 'opening';
  
  // Metodă pentru toggle local instant (pentru click rapid)
  void toggleLocalState() {
    if (_state == 'open' || _state == 'opening') {
      _state = 'closed';
    } else {
      _state = 'open';
    }
    notifyListeners();
  }

  GateProvider() {
    _listenToFcm();
    _startPolling();
    // Fetch inițial IMEDIAT pentru a evita primul click în gol
    _initializeState();
  }
  
  Future<void> _initializeState() async {
    try {
      // Încearcă să preia starea imediat
      await refresh();
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      print('[GateProvider] Eroare la inițializare: $e');
      // NU setăm _isInitialized=true dacă a eșuat!
      // Reîncearcă după 2 secunde
      Future.delayed(const Duration(seconds: 2), () async {
        try {
          await refresh();
          _isInitialized = true;
          notifyListeners();
        } catch (_) {
          print('[GateProvider] A doua încercare eșuată - rămâne neinițializat');
          // NU setăm true - lasă UI să trimită toggle la primul click
        }
      });
    }
  }

  void _listenToFcm() {
    FirebaseMessaging.onMessage.listen((message) {
      final data = message.data;
      print('[GateProvider] FCM received: ${data}');
      
      // Actualizează instant pentru orice tip de notificare gate
      if (data['type'] == 'gate_action' || data['type'] == 'gate_status') {
        // Pentru gate_action, derivăm starea din action
        if (data['action'] == 'opened') {
          _state = 'open';
          _sensorActive = false;
          print('[GateProvider] FCM: Gate OPENED');
          notifyListeners();
        } else if (data['action'] == 'closed') {
          _state = 'closed';
          _sensorActive = false;
          print('[GateProvider] FCM: Gate CLOSED');
          notifyListeners();
        } else if (data['state'] != null) {
          // Pentru gate_status folosim state direct
          _state = data['state'];
          _sensorActive = data['sensor_active'] == 'true';
          print('[GateProvider] FCM: State updated to ${_state}');
          notifyListeners();
        }
      }
    });
  }

  void _startPolling() {
    Timer.periodic(const Duration(milliseconds: 1500), (_) async {
      if (_isPolling) return; // evită suprapunerea
      _isPolling = true;
      try {
        final res = await ApiService.getGateStatus();
        final newState = res['state'];
        final newSensor = res['sensor_active'] ?? false;
        if (newState != null) {
          if (newState != _state || newSensor != _sensorActive) {
            print('[GateProvider] Polling: state=$newState, sensor=$newSensor');
            _state = newState;
            _sensorActive = newSensor;
            notifyListeners();
          }
        }
      } catch (e) {
        // Ignoră erorile - polling continuu
      } finally {
        _isPolling = false;
      }
    });
  }

  // Poate fi folosit de UI pentru a actualiza manual
  Future<void> refresh() async {
    // Cache pentru a preveni prea multe apeluri API (optimizare)
    final now = DateTime.now();
    if (_lastApiCall != null && 
        now.difference(_lastApiCall!) < _apiCacheDuration) {
      print('📦 Cache API gate status - apelat acum ${now.difference(_lastApiCall!).inMilliseconds}ms');
      return;
    }
    
    try {
      final res = await ApiService.getGateStatus();
      _lastApiCall = now;
      
      final newState = res['state'];
      _sensorActive = res['sensor_active'] ?? _sensorActive;
      if (newState != null) {
        if (newState != _state) {
          _state = newState;
          notifyListeners();
        }
        if (!_isInitialized) {
          _isInitialized = true;
          notifyListeners();
        }
      }
    } catch (_) {}
  }

  void set(String state, bool sensor) {
    _state = state;
    _sensorActive = sensor;
    notifyListeners();
  }
} 