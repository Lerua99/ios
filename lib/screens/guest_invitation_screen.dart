import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Pentru Clipboard
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'package:share_plus/share_plus.dart'; // NOU: pentru partajare
import 'package:url_launcher/url_launcher.dart';

class GuestInvitationScreen extends StatefulWidget {
  @override
  _GuestInvitationScreenState createState() => _GuestInvitationScreenState();
}

class _GuestInvitationScreenState extends State<GuestInvitationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _guestNameController = TextEditingController();
  final _guestEmailController = TextEditingController();
  final _guestPhoneController = TextEditingController();
  final _customMessageController = TextEditingController();
  
  DateTime _validFrom = DateTime.now();
  DateTime _validUntil = DateTime.now().add(Duration(days: 1));
  int _maxUses = 4; // Doar numere pare (2, 4, 6...)
  bool _sendEmail = true;
  bool _isLoading = false;
  Map<String, dynamic>? _lastCreatedInvitation; // Pentru butonul de partajare
  
  List<Map<String, dynamic>> _guestPasses = [];

  @override
  void initState() {
    super.initState();
    _loadGuestPasses();
  }

  Future<void> _loadGuestPasses() async {
    try {
      final response = await ApiService.getGuestPasses();
      if (response['success']) {
        setState(() {
          _guestPasses = List<Map<String, dynamic>>.from(response['data']);
        });
      }
    } catch (e) {
      print('Error loading guest passes: $e');
    }
  }

  Future<void> _createGuestPass() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await ApiService.createGuestPass({
        'guest_name': _guestNameController.text,
        'guest_email': 'guest@hopa.app', // Email dummy - nu se folosește
        'guest_phone': null,
        'valid_from': _validFrom.toIso8601String(),
        'valid_until': _validUntil.toIso8601String(),
        'max_uses': _maxUses,
        'custom_message': _customMessageController.text.isEmpty ? null : _customMessageController.text,
        'send_email': false, // NU trimite email automat
      });

      if (response['success']) {
        final guestPass = response['data'];
        
        _clearForm();
        _loadGuestPasses();
        
        // Salvez ultima invitație creată pentru butoanele de partajare/cancel
        setState(() {
          _lastCreatedInvitation = guestPass;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Invitația a fost creată cu succes!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        throw Exception(response['message'] ?? 'Eroare necunoscută');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Eroare: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _clearForm() {
    _guestNameController.clear();
    _guestEmailController.clear();
    _guestPhoneController.clear();
    _customMessageController.clear();
    setState(() {
      _validFrom = DateTime.now();
      _validUntil = DateTime.now().add(Duration(days: 1));
      _maxUses = 5;
      _sendEmail = true;
    });
  }

  Future<void> _selectDate(bool isValidFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isValidFrom ? _validFrom : _validUntil,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(Duration(days: 365)),
    );
    
    if (picked != null) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(isValidFrom ? _validFrom : _validUntil),
      );
      
      if (time != null) {
        final dateTime = DateTime(
          picked.year,
          picked.month,
          picked.day,
          time.hour,
          time.minute,
        );
        
        setState(() {
          if (isValidFrom) {
            _validFrom = dateTime;
            if (_validUntil.isBefore(_validFrom)) {
              _validUntil = _validFrom.add(Duration(hours: 2));
            }
          } else {
            _validUntil = dateTime;
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('🎫 Invitații Oaspeți'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            Container(
              color: Colors.deepPurple,
              child: TabBar(
                indicatorColor: Colors.white,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                tabs: [
                  Tab(icon: Icon(Icons.add), text: 'Creare Nouă'),
                  Tab(icon: Icon(Icons.list), text: 'Invitații Active'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildCreateTab(),
                  _buildListTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 4,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '👤 Informații Oaspete',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 16),
                    TextFormField(
                      controller: _guestNameController,
                      decoration: InputDecoration(
                        labelText: 'Nume Complet *',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value?.isEmpty ?? true) {
                          return 'Numele este obligatoriu';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),
            Card(
              elevation: 4,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '📅 Perioada de Validitate',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 16),
                    ListTile(
                      leading: Icon(Icons.access_time, color: Colors.green),
                      title: Text('De la: ${_formatDateTime(_validFrom)}'),
                      trailing: Icon(Icons.edit),
                      onTap: () => _selectDate(true),
                      tileColor: Colors.green.shade50,
                    ),
                    SizedBox(height: 8),
                    ListTile(
                      leading: Icon(Icons.access_time_filled, color: Colors.red),
                      title: Text('Până la: ${_formatDateTime(_validUntil)}'),
                      trailing: Icon(Icons.edit),
                      onTap: () => _selectDate(false),
                      tileColor: Colors.red.shade50,
                    ),
                    SizedBox(height: 16),
                    Text('Număr maxim acționări (doar numere pare):', style: TextStyle(fontWeight: FontWeight.bold)),
                    Slider(
                      value: _maxUses.toDouble(),
                      min: 2,
                      max: 50,
                      divisions: 24, // 2, 4, 6, 8... 50 = 24 diviziuni
                      label: '$_maxUses acționări',
                      onChanged: (value) {
                        setState(() {
                          // Rotunjește la cel mai apropiat număr par
                          int rounded = value.round();
                          _maxUses = rounded % 2 == 0 ? rounded : rounded + 1;
                        });
                      },
                    ),
                    Text(
                      'ℹ️ O vizită completă = 2 acționări (deschis + închis)',
                      style: TextStyle(fontSize: 12, color: Colors.blue[700], fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),
            Card(
              elevation: 4,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '✉️ Opțiuni Suplimentare',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 16),
                    TextFormField(
                      controller: _customMessageController,
                      decoration: InputDecoration(
                        labelText: 'Mesaj personalizat (opțional)',
                        prefixIcon: Icon(Icons.message),
                        border: OutlineInputBorder(),
                        hintText: 'Ex: Vă așteptăm cu drag!',
                      ),
                      maxLines: 3,
                      maxLength: 500,
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _createGuestPass,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? CircularProgressIndicator(color: Colors.white)
                  : Text(
                      '🎫 Creează Invitația',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
            ),
            SizedBox(height: 16),
            
            // Butoane "Partajează Invitația" și "Cancel" - apar doar dacă există o invitație creată recent
            if (_lastCreatedInvitation != null)
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        // Partajează DIRECT ca la Invitații Active
                        final pass = _lastCreatedInvitation!;
                        final String guestName = pass['guest_name'];
                        final String link = pass['link'] ?? (() {
                          final String base = ApiService.baseUrl;
                          final String host = base.replaceAll('/api/v1', '');
                          final String token = pass['token'] ?? '';
                          return '$host/guest?token=$token';
                        })();
                        final DateTime validUntil = DateTime.parse(pass['valid_until']);
                        final int maxUses = pass['max_uses'];
                        
                        final String message = '''
🎫 Invitație HOPA - Acces Poartă

Bună, $guestName!

Ai primit acces temporar la poarta mea prin aplicația HOPA.

📱 Link acces: $link

⏰ Valabil până la: ${_formatDateTime(validUntil)}
🔢 Număr maxim acționări: $maxUses
ℹ️ O vizită completă = 2 acționări (deschis + închis)

Apasă pe link pentru a deschide/închide poarta.
''';
                        
                        try {
                          await Share.share(message, subject: 'Invitație HOPA - Acces Poartă');
                          // După partajare, resetează butoanele
                          setState(() {
                            _lastCreatedInvitation = null;
                          });
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Eroare la partajare: $e')),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: Icon(Icons.share),
                      label: Text(
                        'Partajează Invitația',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _lastCreatedInvitation = null; // Resetează și ascunde butoanele
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Anulat. Poți crea o nouă invitație.'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[700],
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: Icon(Icons.cancel),
                      label: Text(
                        'Cancel',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            
            // Extra spațiu pentru a evita suprapunerea cu bara de navigație/gestures
            SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
          ],
        ),
      ),
    );
  }

  Widget _buildListTab() {
    return RefreshIndicator(
      onRefresh: _loadGuestPasses,
      child: ListView.builder(
        padding: EdgeInsets.all(16),
        itemCount: _guestPasses.length,
        itemBuilder: (context, index) {
          final pass = _guestPasses[index];
          final isActive = pass['is_active'] == true;
          final validUntil = DateTime.parse(pass['valid_until']);
          final isExpired = validUntil.isBefore(DateTime.now());
          
          return Card(
            margin: EdgeInsets.only(bottom: 12),
            elevation: 4,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: isActive && !isExpired ? Colors.green : Colors.red,
                child: Icon(
                  isActive && !isExpired ? Icons.check : Icons.close,
                  color: Colors.white,
                ),
              ),
              title: Text(
                pass['guest_name'],
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('📧 ${pass['guest_email']}'),
                  Text('📅 Până la: ${_formatDateTime(validUntil)}'),
                  Text('🔢 Utilizări: ${pass['used_count']}/${pass['max_uses']}'),
                ],
              ),
              onTap: () => _openGuestLink(pass),
              trailing: PopupMenuButton(
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'share',
                    child: Row(
                      children: [
                        Icon(Icons.share),
                        SizedBox(width: 8),
                        Text('Partajează Link'),
                      ],
                    ),
                  ),
                  if (isActive)
                    PopupMenuItem(
                      value: 'deactivate',
                      child: Row(
                        children: [
                          Icon(Icons.block),
                          SizedBox(width: 8),
                          Text('Dezactivează'),
                        ],
                      ),
                    ),
                ],
                onSelected: (value) => _handlePassAction(value, pass),
              ),
              isThreeLine: true,
            ),
          );
        },
      ),
    );
  }

  // NOU: Funcție pentru dezactivare link oaspeți
  Future<void> _deactivateGuestPass(Map<String, dynamic> pass) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('Dezactivează Invitația'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ești sigur că vrei să dezactivezi acest link?'),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '👤 ${pass['guest_name']}',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text('📧 ${pass['guest_email']}', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            SizedBox(height: 12),
            Text(
              '⚠️ Oaspetele nu va mai putea folosi link-ul pentru a accesa poarta.',
              style: TextStyle(color: Colors.red.shade700, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Anulează'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Dezactivează', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // Apel API pentru dezactivare
        final response = await ApiService.deactivateGuestPass(pass['id']);
        
        if (response['success']) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white),
                    SizedBox(width: 8),
                    Text('✅ Link dezactivat cu succes!'),
                  ],
                ),
                backgroundColor: Colors.green,
              ),
            );
          }
          _loadGuestPasses(); // Refresh lista
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Eroare: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
  
  // NOU: Deschide link-ul oaspete în browser
  Future<void> _openGuestLink(Map<String, dynamic> pass) async {
    try {
      final String link = pass['link'] ?? (() {
        final String base = ApiService.baseUrl;
        final String host = base.replaceAll('/api/v1', '');
        final String token = pass['token'] ?? '';
        return '$host/guest?token=$token';
      })();
      final uri = Uri.parse(link);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nu pot deschide link-ul')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare la deschiderea link-ului: $e')),
        );
      }
    }
  }


  // NOU: Funcție pentru partajare link oaspeți
  Future<void> _shareGuestLink(Map<String, dynamic> pass) async {
    final String guestName = pass['guest_name'];
    // Preferă link-ul generat de backend; fallback calculează corect domeniul (fără /api/v1)
    final String link = pass['link'] ?? (() {
      final String base = ApiService.baseUrl;
      final String host = base.replaceAll('/api/v1', '');
      final String token = pass['token'] ?? '';
      return '$host/guest?token=$token';
    })();
    final DateTime validUntil = DateTime.parse(pass['valid_until']);
    final int maxUses = pass['max_uses'];
    
    final String message = '''
🎫 Invitație HOPA - Acces Poartă

Bună, $guestName!

Ai primit acces temporar la poarta mea prin aplicația HOPA.

📱 Link acces: $link

⏰ Valabil până la: ${_formatDateTime(validUntil)}
🔢 Număr maxim acționări: $maxUses
ℹ️ O vizită completă = 2 acționări (deschis + închis)

Apasă pe link pentru a deschide/închide poarta.
''';

    // Dialog pentru selectare canal de partajare
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.share, color: Colors.deepPurple),
            SizedBox(width: 8),
            Text('Partajează Link'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.share, color: Colors.blue),
              title: Text('Partajează prin...'),
              subtitle: Text('WhatsApp, Email, SMS, etc.'),
              onTap: () async {
                Navigator.pop(context);
                try {
                  await Share.share(
                    message,
                    subject: 'Invitație HOPA - Acces Poartă',
                  );
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Eroare la partajare: $e')),
                    );
                  }
                }
              },
            ),
            Divider(),
            ListTile(
              leading: Icon(Icons.copy, color: Colors.orange),
              title: Text('Copiază Link'),
              subtitle: Text('Link-ul va fi copiat în clipboard'),
              onTap: () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(text: link));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.white),
                        SizedBox(width: 8),
                        Text('✅ Link copiat în clipboard'),
                      ],
                    ),
                    backgroundColor: Colors.green,
                  ),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Închide'),
          ),
        ],
      ),
    );
  }
  
  void _handlePassAction(String action, Map<String, dynamic> pass) {
    switch (action) {
      case 'share':
        _shareGuestLink(pass);
        break;
      case 'deactivate':
        _deactivateGuestPass(pass);
        break;
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day.toString().padLeft(2, '0')}.${dateTime.month.toString().padLeft(2, '0')}.${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _guestNameController.dispose();
    _guestEmailController.dispose();
    _guestPhoneController.dispose();
    _customMessageController.dispose();
    super.dispose();
  }
} 