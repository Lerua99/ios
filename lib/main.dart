import 'package:flutter/material.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
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
  
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }
  
  Future<void> _initializeApp() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final prefs = await SharedPreferences.getInstance();
      
      // Citește GDPR la pornire - verifică atât key-ul vechi cât și cel nou legat de user
      // Pentru compatibilitate cu versiunile vechi
      final oldGdprAccepted = prefs.getBool('gdpr_accepted') ?? false;
      
      // Verifică dacă avem token pentru a crea key specific per-user
      final token = prefs.getString('auth_token');
      if (token != null && token.isNotEmpty) {
        // Folosește key specific per-user (bazat pe hash-ul token-ului)
        final userKey = 'gdpr_accepted_${token.substring(0, 10)}'; // Primele 10 caractere
        _gdprAccepted = prefs.getBool(userKey) ?? oldGdprAccepted;
        
        // Dacă avem acceptare veche, o migrăm la noul key
        if (oldGdprAccepted && !_gdprAccepted) {
          await prefs.setBool(userKey, true);
          _gdprAccepted = true;
        }
      } else {
        _gdprAccepted = oldGdprAccepted;
      }
      
      // Verifică dacă trial-ul PRO a expirat (doar pentru clienți)
      if (authService.isClient) {
        await authService.checkTrialExpiry();
        
        // Afișează popup de trial DOAR pentru CLIENȚI (nu pentru instalatori)
        if (authService.isAuthenticated && !authService.isPro) {
          final hasSeenTrialPopup = prefs.getBool('has_seen_trial_popup') ?? false;
          
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
            Text(
              'Încearcă HOPA PRO',
              style: TextStyle(color: Colors.white),
            ),
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
              CircularProgressIndicator(
                color: Colors.teal,
              ),
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
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    final authService = Provider.of<AuthService>(context);
    
    if (authService.isAuthenticated) {
      // Blochează aplicația până la acceptarea GDPR
      if (!_gdprAccepted) {
        return GdprDialogScreen(
          onAccepted: () async {
            final prefs = await SharedPreferences.getInstance();
            
            // Salvează atât key-ul vechi (pentru compatibilitate) cât și cel specific per-user
            await prefs.setBool('gdpr_accepted', true);
            
            // Salvează și cu key specific per-user
            final token = prefs.getString('auth_token');
            if (token != null && token.isNotEmpty) {
              final userKey = 'gdpr_accepted_${token.substring(0, 10)}';
              await prefs.setBool(userKey, true);
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
            final hasAnyState = data.containsKey('state') || data.containsKey('gate_status');
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