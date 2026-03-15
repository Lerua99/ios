import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'services/auth_service.dart';
import 'services/theme_service.dart';
import 'services/notification_service.dart';
import 'providers/gate_provider.dart';
import 'services/api_service.dart';
import 'screens/login_screen.dart';
import 'screens/gate_control_screen.dart';
import 'screens/provision_wait_screen.dart';
import 'screens/gdpr_dialog_screen.dart';
import 'screens/installer_dashboard_screen.dart';
import 'screens/camera_stream_screen.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
final Set<String> _handledMessageIds = <String>{};

bool _isTrueLike(dynamic value) {
  final text = (value ?? '').toString().trim().toLowerCase();
  return text == '1' || text == 'true' || text == 'yes' || text == 'y';
}

bool _shouldOpenCameraFromPush(Map<String, dynamic> data) {
  if (_isTrueLike(data['open_camera'])) {
    return true;
  }

  final type = (data['type'] ?? '').toString().toLowerCase();
  final action = (data['action'] ?? '').toString().toLowerCase();
  if (type == 'gate_action' && (action == 'opened' || action == 'open')) {
    return true;
  }

  final watchedKeys = <String>[
    'screen',
    'target',
    'route',
    'action',
    'type',
    'click_action',
  ];

  for (final key in watchedKeys) {
    final value = (data[key] ?? '').toString().toLowerCase();
    if (value.contains('camera')) {
      return true;
    }
  }

  return false;
}

bool _isShellyType(String raw) {
  final lowered = raw.trim().toLowerCase();
  return lowered.contains('shelly');
}

bool _isEsp32Type(String raw) {
  final lowered = raw.trim().toLowerCase();
  return lowered == 'esp32' ||
      lowered == 'hopa' ||
      lowered.startsWith('hopa_') ||
      lowered.startsWith('hopa-') ||
      lowered.startsWith('hopa ');
}

Future<bool> _canOpenCameraForPush(Map<String, dynamic> data) async {
  final payloadType =
      (data['device_type'] ?? data['module_type'] ?? data['controller_type'])
          .toString();

  if (payloadType.trim().isNotEmpty) {
    if (_isShellyType(payloadType)) return false;
    return _isEsp32Type(payloadType);
  }

  try {
    final prefs = await SharedPreferences.getInstance();
    final localType = prefs.getString('device_type') ?? '';
    if (localType.trim().isNotEmpty) {
      if (_isShellyType(localType)) return false;
      return _isEsp32Type(localType);
    }
  } catch (_) {
    // Fallback silențios: dacă nu putem citi tipul modulului, nu deschidem camera.
  }

  return false;
}

String? _extractCameraUrl(Map<String, dynamic> data) {
  final raw = (data['camera_url'] ?? data['stream_url'] ?? data['camera_ip'])
      ?.toString()
      .trim();
  if (raw == null || raw.isEmpty || raw.toLowerCase() == 'null') {
    return null;
  }
  return raw;
}

String? _extractCameraMac(Map<String, dynamic> data) {
  final raw = (data['camera_mac'] ?? data['device_mac'] ?? data['mac_address'])
      ?.toString()
      .trim();
  if (raw == null || raw.isEmpty || raw.toLowerCase() == 'null') {
    return null;
  }

  final normalized = raw.toUpperCase().replaceAll('-', ':');
  if (!RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$').hasMatch(normalized)) {
    return null;
  }
  return normalized;
}

void _openCameraScreen({
  String? cameraUrl,
  String? cameraMac,
  int attempt = 0,
}) {
  final nav = appNavigatorKey.currentState;
  if (nav == null) {
    if (attempt < 10) {
      Future.delayed(
        const Duration(milliseconds: 300),
        () => _openCameraScreen(
          cameraUrl: cameraUrl,
          cameraMac: cameraMac,
          attempt: attempt + 1,
        ),
      );
    }
    return;
  }

  nav.push(
    MaterialPageRoute(
      builder: (_) =>
          CameraStreamScreen(cameraUrl: cameraUrl, deviceMac: cameraMac),
      fullscreenDialog: true,
    ),
  );
}

Future<void> _handleNotificationTap(RemoteMessage message) async {
  final messageId = message.messageId;
  if (messageId != null && _handledMessageIds.contains(messageId)) {
    return;
  }
  if (messageId != null) {
    _handledMessageIds.add(messageId);
  }

  final data = message.data;
  if (!_shouldOpenCameraFromPush(data)) {
    return;
  }
  if (!await _canOpenCameraForPush(data)) {
    return;
  }

  final cameraUrl = _extractCameraUrl(data);
  final cameraMac = _extractCameraMac(data);
  _openCameraScreen(cameraUrl: cameraUrl, cameraMac: cameraMac);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Pornim UI-ul imediat, pentru a elimina întârzierea iniţială
  runApp(const HopaFinalApp());

  // Iniţializăm Firebase şi notificările în fundal
  _initFirebase();
}

Future<void> _initFirebase() async {
  try {
    await Firebase.initializeApp();

    await FirebaseMessaging.instance.requestPermission();

    final fcmToken = await FirebaseMessaging.instance.getToken();
    if (fcmToken != null) {
      print('FCM Token: $fcmToken');
    }

    // 🔄 Ascultă reîmprospătarea token-ului şi îl trimite instant la backend
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      try {
        await ApiService.updateFcmToken(newToken);
        print('🔄 FCM token reîmprospătat şi trimis: $newToken');
      } catch (e) {
        print('❌ Eroare la update FCM token: $e');
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleNotificationTap(message);
    });

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      await _handleNotificationTap(initialMessage);
    }
  } catch (e) {
    print('Firebase init error: $e — continuăm fără Firebase');
  }
}

class HopaFinalApp extends StatelessWidget {
  const HopaFinalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => ThemeService()),
        ChangeNotifierProvider(create: (_) => NotificationService()),
        ChangeNotifierProvider(create: (_) => GateProvider()),
      ],
      child: Consumer<ThemeService>(
        builder: (context, themeService, child) {
          return MaterialApp(
            title: 'HOPA Gates',
            theme: themeService.flutterThemeData,
            navigatorKey: appNavigatorKey,
            home: const AuthWrapper(),
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoading = true;
  bool _gdprAccepted = false;
  String? _gdprUserKey;
  bool _gdprStatusLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final prefs = await SharedPreferences.getInstance();
      _gdprAccepted = false;

      // GDPR este strict per-cont (nu mai folosim fallback global).
      final role = prefs.getString('user_role');
      final clientId = prefs.getInt('client_id') ?? 0;
      final installerId = prefs.getInt('installer_id') ?? 0;
      if (role != null) {
        final startupKey = _buildGdprUserKey(
          role: role,
          clientId: clientId,
          installerId: installerId,
        );
        if (startupKey != null) {
          _gdprUserKey = startupKey;
          _gdprAccepted = prefs.getBool(startupKey) ?? false;
        }
      }

      // Verifică dacă trial-ul PRO a expirat (doar pentru clienți)
      if (authService.isClient) {
        await authService.checkTrialExpiry();

        // Afișează popup de trial DOAR pentru CLIENȚI (nu pentru instalatori)
        if (authService.isAuthenticated && !authService.isPro) {
          final hasSeenTrialPopup =
              prefs.getBool('has_seen_trial_popup') ?? false;

          if (!hasSeenTrialPopup) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _showTrialOfferPopup();
            });
          }
        }
      }
    } catch (e) {
      print('Error during app initialization: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String? _buildGdprUserKey({
    required String role,
    required int clientId,
    required int installerId,
  }) {
    if (role == 'installer' && installerId > 0) {
      return 'gdpr_accepted_installer_$installerId';
    }
    if (role == 'client' && clientId > 0) {
      return 'gdpr_accepted_client_$clientId';
    }
    return null;
  }

  String? _buildGdprUserKeyFromAuth(AuthService authService) {
    final role = authService.userRole;
    if (role == null) return null;
    final data = authService.userData ?? {};
    final clientId = (data['client_id'] is int) ? data['client_id'] as int : 0;
    final installerId = (data['installer_id'] is int)
        ? data['installer_id'] as int
        : 0;
    return _buildGdprUserKey(
      role: role,
      clientId: clientId,
      installerId: installerId,
    );
  }

  Future<void> _loadGdprForUserKey(String key) async {
    if (_gdprStatusLoading && _gdprUserKey == key) return;
    setState(() {
      _gdprStatusLoading = true;
      _gdprUserKey = key;
      _gdprAccepted = false;
    });

    final prefs = await SharedPreferences.getInstance();
    final accepted = prefs.getBool(key) ?? false;

    if (!mounted) return;
    setState(() {
      _gdprAccepted = accepted;
      _gdprStatusLoading = false;
    });
  }

  void _showTrialOfferPopup() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final prefs = await SharedPreferences.getInstance();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Row(
          children: [
            Icon(Icons.star, color: Colors.amber, size: 28),
            const SizedBox(width: 10),
            Text('Încearcă HOPA PRO', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '🎉 Activează trial-ul GRATUIT pentru 15 zile și deblochează toate funcțiile PRO!',
              style: TextStyle(color: Colors.grey[300], fontSize: 16),
            ),
            const SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '✨ Acces complet la toate funcțiile\n🎨 Tema PRO exclusivă\n📊 Statistici avansate\n🔔 Notificări în timp real',
                style: TextStyle(color: Colors.amber[700], fontSize: 14),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await prefs.setBool('has_seen_trial_popup', true);
              Navigator.pop(context);
            },
            child: Text('Mai târziu', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context); // Închide dialog-ul imediat

              // Arată loading
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Se activează trial-ul...'),
                  backgroundColor: Colors.blueGrey,
                  duration: Duration(seconds: 2),
                ),
              );

              try {
                await authService.startProTrial();
                await prefs.setBool('has_seen_trial_popup', true);

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('🌟 PRO Trial activat pentru 15 zile!'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Eroare la activarea trial-ului'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
            ),
            child: Text('ACTIVEAZĂ GRATUIT'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.teal),
              SizedBox(height: 20),
              Text(
                'HOPA Gates',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Se încarcă...',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    final authService = Provider.of<AuthService>(context);

    if (authService.isAuthenticated) {
      final expectedGdprKey = _buildGdprUserKeyFromAuth(authService);
      if (expectedGdprKey != null && expectedGdprKey != _gdprUserKey) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _loadGdprForUserKey(expectedGdprKey);
        });
        return Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: CircularProgressIndicator(color: Colors.teal)),
        );
      }

      if (_gdprStatusLoading) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: CircularProgressIndicator(color: Colors.teal)),
        );
      }

      // Blochează aplicația până la acceptarea GDPR
      if (!_gdprAccepted) {
        return GdprDialogScreen(
          onAccepted: () async {
            final prefs = await SharedPreferences.getInstance();

            if (_gdprUserKey != null) {
              await prefs.setBool(_gdprUserKey!, true);
            }

            setState(() {
              _gdprAccepted = true;
            });
          },
        );
      }
      // Verifică rolul utilizatorului
      if (authService.isInstaller) {
        // Routing pentru INSTALATORI
        return const InstallerDashboardScreen();
      } else {
        // Routing pentru CLIENȚI (flow existent)
        // Verific rapid dacă dispozitivul este provisionat, dar cu fallback generos
        return FutureBuilder(
          future: ApiService.getGateStatus(),
          builder: (context, snapshot) {
            // Dacă avem eroare de rețea sau răspuns parțial, mergem tot la ecranul principal
            if (snapshot.hasError) {
              return const GateControlScreen();
            }

            if (!snapshot.hasData) {
              // În lipsa datelor, nu blocăm utilizatorul pe ecranul de provisioning
              return const GateControlScreen();
            }

            final data = snapshot.data as Map<String, dynamic>;

            // Considerăm provisionat dacă backend a raportat explicit, sau dacă avem vreun status
            final hasAnyState =
                data.containsKey('state') || data.containsKey('gate_status');
            final provisioned = (data['provisioned'] == true) || hasAnyState;

            if (provisioned) {
              return const GateControlScreen();
            }
            return const ProvisionWaitScreen();
          },
        );
      }
    } else {
      return const LoginScreen();
    }
  }
}
