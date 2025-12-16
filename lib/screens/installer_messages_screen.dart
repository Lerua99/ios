import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'installer_sos_detail_screen.dart';
import 'installer_request_detail_screen.dart';

class InstallerMessagesScreen extends StatefulWidget {
  const InstallerMessagesScreen({Key? key}) : super(key: key);

  @override
  State<InstallerMessagesScreen> createState() => _InstallerMessagesScreenState();
}

class _InstallerMessagesScreenState extends State<InstallerMessagesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // SOS
  List<dynamic> _sosAlerts = [];
  bool _isLoadingSOS = true;
  int _sosUnreadCount = 0;
  
  // Installation Requests
  List<dynamic> _installRequests = [];
  bool _isLoadingRequests = true;
  int _requestsUnreadCount = 0;
  
  // Admin Messages
  List<dynamic> _adminMessages = [];
  bool _isLoadingAdmin = true;
  int _adminUnreadCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAllMessages();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllMessages() async {
    await Future.wait([
      _loadSOSAlerts(),
      _loadInstallationRequests(),
      _loadAdminMessages(),
    ]);
  }

  Future<void> _loadSOSAlerts() async {
    setState(() => _isLoadingSOS = true);
    try {
      final alerts = await ApiService.getInstallerSOS(status: null);
      setState(() {
        _sosAlerts = alerts;
        _sosUnreadCount = alerts.where((a) => a['status'] == 'pending').length;
        _isLoadingSOS = false;
      });
    } catch (e) {
      print('Error loading SOS: $e');
      setState(() => _isLoadingSOS = false);
    }
  }

  Future<void> _loadInstallationRequests() async {
    setState(() => _isLoadingRequests = true);
    try {
      final requests = await ApiService.getInstallationRequests();
      setState(() {
        _installRequests = requests;
        _requestsUnreadCount = requests.where((r) => r['status'] == 'pending').length;
        _isLoadingRequests = false;
      });
    } catch (e) {
      print('Error loading installation requests: $e');
      setState(() => _isLoadingRequests = false);
    }
  }

  Future<void> _loadAdminMessages() async {
    setState(() => _isLoadingAdmin = true);
    try {
      final messages = await ApiService.getAdminNotifications();
      setState(() {
        _adminMessages = messages;
        _adminUnreadCount = messages.where((m) => m['is_read'] == false).length;
        _isLoadingAdmin = false;
      });
    } catch (e) {
      print('Error loading admin messages: $e');
      setState(() => _isLoadingAdmin = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalUnread = _sosUnreadCount + _requestsUnreadCount + _adminUnreadCount;
    
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Mesaje', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            if (totalUnread > 0)
              Text(
                '$totalUnread necitite',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.normal),
              ),
          ],
        ),
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAllMessages,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.sos, size: 18),
                  const SizedBox(width: 6),
                  const Text('SOS'),
                  if (_sosUnreadCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$_sosUnreadCount',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.person_add, size: 18),
                  const SizedBox(width: 6),
                  const Text('Cereri'),
                  if (_requestsUnreadCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$_requestsUnreadCount',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.notifications, size: 18),
                  const SizedBox(width: 6),
                  const Text('Admin'),
                  if (_adminUnreadCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$_adminUnreadCount',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: SOS Alerts
          _buildSOSTab(),
          
          // Tab 2: Installation Requests
          _buildRequestsTab(),
          
          // Tab 3: Admin Messages
          _buildAdminTab(),
        ],
      ),
    );
  }

  // TAB 1: SOS ALERTS
  Widget _buildSOSTab() {
    if (_isLoadingSOS) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_sosAlerts.isEmpty) {
      return _buildEmptyState(
        icon: Icons.sos_outlined,
        title: 'Nu ai SOS-uri',
        subtitle: 'Clienții pot trimite SOS când au probleme tehnice',
      );
    }
    
    return RefreshIndicator(
      onRefresh: _loadSOSAlerts,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _sosAlerts.length,
        itemBuilder: (context, index) {
          final sos = _sosAlerts[index];
          return _buildSOSCard(sos);
        },
      ),
    );
  }

  Widget _buildSOSCard(Map<String, dynamic> sos) {
    final status = sos['status'] ?? 'pending';
    final isPending = status == 'pending';
    final isResolved = status == 'resolved';
    
    Color statusColor = isPending ? Colors.red : (isResolved ? Colors.green : Colors.orange);
    IconData statusIcon = isPending ? Icons.warning : (isResolved ? Icons.check_circle : Icons.access_time);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isPending ? 4 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isPending ? BorderSide(color: Colors.red, width: 2) : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => _openSOSDetail(sos),
        borderRadius: BorderRadius.circular(12),
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
                          sos['client_name'] ?? 'Client',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          sos['created_at_human'] ?? '',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Colors.grey[400]),
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
                  sos['problem_description'] ?? '',
                  style: const TextStyle(fontSize: 14),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // TAB 2: INSTALLATION REQUESTS
  Widget _buildRequestsTab() {
    if (_isLoadingRequests) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_installRequests.isEmpty) {
      return _buildEmptyState(
        icon: Icons.person_add_outlined,
        title: 'Nu ai cereri de instalare',
        subtitle: 'Clienții noi vor apărea aici',
      );
    }
    
    return RefreshIndicator(
      onRefresh: _loadInstallationRequests,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _installRequests.length,
        itemBuilder: (context, index) {
          final request = _installRequests[index];
          return _buildRequestCard(request);
        },
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> request) {
    final status = request['status'] ?? 'pending';
    final isPending = status == 'pending';
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isPending ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isPending ? BorderSide(color: Colors.orange, width: 2) : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => _openRequestDetail(request),
        borderRadius: BorderRadius.circular(12),
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
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.person_add, color: Colors.blue, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          request['name'] ?? 'Client Nou',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          request['phone'] ?? '',
                          style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                        ),
                      ],
                    ),
                  ),
                  if (isPending)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'NOU',
                        style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right, color: Colors.grey[400]),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${request['city'] ?? ''}, ${request['county'] ?? ''}',
                      style: TextStyle(fontSize: 13, color: Colors.grey[700]),
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

  // TAB 3: ADMIN MESSAGES
  Widget _buildAdminTab() {
    if (_isLoadingAdmin) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_adminMessages.isEmpty) {
      return _buildEmptyState(
        icon: Icons.notifications_outlined,
        title: 'Nu ai mesaje de la admin',
        subtitle: 'Mesajele importante vor apărea aici',
      );
    }
    
    return RefreshIndicator(
      onRefresh: _loadAdminMessages,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _adminMessages.length,
        itemBuilder: (context, index) {
          final message = _adminMessages[index];
          return _buildAdminCard(message);
        },
      ),
    );
  }

  Widget _buildAdminCard(Map<String, dynamic> message) {
    final isRead = message['is_read'] ?? false;
    final type = message['type'] ?? 'info';
    
    Color typeColor = _getTypeColor(type);
    IconData typeIcon = _getTypeIcon(type);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isRead ? 1 : 3,
      color: isRead ? Colors.white : Colors.blue[50],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _openAdminMessageDetail(message),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Stack(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: typeColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(typeIcon, color: typeColor, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message['title'] ?? 'Mesaj Admin',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          message['message'] ?? '',
                          style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          message['created_at_human'] ?? '',
                          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right, color: Colors.grey[400]),
                ],
              ),
              // Buton ștergere
              Positioned(
                top: -8,
                right: -8,
                child: IconButton(
                  icon: Icon(Icons.close, color: Colors.grey[400], size: 20),
                  onPressed: () => _deleteAdminMessage(message['id']),
                  tooltip: 'Șterge',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteAdminMessage(int messageId) async {
    try {
      await ApiService.deletePushNotification(messageId.toString());
      setState(() {
        _adminMessages.removeWhere((m) => m['id'] == messageId);
        _adminUnreadCount = _adminMessages.where((m) => m['is_read'] == false).length;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mesaj șters'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'success':
        return Colors.green;
      case 'warning':
        return Colors.orange;
      case 'danger':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'success':
        return Icons.check_circle;
      case 'warning':
        return Icons.warning;
      case 'danger':
        return Icons.error;
      default:
        return Icons.info;
    }
  }

  Widget _buildEmptyState({required IconData icon, required String title, required String subtitle}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _openSOSDetail(Map<String, dynamic> sos) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => InstallerSOSDetailScreen(sosData: sos),
      ),
    ).then((_) => _loadSOSAlerts()); // Reload după ce revine
  }

  void _openRequestDetail(Map<String, dynamic> request) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => InstallerRequestDetailScreen(requestData: request),
      ),
    ).then((_) => _loadInstallationRequests()); // Reload după ce revine
  }

  void _openAdminMessageDetail(Map<String, dynamic> message) async {
    // Marchează ca citit
    if (message['is_read'] == false) {
      try {
        await ApiService.markAdminNotificationRead(message['id']);
        setState(() {
          message['is_read'] = true;
          _adminUnreadCount = _adminMessages.where((m) => m['is_read'] == false).length;
        });
      } catch (e) {
        print('Error marking as read: $e');
      }
    }
    
    // Afișează dialog cu mesajul complet
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(_getTypeIcon(message['type'] ?? 'info'), 
                 color: _getTypeColor(message['type'] ?? 'info')),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message['title'] ?? 'Mesaj Admin',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message['message'] ?? '',
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 16),
              Text(
                'Trimis: ${message['created_at_human'] ?? ''}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Închide'),
          ),
        ],
      ),
    );
  }
}

