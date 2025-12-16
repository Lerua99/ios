import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';

class InstallerSOSDetailScreen extends StatefulWidget {
  final Map<String, dynamic> sosData;
  
  const InstallerSOSDetailScreen({Key? key, required this.sosData}) : super(key: key);

  @override
  State<InstallerSOSDetailScreen> createState() => _InstallerSOSDetailScreenState();
}

class _InstallerSOSDetailScreenState extends State<InstallerSOSDetailScreen> {
  late Map<String, dynamic> _sos;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _sos = Map<String, dynamic>.from(widget.sosData);
  }

  @override
  Widget build(BuildContext context) {
    final status = _sos['status'] ?? 'pending';
    final clientName = _sos['client_name'] ?? 'Client';
    final clientPhone = _sos['client_phone'] ?? '';
    final clientAddress = _sos['client_address'] ?? '';
    final problem = _sos['problem_description'] ?? '';
    final gateName = _sos['gate_name'] ?? 'Poartă';
    
    Color statusColor;
    IconData statusIcon;
    String statusText;
    
    switch (status) {
      case 'pending':
        statusColor = Colors.red;
        statusIcon = Icons.warning;
        statusText = 'URGENT - Necesită atenție';
        break;
      case 'acknowledged':
        statusColor = Colors.orange;
        statusIcon = Icons.access_time;
        statusText = 'Preluat - În lucru';
        break;
      case 'resolved':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'Rezolvat';
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help;
        statusText = 'Necunoscut';
    }

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Detalii SOS'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFe74c3c), Color(0xFFc0392b)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Badge
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: statusColor, width: 2),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: statusColor.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(statusIcon, color: statusColor, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            // ✅ DATA PREFERATĂ DE CLIENT (DACĂ EXISTĂ)
            if (_sos['preferred_date'] != null && _sos['preferred_date'].toString().isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.green, width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.calendar_today, color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Client disponibil la:',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.event, color: Colors.green, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '📅 ${_sos['preferred_date']} la ${_sos['preferred_time'] ?? 'oră nedefinită'}',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            
            // Informații Client
            _buildSection(
              title: '👤 Informații Client',
              children: [
                _buildInfoRow(Icons.person, 'Nume', clientName),
                if (clientPhone.isNotEmpty)
                  _buildInfoRow(Icons.phone, 'Telefon', clientPhone),
                if (clientAddress.isNotEmpty)
                  _buildInfoRow(Icons.location_on, 'Adresă', clientAddress),
                _buildInfoRow(Icons.door_sliding, 'Poartă', gateName),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Problema raportată
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '⚠️ Problema Raportată',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.orange.withOpacity(0.3), width: 1),
                  ),
                  child: Text(
                    problem,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.black87,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Acțiuni rapide
            if (clientPhone.isNotEmpty)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _callClient(clientPhone),
                  icon: const Icon(Icons.phone, size: 26),
                  label: const Text('Sună Clientul', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 2,
                  ),
                ),
              ),
            
            const SizedBox(height: 12),
            
            // ⚠️ AVERTIZARE - Trebuie să sune clientul
            if (status != 'resolved') ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue, width: 1.5),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info, color: Colors.blue, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _sos['preferred_date'] != null 
                            ? '💡 Clientul e disponibil la data afișată. Dacă nu poți, sună-l pentru reprogramare!'
                            : '📞 Sună clientul pentru a stabili o programare!',
                        style: const TextStyle(
                          color: Colors.blue,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            
            // Acțiuni bazate pe status
            if (status == 'pending') ...[
              // ✅ BUTON: Accept cu data clientului (dacă există)
              if (_sos['preferred_date'] != null && _sos['preferred_date'].toString().isNotEmpty) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _acceptClientDate,
                    icon: const Icon(Icons.check_circle, size: 26),
                    label: const Text('✅ Accept cu această dată', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _acknowledgeAlert,
                  icon: const Icon(Icons.check, size: 26),
                  label: const Text('Marchează ca Preluat', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 2,
                  ),
                ),
              ),
            ] else if (status == 'acknowledged') ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _scheduleVisit,
                  icon: const Icon(Icons.calendar_today, size: 26),
                  label: Text(
                    _sos['preferred_date'] != null ? 'Reprogramează Vizită' : 'Programează Vizită',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 2,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _resolveAlert,
                  icon: const Icon(Icons.check_circle, size: 26),
                  label: const Text('Marchează ca Rezolvat', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 2,
                  ),
                ),
              ),
            ],
            
            // Informații programare (dacă există)
            if (_sos['appointment_date'] != null) ...[
              const SizedBox(height: 20),
              _buildSection(
                title: '📅 Programare Vizită',
                children: [
                  _buildInfoRow(
                    Icons.calendar_today,
                    'Data',
                    '${_sos['appointment_date']} ${_sos['appointment_time'] ?? ''}',
                  ),
                  if (_sos['appointment_notes'] != null && _sos['appointment_notes'].isNotEmpty)
                    _buildInfoRow(Icons.note, 'Notițe', _sos['appointment_notes']),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSection({required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: Colors.grey[700]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _callClient(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nu se poate inița apelul')),
        );
      }
    }
  }

  Future<void> _acceptClientDate() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('✅ Accept cu această dată'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Vei programa vizita pentru:'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green, width: 2),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, color: Colors.green),
                  const SizedBox(width: 8),
                  Text(
                    '📅 ${_sos['preferred_date']} la ${_sos['preferred_time'] ?? ''}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Clientul va fi notificat automat!',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anulează'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('✅ Confirmă'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isProcessing = true);
      
      try {
        // Programează cu data clientului
        await ApiService.scheduleInstallerSOS(
          _sos['id'],
          date: _sos['preferred_date'],
          time: _sos['preferred_time'] ?? '10:00',
          notes: 'Acceptat la data preferată de client',
        );
        
        setState(() {
          _sos['status'] = 'acknowledged';
          _sos['appointment_date'] = _sos['preferred_date'];
          _sos['appointment_time'] = _sos['preferred_time'];
          _sos['appointment_notes'] = 'Acceptat la data preferată de client';
          _isProcessing = false;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Vizită programată și clientul a fost notificat!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        setState(() => _isProcessing = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _acknowledgeAlert() async {
    setState(() => _isProcessing = true);
    
    try {
      await ApiService.acknowledgeInstallerSOS(_sos['id']);
      
      setState(() {
        _sos['status'] = 'acknowledged';
        _isProcessing = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SOS marcat ca preluat'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _scheduleVisit() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => _ScheduleVisitDialog(
        preferredDate: _sos['preferred_date'],
        preferredTime: _sos['preferred_time'],
      ),
    );
    
    if (result != null) {
      setState(() => _isProcessing = true);
      
      try {
        await ApiService.scheduleInstallerSOS(
          _sos['id'],
          date: result['date']!,
          time: result['time']!,
          notes: result['notes'],
        );
        
        setState(() {
          _sos['appointment_date'] = result['date'];
          _sos['appointment_time'] = result['time'];
          _sos['appointment_notes'] = result['notes'];
          _isProcessing = false;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Vizită programată și clientul a fost notificat'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        setState(() => _isProcessing = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _resolveAlert() async {
    final notesController = TextEditingController();
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Marchează ca Rezolvat'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Client: ${_sos['client_name']}'),
            const SizedBox(height: 16),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(
                labelText: 'Note rezolvare (opțional)',
                border: OutlineInputBorder(),
                hintText: 'Ex: Am înlocuit releul defect...',
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anulează'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Marchează Rezolvat'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isProcessing = true);
      
      try {
        await ApiService.resolveInstallerSOS(
          _sos['id'],
          notes: notesController.text.isNotEmpty ? notesController.text : null,
        );
        
        setState(() {
          _sos['status'] = 'resolved';
          _sos['resolved_at'] = DateTime.now().toIso8601String();
          _isProcessing = false;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('SOS marcat ca rezolvat'),
              backgroundColor: Colors.green,
            ),
          );
          
          // Revine la lista de mesaje
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) Navigator.pop(context);
          });
        }
      } catch (e) {
        setState(() => _isProcessing = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }
}

// Dialog pentru programare vizită
class _ScheduleVisitDialog extends StatefulWidget {
  final String? preferredDate;
  final String? preferredTime;
  
  const _ScheduleVisitDialog({this.preferredDate, this.preferredTime});
  
  @override
  State<_ScheduleVisitDialog> createState() => _ScheduleVisitDialogState();
}

class _ScheduleVisitDialogState extends State<_ScheduleVisitDialog> {
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    
    // ✅ PRE-COMPLETEAZĂ cu data preferată de client dacă există
    if (widget.preferredDate != null) {
      try {
        _selectedDate = DateTime.parse(widget.preferredDate!);
      } catch (e) {
        print('Error parsing preferred_date: $e');
      }
    }
    
    if (widget.preferredTime != null) {
      try {
        final parts = widget.preferredTime!.split(':');
        if (parts.length == 2) {
          _selectedTime = TimeOfDay(
            hour: int.parse(parts[0]),
            minute: int.parse(parts[1]),
          );
        }
      } catch (e) {
        print('Error parsing preferred_time: $e');
      }
    }
    
    // Adaugă notă dacă există dată preferată
    if (widget.preferredDate != null) {
      _notesController.text = 'Programat la data preferată de client';
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Programează Vizită'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Data
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today, color: Color(0xFF667eea)),
              title: const Text('Data vizitei'),
              subtitle: Text(
                _selectedDate != null
                    ? '${_selectedDate!.day}.${_selectedDate!.month}.${_selectedDate!.year}'
                    : 'Selectează data',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 90)),
                );
                if (date != null) {
                  setState(() => _selectedDate = date);
                }
              },
            ),
            
            const Divider(),
            
            // Ora
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.access_time, color: Color(0xFF667eea)),
              title: const Text('Ora vizitei'),
              subtitle: Text(
                _selectedTime != null
                    ? '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}'
                    : 'Selectează ora',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.now(),
                );
                if (time != null) {
                  setState(() => _selectedTime = time);
                }
              },
            ),
            
            const SizedBox(height: 16),
            
            // Note
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Note programare (opțional)',
                border: OutlineInputBorder(),
                hintText: 'Ex: Voi aduce piese de schimb...',
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Anulează'),
        ),
        ElevatedButton(
          onPressed: _selectedDate != null && _selectedTime != null
              ? () {
                  final dateStr = '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}';
                  final timeStr = '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}';
                  
                  Navigator.pop(context, {
                    'date': dateStr,
                    'time': timeStr,
                    'notes': _notesController.text,
                  });
                }
              : null,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
          child: const Text('Programează'),
        ),
      ],
    );
  }
}

