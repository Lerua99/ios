import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'package:url_launcher/url_launcher.dart';

class InstallerSOSScreen extends StatefulWidget {
  const InstallerSOSScreen({Key? key}) : super(key: key);

  @override
  State<InstallerSOSScreen> createState() => _InstallerSOSScreenState();
}

class _InstallerSOSScreenState extends State<InstallerSOSScreen> {
  List<dynamic> _sosAlerts = [];
  bool _isLoading = true;
  String _filter = 'all'; // 'all', 'pending', 'resolved'

  @override
  void initState() {
    super.initState();
    _loadSOSAlerts();
  }

  Future<void> _loadSOSAlerts() async {
    setState(() => _isLoading = true);
    try {
      final status = _filter == 'all' ? null : _filter;
      
      print('🔵 FLUTTER - Încarc SOS-uri cu filtru: $status');
      final alerts = await ApiService.getInstallerSOS(status: status);
      
      print('✅ FLUTTER - Am primit ${alerts.length} SOS-uri');
      if (alerts.isNotEmpty) {
        print('📋 SOS-uri primite:');
        for (var sos in alerts) {
          print('  - ID: ${sos['id']}, Client: ${sos['client_name']}, Status: ${sos['status']}');
        }
      }
      
      setState(() {
        _sosAlerts = alerts;
        _isLoading = false;
      });
    } catch (e) {
      print('🔴 FLUTTER - Error loading SOS alerts: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _sosAlerts.where((s) => s['status'] == 'pending').length;
    
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('SOS Alerts'),
            if (pendingCount > 0)
              Text(
                '$pendingCount active',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
              ),
          ],
        ),
        backgroundColor: Colors.red[700],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSOSAlerts,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Chips
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.white,
            child: Row(
              children: [
                _buildFilterChip('Toate', 'all'),
                const SizedBox(width: 8),
                _buildFilterChip('Pending', 'pending'),
                const SizedBox(width: 8),
                _buildFilterChip('Rezolvate', 'resolved'),
              ],
            ),
          ),
          
          // SOS List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _sosAlerts.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadSOSAlerts,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _sosAlerts.length,
                          itemBuilder: (context, index) {
                            final alert = _sosAlerts[index];
                            return _buildSOSCard(alert);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filter == value;
    
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _filter = value);
          _loadSOSAlerts();
        }
      },
      selectedColor: Colors.red[700],
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildSOSCard(Map<String, dynamic> alert) {
    final clientName = alert['client_name'] ?? 'N/A';
    final clientPhone = alert['client_phone'] ?? '';
    final problem = alert['problem_description'] ?? 'N/A';
    final status = alert['status'] ?? 'pending';
    final createdAt = alert['created_at_human'] ?? 'N/A';
    final installedBy = alert['installed_by']; // Dacă e de la angajat

    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (status) {
      case 'pending':
        statusColor = Colors.red;
        statusIcon = Icons.warning;
        statusText = 'URGENT';
        break;
      case 'acknowledged':
        statusColor = Colors.orange;
        statusIcon = Icons.access_time;
        statusText = 'În progres';
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

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: status == 'pending' ? 4 : 2,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: status == 'pending' 
              ? Border.all(color: Colors.red, width: 2)
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(statusIcon, color: statusColor, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          clientName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          createdAt,
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 12,
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  problem,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              
              if (installedBy != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.work, size: 14, color: Colors.orange),
                    const SizedBox(width: 6),
                    Text(
                      'Instalat de: $installedBy',
                      style: const TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ],
                ),
              ],
              
              const SizedBox(height: 12),
              
              Row(
                children: [
                  if (clientPhone.isNotEmpty)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _callClient(clientPhone),
                        icon: const Icon(Icons.phone, size: 18),
                        label: const Text('Sună'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  if (clientPhone.isNotEmpty) const SizedBox(width: 8),
                  if (status != 'resolved')
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _resolveAlert(alert),
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Rezolvă'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
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

  Future<void> _resolveAlert(Map<String, dynamic> alert) async {
    final notesController = TextEditingController();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Marchează ca Rezolvat'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Client: ${alert['client_name']}'),
            const SizedBox(height: 12),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(
                labelText: 'Note rezolvare (opțional)',
                border: OutlineInputBorder(),
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
            child: const Text('Marchează Rezolvat'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ApiService.resolveInstallerSOS(
          alert['id'],
          notes: notesController.text.isNotEmpty ? notesController.text : null,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('SOS marcat ca rezolvat'), backgroundColor: Colors.green),
          );
        }
        _loadSOSAlerts();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Eroare: $e')),
          );
        }
      }
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _filter == 'resolved' ? Icons.check_circle_outline : Icons.sos_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            _filter == 'resolved' 
                ? 'Nu ai SOS-uri rezolvate'
                : 'Nu ai SOS-uri active',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            _filter == 'all'
                ? 'Nu există nicio alertă SOS'
                : 'Schimbă filtrul pentru a vedea alte alerte',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}















