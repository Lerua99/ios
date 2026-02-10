import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../services/auth_service.dart';
import '../services/theme_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../services/api_service.dart';
import 'help_screen.dart';


class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _deviceNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  
  // ignore: unused_field
  String? _fcmToken;   // token local - folosit în _registerToken
  // ignore: unused_field
  final bool _sendingToken = false; // status - folosit în _registerToken
  // ignore: unused_field
  List<dynamic> _plans = [];
  // ignore: unused_field
  bool _loadingPlans = false;
  
  @override
  void initState() {
    super.initState();
    _safeInit();
  }

  /// Inițializare defensivă — orice eroare este prinsă pentru a nu crasha ecranul
  Future<void> _safeInit() async {
    // 1. FCM token — complet opțional, nu blochează UI-ul
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (mounted) setState(() => _fcmToken = token);
    } catch (e) {
      debugPrint('⚠️ Nu s-a putut obține FCM token: $e');
    }

    // 2. Plans — complet opțional
    try {
      await _fetchPlans();
    } catch (e) {
      debugPrint('⚠️ Eroare la încărcarea planurilor: $e');
    }
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
        const SnackBar(backgroundColor: Colors.green, content: Text('Abonament activat cu succes!')),
      );
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Eroare la upgrade: $e')),
      );
    }
  }
  
  @override
  void dispose() {
    _deviceNameController.dispose();
    _phoneController.dispose();
    super.dispose();
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
    final systems = ['BFT', 'FAAC', 'Nice', 'CAME', 'Beninca', 'Motorline', 'Sommer', 'Hörmann'];
    
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
                        style: TextStyle(color: Colors.red[700], fontSize: 13, fontWeight: FontWeight.bold),
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
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 16,
                        ),
                      ),
                      trailing: isSelected
                          ? Icon(Icons.check_circle, color: Colors.teal, size: 24)
                          : Icon(Icons.radio_button_unchecked, color: Colors.grey[500], size: 24),
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
            _buildVoiceCommand('🔓', 'Deschide poarta', '"Hey ${Platform.isIOS ? 'Siri' : 'Google'}, Hopa"'),
            _buildVoiceCommand('🔒', 'Închide poarta', '"Hey ${Platform.isIOS ? 'Siri' : 'Google'}, Hopa închide"'),
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
                    color: Platform.isIOS ? Colors.blue[300] : Colors.orange[300],
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
    // Wrap complet în try-catch — pe release builds Flutter arată ecran GRI
    // dacă build() aruncă o excepție neprinsă. Acest wrapper garantează
    // afișarea unui fallback vizibil în loc de ecranul gri.
    try {
      return _buildSettingsContent(context);
    } catch (e) {
      debugPrint('❌ CRASH în SettingsScreen.build(): $e');
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Setări', style: TextStyle(color: Colors.white)),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 64),
              const SizedBox(height: 16),
              const Text(
                'Eroare la afișarea setărilor',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                e.toString(),
                style: const TextStyle(color: Colors.grey, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => setState(() {}),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                child: const Text('Reîncearcă'),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildSettingsContent(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final themeService = Provider.of<ThemeService>(context);
    final userData = authService.userData;
    
    final name = (userData?['name'] ?? 'N/A').toString();
    final accountType = (userData?['account_type'] ?? 'Standard').toString();
    final clientCode = (userData?['activation_code'] ?? 'N/A').toString();
    final phone = (userData?['phone'] ?? 'N/A').toString();
    final address = (userData?['address'] ?? 'N/A').toString();
    final systemType = (userData?['system_type'] ?? '').toString();
    final displaySystemType = systemType.isEmpty || systemType == '-' ? 'OBLIGATORIU - Selectează marca' : systemType;
    final device = (userData?['device'] ?? 'Poartă Principală').toString();
    
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
              _buildEditableRow('Telefon', phone, Icons.phone, () => _changePhoneNumber(phone)),
              _buildInfoRow('Adresă', formattedAddress),
              _buildEditableRow('Sistem automatizare', displaySystemType, Icons.settings_remote, () => _changeAutomationSystem(systemType)),
              _buildEditableRow('Dispozitiv', device, Icons.door_sliding, () => _editDeviceName(device)),
              
              const SizedBox(height: 40),
              
              // Secțiunea NOTIFICĂRI eliminată la cerere
              
              const SizedBox(height: 40),
              
              // Secțiunea COMENZI VOCALE mutată în Setări Notificări
              
              const SizedBox(height: 40),
              
              // Secțiunea AJUTOR
              _buildSectionTitle('Ajutor'),
              const SizedBox(height: 20),
              
              // Buton Help - deschide ecran cu FAQ
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const HelpScreen()),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.3), width: 1),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.help_outline, color: Colors.deepPurple, size: 28),
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
                      Icon(Icons.arrow_forward_ios, color: Colors.grey[400], size: 18),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 40),
              
              // Secțiunea DESPRE
              _buildSectionTitle('Despre'),
              const SizedBox(height: 20),
              
              _buildInfoRow('Versiune', '1.97.3'),
              _buildInfoRow('Dezvoltator', 'Casa Luminii Balasa S.R.L.'),
              
              const SizedBox(height: 40),
            ],
          ),
        ),
        ),
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
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 16,
              ),
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

  Widget _buildEditableRow(String label, String value, IconData icon, VoidCallback onTap) {
    final isSystemRequired = label == 'Sistem automatizare' && (value.contains('OBLIGATORIU') || value == '-');
    
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: isSystemRequired ? BoxDecoration(
          border: Border.all(color: Colors.orange, width: 2),
          borderRadius: BorderRadius.circular(8),
          color: Colors.orange.withValues(alpha: 0.1),
        ) : null,
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
                        color: isSystemRequired ? Colors.orange : Colors.grey[500],
                        fontSize: 16,
                        fontWeight: isSystemRequired ? FontWeight.bold : FontWeight.normal,
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

}
