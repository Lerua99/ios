import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../config/api_config.dart';
import 'package:intl/intl.dart';

class ContactInstallerScreen extends StatefulWidget {
  const ContactInstallerScreen({Key? key}) : super(key: key);

  @override
  State<ContactInstallerScreen> createState() => _ContactInstallerScreenState();
}

class _ContactInstallerScreenState extends State<ContactInstallerScreen> {
  String selectedGate = 'Poartă Principală';
  final TextEditingController _problemController = TextEditingController();
  DateTime? selectedDate;
  TimeOfDay? selectedTime;
  bool _isLoading = false;

  final List<String> gates = [
    'Poartă Principală',
    'Poartă Secundară',
    'Poartă Garaj',
    'Barieră Auto',
    'Ușă Intrare',
    'Altele',
  ];

  @override
  void dispose() {
    _problemController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.teal,
              onPrimary: Colors.black,
              surface: Colors.grey,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  Future<void> _selectTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.teal,
              onPrimary: Colors.black,
              surface: Colors.grey,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      setState(() {
        selectedTime = picked;
      });
    }
  }

  Future<void> _sendSOSRequest() async {
    if (_problemController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Te rog descrie problema!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // DEBUG: Afișăm toate detaliile într-un dialog
    String debugInfo = '';
    
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final userData = authService.userData;
      final token = userData?['token'];

      // Obținem ID-urile din userData (din sesiunea de autentificare)
      final clientId = userData?['client_id'] ?? userData?['id'];
      final installerId = userData?['installer_id'];
      
      if (clientId == null || installerId == null) {
        throw Exception('Date client incomplete. Vă rugăm să vă autentificați din nou.');
      }
      
      final requestData = {
        'client_id': clientId,
        'installer_id': installerId,
        'gate_name': selectedGate,
        'problem_description': _problemController.text.trim(),
        'client_name': userData?['name'] ?? 'Client',
        'client_address': userData?['address'] ?? 'Adresă necunoscută',
        'client_phone': userData?['phone'] ?? '',  // ✅ ADĂUGAT TELEFON
      };
      
      // Adăugăm data și ora doar dacă sunt selectate
      if (selectedDate != null) {
        requestData['preferred_date'] = DateFormat('yyyy-MM-dd').format(selectedDate!);
      }
      if (selectedTime != null) {
        requestData['preferred_time'] = '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}';
      }

      // Construim debug info
      final apiUrl = '${ApiConfig.baseUrl}${ApiConfig.sosEndpoint}';
      debugInfo = '''
=== DEBUG INFO ===
URL: $apiUrl
Token: $token
Date: ${DateTime.now()}

REQUEST DATA:
${JsonEncoder.withIndent('  ').convert(requestData)}

HEADERS:
Authorization: Bearer $token
Content-Type: application/json
Accept: application/json
''';

      print('🔵 Trimit cerere SOS cu datele: $requestData');
      print('🔵 Token: $token');
      
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(requestData),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Timeout: Serverul nu răspunde. Verifică conexiunea la internet și că ești pe aceeași rețea WiFi cu serverul.');
        },
      );

      print('🟢 Răspuns server: ${response.statusCode}');
      print('🟢 Body: ${response.body}');
      
      debugInfo += '''

RESPONSE:
Status Code: ${response.statusCode}
Body: ${response.body}
''';

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          // Afișăm dialogul de confirmare cu detalii despre programare
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext context) {
              return AlertDialog(
                backgroundColor: Colors.grey[900],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.teal.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_circle,
                        size: 50,
                        color: Colors.teal,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Cerere trimisă cu succes!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Instalatorul va primi notificare și te va contacta pentru confirmare.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[300],
                      ),
                    ),
                    if (selectedDate != null && selectedTime != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.calendar_today, color: Colors.blue, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Programare dorită: ${DateFormat('dd.MM.yyyy').format(selectedDate!)} la ${selectedTime!.format(context)}',
                              style: const TextStyle(
                                color: Colors.blue,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).pop();
                    },
                    child: const Text(
                      'OK',
                      style: TextStyle(
                        color: Colors.teal,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        }
      } else {
        // Parsăm eroarea din răspuns
        String errorMessage = 'Eroare la trimiterea cererii';
        try {
          final errorData = json.decode(response.body);
          errorMessage = errorData['message'] ?? errorMessage;
        } catch (_) {}
        
        throw Exception('$errorMessage (Status: ${response.statusCode})');
      }
    } catch (e) {
      print('🔴 Eroare completă: $e');
      if (mounted) {
        // Afișăm dialog cu eroarea detaliată
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: Colors.grey[900],
            title: Row(
              children: [
                Icon(Icons.error, color: Colors.red),
                SizedBox(width: 8),
                Text('Eroare', style: TextStyle(color: Colors.white)),
              ],
            ),
            content: Text(
              e.toString().replaceAll('Exception: ', ''),
              style: TextStyle(color: Colors.white),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('OK', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          'Contactează Instalatorul',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header cu icon de avertizare
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.warning,
                      color: Colors.red,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Raportează o problemă tehnică',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),

            // Selectare poartă
            Text(
              'Selectează dispozitivul cu probleme:',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.teal),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedGate,
                  isExpanded: true,
                  dropdownColor: Colors.grey[900],
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                  icon: const Icon(Icons.arrow_drop_down, color: Colors.teal),
                  items: gates.map((String gate) {
                    return DropdownMenuItem<String>(
                      value: gate,
                      child: Text(gate),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    setState(() {
                      selectedGate = newValue!;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Descriere problemă
            Text(
              'Descrie problema:',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[800]!),
              ),
              child: TextField(
                controller: _problemController,
                maxLines: 5,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Ex: Poarta nu se deschide complet, face zgomot ciudat...',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Programare preferată
            Text(
              'Programare preferată (opțional):',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _selectDate,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selectedDate != null ? Colors.blue : Colors.grey[800]!,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            color: selectedDate != null ? Colors.blue : Colors.grey[600],
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            selectedDate != null
                                ? DateFormat('dd.MM.yyyy').format(selectedDate!)
                                : 'Alege data',
                            style: TextStyle(
                              color: selectedDate != null ? Colors.white : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: _selectTime,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selectedTime != null ? Colors.blue : Colors.grey[800]!,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            color: selectedTime != null ? Colors.blue : Colors.grey[600],
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            selectedTime != null
                                ? selectedTime!.format(context)
                                : 'Alege ora',
                            style: TextStyle(
                              color: selectedTime != null ? Colors.white : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),

            const Spacer(),
            // Butoane – fixate mai sus pentru a evita acoperirea de tastatură
            SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: Colors.grey[600]!),
                        foregroundColor: Colors.grey[300],
                      ),
                      child: const Text('Anulează'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _sendSOSRequest,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Trimite SOS', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
              ),
            ),
          );
        },
      ),
    );
  }
} 