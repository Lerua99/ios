import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'technician_activity_screen.dart';

class InstallerEmployeesScreen extends StatefulWidget {
  const InstallerEmployeesScreen({Key? key}) : super(key: key);

  @override
  State<InstallerEmployeesScreen> createState() => _InstallerEmployeesScreenState();
}

class _InstallerEmployeesScreenState extends State<InstallerEmployeesScreen> {
  List<dynamic> _technicians = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTechnicians();
  }

  Future<void> _loadTechnicians() async {
    setState(() => _isLoading = true);
    try {
      final technicians = await ApiService.getInstallerEmployees();
      setState(() {
        _technicians = technicians;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading technicians: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare: $e')),
        );
      }
    }
  }

  Future<void> _showAddTechnicianDialog() async {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Adaugă Tehnician'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Nume Complet',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Telefon',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anulează'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isEmpty || 
                  emailController.text.isEmpty || 
                  phoneController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Completează toate câmpurile')),
                );
                return;
              }

              try {
                final result = await ApiService.addEmployee({
                  'name': nameController.text,
                  'email': emailController.text,
                  'phone': phoneController.text,
                });

                if (result['success'] == true) {
                  if (context.mounted) {
                    Navigator.pop(context, true);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Tehnician adăugat! Cod: ${result['installer_code']}'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Eroare: $e')),
                  );
                }
              }
            },
            child: const Text('Adaugă'),
          ),
        ],
      ),
    );

    if (result == true) {
      _loadTechnicians();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Tehnicienii Mei'),
        backgroundColor: const Color(0xFF4e73df),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTechnicians,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _technicians.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadTechnicians,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _technicians.length,
                    itemBuilder: (context, index) {
                      final technician = _technicians[index];
                      return _buildTechnicianCard(technician);
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddTechnicianDialog,
        icon: const Icon(Icons.person_add),
        label: const Text('Adaugă Tehnician'),
        backgroundColor: const Color(0xFF4e73df),
      ),
    );
  }

  Widget _buildTechnicianCard(Map<String, dynamic> technician) {
    final name = technician['name'] ?? 'N/A';
    final email = technician['email'] ?? 'N/A';
    final code = technician['code'] ?? 'N/A';
    final clientsCount = technician['clients_count'] ?? 0;
    final isActive = technician['is_active'] ?? true;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
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
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.work, color: Colors.orange),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        email,
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isActive 
                        ? Colors.green.withOpacity(0.1) 
                        : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isActive ? 'Activ' : 'Suspendat',
                    style: TextStyle(
                      fontSize: 12,
                      color: isActive ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            Row(
              children: [
                _buildInfoChip('Cod: $code', Icons.key, Colors.blue),
                const SizedBox(width: 8),
                _buildInfoChip('$clientsCount clienți', Icons.people, Colors.green),
              ],
            ),
            
            const SizedBox(height: 12),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TechnicianActivityScreen(
                          technicianId: technician['id'],
                          technicianName: name,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.analytics, size: 18),
                  label: const Text('Vezi Activitate'),
                  style: TextButton.styleFrom(foregroundColor: Colors.blue),
                ),
                const SizedBox(width: 8),
                if (isActive)
                  TextButton.icon(
                    onPressed: () => _suspendTechnician(technician),
                    icon: const Icon(Icons.pause, size: 18),
                    label: const Text('Suspendă'),
                    style: TextButton.styleFrom(foregroundColor: Colors.orange),
                  )
                else
                  TextButton.icon(
                    onPressed: () => _activateTechnician(technician),
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Activează'),
                    style: TextButton.styleFrom(foregroundColor: Colors.green),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(String text, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Future<void> _suspendTechnician(Map<String, dynamic> technician) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Suspendă Tehnician'),
        content: Text('Sigur vrei să suspenzi pe ${technician['name']}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anulează'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Suspendă'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ApiService.suspendEmployee(technician['id']);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tehnician suspendat'), backgroundColor: Colors.orange),
          );
        }
        _loadTechnicians();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Eroare: $e')),
          );
        }
      }
    }
  }

  Future<void> _activateTechnician(Map<String, dynamic> technician) async {
    try {
      await ApiService.activateEmployee(technician['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tehnician activat'), backgroundColor: Colors.green),
        );
      }
      _loadTechnicians();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare: $e')),
        );
      }
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.work_outline, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text(
            'Nu ai tehnicieni',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Apasă butonul + pentru a adăuga primul tehnician',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}








