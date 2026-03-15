import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecurityService {
  static const _storage = FlutterSecureStorage();
  static const _pinKey = 'hopa_security_pin';
  static const _biometricEnabledKey = 'hopa_biometric_enabled';
  static const _protectionModeKey = 'hopa_sensitive_protection_mode';
  static const String modeAllSensitive = 'all_sensitive';
  static const String modeDeleteOnly = 'delete_only';
  static final LocalAuthentication _localAuth = LocalAuthentication();

  static Future<bool> hasPin() async {
    final pin = await _storage.read(key: _pinKey);
    return pin != null && pin.isNotEmpty;
  }

  static Future<void> savePin(String pin) async {
    await _storage.write(key: _pinKey, value: pin);
  }

  static Future<void> clearPin() async {
    await _storage.delete(key: _pinKey);
  }

  static Future<bool> verifyPin(String pin) async {
    final stored = await _storage.read(key: _pinKey);
    return stored != null && stored == pin;
  }

  static Future<bool> isBiometricAvailable() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      return canCheck || isSupported;
    } catch (e) {
      debugPrint('Biometric availability error: $e');
      return false;
    }
  }

  static Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_biometricEnabledKey) ?? false;
  }

  static Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricEnabledKey, enabled);
  }

  static Future<String> getProtectionMode() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString(_protectionModeKey) ?? modeAllSensitive;
    if (mode != modeAllSensitive && mode != modeDeleteOnly) {
      return modeAllSensitive;
    }
    return mode;
  }

  static Future<void> setProtectionMode(String mode) async {
    final normalized = (mode == modeDeleteOnly)
        ? modeDeleteOnly
        : modeAllSensitive;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_protectionModeKey, normalized);
  }

  static Future<bool> authenticateWithBiometrics(String reason) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (e) {
      debugPrint('Biometric auth error: $e');
      return false;
    }
  }
}
