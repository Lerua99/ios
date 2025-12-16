import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

class DeviceUtils {
  static String? _cachedDeviceModel;
  
  /// Obține modelul telefonului (ex: "Samsung S22 Ultra", "Samsung A53")
  static Future<String> getDeviceModel() async {
    if (_cachedDeviceModel != null) {
      return _cachedDeviceModel!;
    }
    
    try {
      final deviceInfo = DeviceInfoPlugin();
      
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        final model = androidInfo.model; // ex: "SM-S908B"
        final manufacturer = androidInfo.manufacturer; // ex: "Samsung"
        
        // Mapare modele Samsung la nume friendly
        final samsungModels = {
          'SM-S908B': 'Samsung S22 Ultra',
          'SM-S901B': 'Samsung S22',
          'SM-A536B': 'Samsung A53',
          'SM-A546B': 'Samsung A54',
          'SM-S911B': 'Samsung S23',
          'SM-S918B': 'Samsung S23 Ultra',
          'SM-S921B': 'Samsung S24',
          'SM-S928B': 'Samsung S24 Ultra',
        };
        
        _cachedDeviceModel = samsungModels[model] ?? '$manufacturer $model';
        return _cachedDeviceModel!;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        _cachedDeviceModel = '${iosInfo.name} ${iosInfo.model}';
        return _cachedDeviceModel!;
      }
    } catch (e) {
      print('Eroare la obținerea device info: $e');
    }
    
    _cachedDeviceModel = 'Dispozitiv necunoscut';
    return _cachedDeviceModel!;
  }
}

