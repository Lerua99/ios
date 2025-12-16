class AppConfig {
  // Domeniul de producție
  static const String baseUrl = 'https://hopa.tritech.ro';
  static const String apiUrl = '$baseUrl/api/v1';
  
  // Firebase config (va fi configurat automat prin google-services.json)
  static const bool enableFirebase = true;
  
  // App info
  static const String appName = 'HOPA';
  static const String appVersion = '1.0.0';
  
  // Timeouts
  static const int connectionTimeout = 30000; // 30 seconds
  static const int receiveTimeout = 30000; // 30 seconds
} 