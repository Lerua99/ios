import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import 'installer_clients_screen.dart';
import 'installer_employees_screen.dart';
import 'installer_sos_screen.dart';
import 'installer_add_client_screen.dart';
import 'installer_requests_screen.dart';
import 'installer_messages_screen.dart';

class InstallerDashboardScreen extends StatefulWidget {
  const InstallerDashboardScreen({Key? key}) : super(key: key);

  @override
  State<InstallerDashboardScreen> createState() => _InstallerDashboardScreenState();
}

class _InstallerDashboardScreenState extends State<InstallerDashboardScreen> {
  Map<String, dynamic>? _stats;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final stats = await ApiService.getInstallerStats();
      setState(() {
        _stats = stats['data'];
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading stats: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final userData = authService.userData;
    final companyName = userData?['company_name'] ?? 'Instalator';
    
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Dashboard Instalator', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text(
              companyName,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
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
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStats,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStats,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Statistici Cards
                    _buildStatsCards(),
                    
                    const SizedBox(height: 24),
                    
                    // Acțiuni Rapide
                    const Text(
                      '🚀 Acțiuni Rapide',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF4e73df),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildQuickActions(),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildStatsCards() {
    final totalClients = _stats?['total_clients'] ?? 0;
    final installationsMonth = _stats?['installations_this_month'] ?? 0;
    final sosActive = _stats?['sos_active'] ?? 0;
    final employeesCount = _stats?['employees_count'] ?? 0;
    final installationRequests = _stats?['installation_requests_pending'] ?? 0;

    // Verifică dacă e TEHNICIAN (sub-instalator)
    final authService = Provider.of<AuthService>(context, listen: false);
    final installer = authService.userData?['installer'];
    final parentId = installer?['parent_installer_id'];
    final isTechnician = installer?['is_technician'] == true || parentId != null;
    
    // DEBUG temporar - să vedem ce primește
    print('🔍 DASHBOARD CHECK:');
    print('   User: ${authService.userData?['name'] ?? 'NO NAME'}');
    print('   Role: ${authService.userData?['role'] ?? 'NO ROLE'}');
    print('   Full UserData: ${authService.userData}');
    print('   Installer data: $installer');
    print('   Parent ID: $parentId');
    print('   Is Technician: $isTechnician');

    return Column(
      children: [
        // CERERI NOI - doar pentru PATRON
        if (!isTechnician) ...[
          _buildRequestsCard(installationRequests),
          const SizedBox(height: 12),
        ],
        
        
        // TEHNICIAN: 3 carduri full width
        if (isTechnician) ...[
          _buildStatCard(
            '👥 Clienți',
            '$totalClients',
            const Color(0xFF4776E6),
            Icons.people,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const InstallerClientsScreen()),
              );
            },
          ),
          const SizedBox(height: 12),
          _buildStatCard(
            '📅 Instalări',
            '$installationsMonth',
            const Color(0xFF11998e),
            Icons.calendar_today,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const InstallerClientsScreen()),
              );
            },
          ),
          const SizedBox(height: 12),
          _buildStatCard(
            '🚨 SOS',
            '$sosActive',
            sosActive > 0 ? const Color(0xFFe74c3c) : Colors.grey,
            Icons.warning,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const InstallerSOSScreen()),
              );
            },
          ),
        ],
        
        // PATRON: 2x2 grid
        if (!isTechnician) ...[
          // Rând 1: Clienți + Instalări Luna
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  '👥 Clienți',
                  '$totalClients',
                  const Color(0xFF4776E6),
                  Icons.people,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const InstallerClientsScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  '📅 Instalări',
                  '$installationsMonth',
                  const Color(0xFF11998e),
                  Icons.calendar_today,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const InstallerClientsScreen()),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Rând 2: SOS Active + Tehnicieni
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  '🚨 SOS',
                  '$sosActive',
                  sosActive > 0 ? const Color(0xFFe74c3c) : Colors.grey,
                  Icons.warning,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const InstallerSOSScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  '👷 Tehnicieni',
                  '$employeesCount',
                  const Color(0xFFf39c12),
                  Icons.engineering,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const InstallerEmployeesScreen()),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // Card special pentru Cereri Noi (între clopoțel și 0)
  Widget _buildRequestsCard(int requests) {
    final color = requests > 0 ? const Color(0xFF764ba2) : Colors.grey;
    return Container(
      height: 90, // Mai mic decât celelalte
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.8), color],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Icon clopoțel stânga
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.notifications_active, color: Colors.white, size: 24),
            ),
            // Text central
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'NEW',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Cereri Noi',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            // Număr în cerc alb dreapta
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  '$requests',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color color, IconData icon, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 110, // Card-uri mai mici (era implicit mai mare)
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withOpacity(0.8), color],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16), // Mai rotunjit
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 10, // Mai puțin blur
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Card(
          margin: EdgeInsets.zero,
          color: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(14), // Mai puțin padding
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: Colors.white, size: 28),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildQuickActions() {
    final canCreateSubInstallers = _stats?['is_principal'] ?? false;
    final installationRequests = _stats?['installation_requests_pending'] ?? 0;
    final sosActive = _stats?['sos_active'] ?? 0;
    final totalUnread = (installationRequests + sosActive); // Poți adăuga și admin messages count
    
    return Column(
      children: [
        // MESAJE (nou) - apare PRIMUL cu badge pentru necitite
        _buildActionButton(
          '💬 Mesaje',
          totalUnread > 0 ? '$totalUnread necitite' : 'SOS, Cereri, Notificări',
          Icons.message,
          totalUnread > 0 ? Colors.red : Colors.indigo,
          () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const InstallerMessagesScreen()),
            );
          },
          badge: totalUnread > 0 ? totalUnread : null,
        ),
        const SizedBox(height: 12),
        
        // Cereri Instalare NOI - apare AL DOILEA dacă există cereri
        if (installationRequests > 0) ...[
          _buildActionButton(
            '🆕 Cereri Instalare ($installationRequests)',
            'Clienți noi te așteaptă!',
            Icons.notification_important,
            Colors.purple,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const InstallerRequestsScreen()),
              );
            },
          ),
          const SizedBox(height: 12),
        ],
        _buildActionButton(
          '+ Adaugă Client',
          'Instalează un client nou',
          Icons.person_add,
          Colors.blue,
          () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const InstallerAddClientScreen()),
            );
          },
        ),
        const SizedBox(height: 12),
        _buildActionButton(
          '👥 Vezi Clienți',
          'Lista completă clienți',
          Icons.list,
          Colors.green,
          () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const InstallerClientsScreen()),
            );
          },
        ),
        if (canCreateSubInstallers) ...[
          const SizedBox(height: 12),
          _buildActionButton(
            '👷 Tehnicienii Mei',
            'Gestionează echipa',
            Icons.engineering,
            Colors.orange,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const InstallerEmployeesScreen()),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildActionButton(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap, {
    int? badge,
  }) {
    // Gradient special pentru "Cereri Instalare" - VIOLET PUTERNIC
    final isNewRequest = title.contains('Cereri Instalare');
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: isNewRequest
              ? const LinearGradient(
                  colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : LinearGradient(
                  colors: [Colors.white, Colors.white],
                ),
          borderRadius: BorderRadius.circular(16),
          border: isNewRequest ? null : Border.all(color: Colors.grey[200]!, width: 1),
          boxShadow: [
            BoxShadow(
              color: isNewRequest ? Colors.purple.withOpacity(0.4) : Colors.black.withOpacity(0.05),
              blurRadius: isNewRequest ? 20 : 10,
              offset: Offset(0, isNewRequest ? 8 : 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isNewRequest ? Colors.white.withOpacity(0.25) : color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: isNewRequest ? [
                      BoxShadow(
                        color: Colors.white.withOpacity(0.3),
                        blurRadius: 8,
                      ),
                    ] : null,
                  ),
                  child: Icon(icon, color: isNewRequest ? Colors.white : color, size: 28),
                ),
                if (badge != null && badge > 0)
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 22,
                        minHeight: 22,
                      ),
                      child: Text(
                        badge > 99 ? '99+' : '$badge',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: isNewRequest ? Colors.white : Colors.black87,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: isNewRequest ? Colors.white.withOpacity(0.9) : Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: isNewRequest ? Colors.white : Colors.grey[400],
              size: 30,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: 0,
      selectedItemColor: const Color(0xFF4e73df),
      unselectedItemColor: Colors.grey,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.people),
          label: 'Clienți',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.engineering),
          label: 'Tehnicieni',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.sos),
          label: 'SOS',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.settings),
          label: 'Setări',
        ),
      ],
      onTap: (index) {
        // Navigate to different screens
        switch (index) {
          case 0:
            // Already on home
            break;
          case 1:
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const InstallerClientsScreen()),
            );
            break;
          case 2:
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const InstallerEmployeesScreen()),
            );
            break;
          case 3:
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const InstallerSOSScreen()),
            );
            break;
          case 4:
          // Logout
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Deconectare'),
              content: const Text('Sigur vrei să te deconectezi?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Anulează'),
                ),
                TextButton(
                  onPressed: () async {
                    await Provider.of<AuthService>(context, listen: false).logout();
                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Deconectare', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          );
            break;
        }
      },
    );
  }
}

