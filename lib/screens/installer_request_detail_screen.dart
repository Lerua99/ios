import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';

class InstallerRequestDetailScreen extends StatefulWidget {
  final Map<String, dynamic> requestData;
  
  const InstallerRequestDetailScreen({Key? key, required this.requestData}) : super(key: key);

  @override
  State<InstallerRequestDetailScreen> createState() => _InstallerRequestDetailScreenState();
}

class _InstallerRequestDetailScreenState extends State<InstallerRequestDetailScreen> {
  late Map<String, dynamic> _request;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _request = Map<String, dynamic>.from(widget.requestData);
  }

  @override
  Widget build(BuildContext context) {
    final clientName = _request['client_name'] ?? 'Client';
    final clientPhone = _request['client_phone'] ?? '';
    final clientEmail = _request['client_email'] ?? '';
    final address = _request['installation_address'] ?? '';
    final city = _request['city'] ?? '';
    final county = _request['county'] ?? '';
    final serviceType = _request['service_type'] ?? '';
    final status = _request['status'] ?? 'pending';
    final hoursRemaining = _request['hours_remaining'];

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Detalii Cerere Instalare'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF667eea), Color(0xFF764ba2)],
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
            // Deadline warning
            if (status == 'pending' && hoursRemaining != null && hoursRemaining < 24)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: hoursRemaining < 6 ? Colors.red[50] : Colors.orange[50],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: hoursRemaining < 6 ? Colors.red : Colors.orange,
                    width: 2,
                  ),
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
                            color: (hoursRemaining < 6 ? Colors.red : Colors.orange).withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.timer,
                        color: hoursRemaining < 6 ? Colors.red : Colors.orange,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        hoursRemaining < 1
                            ? 'URGENT: Expiră în mai puțin de 1 oră!'
                            : 'Răspunde în ${hoursRemaining.toInt()} ore',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: hoursRemaining < 6 ? Colors.red : Colors.orange,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            
            if (status == 'pending' && hoursRemaining != null && hoursRemaining < 24)
              const SizedBox(height: 20),
            
            // Informații Client
            _buildSection(
              title: '👤 Informații Client',
              children: [
                _buildInfoRow(Icons.person, 'Nume', clientName),
                if (clientPhone.isNotEmpty)
                  _buildInfoRow(Icons.phone, 'Telefon', clientPhone),
                if (clientEmail.isNotEmpty)
                  _buildInfoRow(Icons.email, 'Email', clientEmail),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Adresă instalare
            _buildSection(
              title: '📍 Adresă Instalare',
              children: [
                _buildInfoRow(Icons.home, 'Adresă', address),
                _buildInfoRow(Icons.location_city, 'Oraș', city),
                _buildInfoRow(Icons.map, 'Județ', county),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Tip serviciu
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🔧 Serviciu Solicitat',
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
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.blue.withOpacity(0.3), width: 1),
                  ),
                  child: Text(
                    _getServiceTypeLabel(serviceType),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Butoane acțiuni
            if (status == 'pending') ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: clientPhone.isNotEmpty ? () => _callClient(clientPhone) : null,
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
              
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _acceptRequest,
                  icon: _isProcessing
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.check_circle, size: 26),
                  label: const Text('Accept Cererea', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
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
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.green, width: 2),
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
                            color: Colors.green.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.check_circle, color: Colors.green, size: 28),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        'Cerere acceptată! Contactează clientul pentru detalii instalare.',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.green),
                      ),
                    ),
                  ],
                ),
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

  String _getServiceTypeLabel(String type) {
    switch (type) {
      case 'instalare_noua':
        return '🏗️ Instalare Nouă (Client nou)';
      case 'instalare_poarta':
        return '🚪 Instalare Poartă Suplimentară';
      case 'reparatie':
        return '🔧 Reparație/Service';
      default:
        return type;
    }
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

  Future<void> _acceptRequest() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmă Acceptarea'),
        content: Text(
          'Confirmi că vei contacta clientul ${_request['client_name']} pentru instalare?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anulează'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Accept'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isProcessing = true);
      
      try {
        await ApiService.acceptInstallationRequest(_request['id']);
        
        setState(() {
          _request['status'] = 'accepted';
          _isProcessing = false;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cerere acceptată! Contactează clientul pentru programare.'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
          
          // Revine la lista de mesaje
          Future.delayed(const Duration(seconds: 2), () {
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

