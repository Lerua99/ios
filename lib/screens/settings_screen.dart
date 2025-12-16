import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../services/auth_service.dart';
import '../services/theme_service.dart';
import '../services/notification_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../services/api_service.dart';
import 'help_screen.dart';


class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _deviceNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  
  String? _fcmToken;   // token local
  bool _sendingToken = false; // status
  List<dynamic> _plans = [];
  bool _loadingPlans = false;
  
  @override
  void initState() {
    super.initState();
    // Obține tokenul FCM pentru afișare rapidă
    FirebaseMessaging.instance.getToken().then((token) {
      if (mounted) setState(() => _fcmToken = token);
    }).catchError((error) {
      // Ignorăm eroarea Firebase - nu e critică pentru funcționarea aplicației
      print('⚠️ Nu s-a putut obține FCM token: $error');
    });
    _fetchPlans();
  }

  Future<void> _fetchPlans() async {
    setState(() => _loadingPlans = true);
    try {
      _plans = await ApiService.getSubscriptionPlans();
    } catch (_) {}
    setState(() => _loadingPlans = false);
  }

  Future<void> _upgradePlan(int planId) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    Navigator.pop(context); // close dialog
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Se activează abonamentul...')),
    );
    try {
      await ApiService.upgradeSubscription(planId, 0);
      await authService.syncSubscriptionStatus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: Colors.green, content: Text('Abonament activat cu succes!')),
      );
      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Eroare la upgrade: $e')),
      );
    }
  }

  void _showUpgradeDialog() {
    if (_loadingPlans) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Selectează un plan'),
        content: SizedBox(
          width: double.maxFinite,
          child: _plans.isEmpty
              ? const Text('Nu sunt planuri disponibile')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _plans.length,
                  itemBuilder: (c, i) {
                    final p = _plans[i];
                    return ListTile(
                      title: Text(p['name']),
                      subtitle: Text('${(p['price_cents'] / 100).toStringAsFixed(2)} ${p['currency']}'),
                      onTap: () => _upgradePlan(p['id']),
                    );
                  },
                ),
        ),
      ),
    );
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
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.updateDeviceName(result);
      
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
                color: Colors.orange.withOpacity(0.2),
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
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.updatePhoneNumber(result);
      
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
                  color: Colors.red.withOpacity(0.2),
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
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.updateSystemType(result);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sistem schimbat în $result'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

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

  Future<void> _registerToken() async {
    setState(() => _sendingToken = true);
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await ApiService.updateFcmToken(token);
        setState(() => _fcmToken = token);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Token FCM trimis la server')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Nu s-a putut obține token FCM')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Eroare: $e')),
      );
    } finally {
      if (mounted) setState(() => _sendingToken = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final themeService = Provider.of<ThemeService>(context);
    final userData = authService.userData;
    
    final name = userData?['name'] ?? 'N/A';
    final accountType = userData?['account_type'] ?? 'Standard';
    final clientCode = userData?['activation_code'] ?? 'N/A';
    final phone = userData?['phone'] ?? 'N/A';
    final address = userData?['address'] ?? 'N/A';
    final systemType = userData?['system_type'] ?? '';
    final displaySystemType = systemType.isEmpty || systemType == '-' ? 'OBLIGATORIU - Selectează marca' : systemType;
    final device = userData?['device'] ?? 'Poartă Principală';
    final isPro = authService.isPro;
    final isTrialActive = authService.isProTrialActive;
    final trialDaysRemaining = authService.trialDaysRemaining;
    
    final formattedAddress = address
        .replaceAll('CT', 'Constanța')
        .replaceAll('JUDETUL', 'Județul');

    return themeService.getBackgroundWidget(
      Scaffold(
        backgroundColor: Colors.transparent,
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
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Secțiunea CONT
              _buildSectionTitle('Cont'),
              const SizedBox(height: 20),
              
              _buildInfoRow('Nume', name),
              _buildInfoRow('Tip cont', accountType),
              
              // Trial countdown dacă este activ
              if (isTrialActive)
                Container(
                  padding: EdgeInsets.all(12),
                  margin: EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber, width: 1),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.timer, color: Colors.amber[700], size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'PRO trial: $trialDaysRemaining ${trialDaysRemaining == 1 ? 'zi rămasă' : 'zile rămase'}',
                          style: TextStyle(
                            color: Colors.amber[700],
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (trialDaysRemaining <= 3)
                        Icon(Icons.warning, color: Colors.orange, size: 18),
                    ],
                  ),
                ),
              
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
              
              // Secțiunea UPGRADE
              _buildSectionTitle('Upgrade'),
              const SizedBox(height: 20),
              
              _buildUpgradeToProCard(),
              
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
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.deepPurple.withOpacity(0.3), width: 1),
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
              
              _buildInfoRow('Versiune', '1.90'),
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
          color: Colors.orange.withOpacity(0.1),
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

  Widget _buildSwitchRow(String label, bool value, Function(bool) onChanged) {
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
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeColor: Colors.teal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpgradeToProCard() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final userData = authService.userData;
    final accountType = userData?['account_type'] ?? 'Standard';
    final isPro = authService.isPro;
    final isTrialActive = authService.isProTrialActive;
    final trialDaysRemaining = authService.trialDaysRemaining;
    
    if (isPro && !isTrialActive) {
      // PRO permanent activ
      // Card pentru utilizatorii PRO - afișează beneficiile active
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.purple.shade800, Colors.purple.shade600],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.purple.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.star, color: Colors.amber, size: 28),
                const SizedBox(width: 10),
                Text(
                  'HOPA PRO Activ',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Beneficiile tale PRO active:',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            _buildProFeature('🎨', 'Tema PRO'),
            _buildProFeature('📡', 'Detectare HOPA automată'),
            _buildProFeature('🚪', 'Control complet poartă'),
            _buildProFeature('🔔', 'Notificări avansate'),
            _buildProFeature('📊', 'Statistici detaliate'),
          ],
        ),
      );
    } else if (isTrialActive) {
      // Card pentru trial PRO activ cu countdown
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.amber.shade800, Colors.amber.shade600],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.amber.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.star_half, color: Colors.white, size: 28),
                const SizedBox(width: 10),
                Text(
                  'PRO Trial Activ',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.timer, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '$trialDaysRemaining ${trialDaysRemaining == 1 ? 'zi rămasă' : 'zile rămase'}',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (trialDaysRemaining <= 3) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.warning, color: Colors.red, size: 20),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Beneficii PRO active în trial:',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            _buildProFeature('🎨', 'Tema PRO'),
            _buildProFeature('📡', 'Detectare HOPA automată'),
            _buildProFeature('🚪', 'Control complet poartă'),
            _buildProFeature('🔔', 'Notificări avansate'),
            _buildProFeature('📊', 'Statistici detaliate'),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _startProTrial,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.orange.shade800,
                    ),
                    child: const Text('TRIAL 15 ZILE'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _showUpgradeDialog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('UPGRADE'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    } else {
      // Card pentru utilizatorii Standard - încurajează upgrade
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.orange.shade800, Colors.orange.shade600],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.orange.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.upgrade, color: Colors.white, size: 28),
                const SizedBox(width: 10),
                Text(
                  'Treci la PRO',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Deblochează toate funcțiile:',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            _buildProFeature('🎨', 'Tema PRO'),
            _buildProFeature('📡', 'Detectare HOPA automată'),
            _buildProFeature('🚪', 'Automatizare completă'),
            _buildProFeature('🔔', 'Notificări în timp real'),
            _buildProFeature('📊', 'Istoric și statistici'),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _startProTrial,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.orange.shade800,
                    ),
                    child: const Text('TRIAL 15 ZILE'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _showUpgradeDialog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('UPGRADE'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }
  }
  
  Widget _buildProFeature(String icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(icon, style: TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Text(
            text,
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startProTrial() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Se activează trial-ul PRO...'),
        backgroundColor: Colors.blueGrey,
        duration: const Duration(seconds: 2),
      ),
    );
    try {
      await authService.startProTrial();
      if (authService.isPro) {
        final themeService = Provider.of<ThemeService>(context, listen: false);
        await themeService.setTheme(AppTheme.current);
      }
      setState(() {}); // re-render pentru a arăta cardul PRO
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Trial PRO activat pentru 15 zile!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Eroare activare PRO: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
