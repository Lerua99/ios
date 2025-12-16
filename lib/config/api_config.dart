class ApiConfig {
  // ====== CONFIGURAȚIA ACTIVĂ (ESP32 DIRECT) ======
  // Folosim backend-ul de producție
  static const String baseUrl = 'https://hopa.tritech.ro/api/v1';
  
  // ====== ALTERNATIVE (comentate) ======
  // static const String baseUrl = 'http://192.168.1.XXX'; // alt IP ESP32
  // static const String baseUrl = 'http://10.0.2.2:8000/api/v1'; // emulator
  // static const String baseUrl = 'http://192.168.1.128:8000/api/v1'; // Laravel local
  
  // Endpoints
  static const String sosEndpoint = '/sos/send';
  static const String loginEndpoint = '/login-code';
  static const String gateOpenEndpoint = '/gate/open'; // Endpoint vechi (pentru compatibilitate)
  static const String gateControlEndpoint = '/gate/control'; // Endpoint nou unificat
} 