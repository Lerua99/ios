import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/shelly_device.dart';
import '../services/auth_service.dart';
import '../services/shelly_service.dart';
import 'shelly_device_detail_screen.dart';
import '../config/api_config.dart';

class ShellyDevicesScreen extends StatefulWidget {
  const ShellyDevicesScreen({Key? key}) : super(key: key);

  @override
  State<ShellyDevicesScreen> createState() => _ShellyDevicesScreenState();
}

class _ShellyDevicesScreenState extends State<ShellyDevicesScreen> {
  late ShellyService _shellyService;
  List<ShellyDevice> _devices = [];
  bool _isLoading = true;
  String? _error;
  bool _isNavigating = false; // Previne click în timpul navigării

  @override
  void initState() {
    super.initState();
    _initializeService();
    _loadDevices();
  }

  void _initializeService() {
    final authService = Provider.of<AuthService>(context, listen: false);
    _shellyService = ShellyService(
      baseUrl: ApiConfig.baseUrl,
      authService: authService,
    );
  }

  Future<void> _loadDevices() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final devices = await _shellyService.getDevices();
      setState(() {
        _devices = devices;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  // Track pentru fiecare dispozitiv dacă e în procesare
  final Map<int, bool> _controllingDevices = {};

  Future<void> _controlDevice(ShellyDevice device, String action) async {
    // Previne double-tap pe butonul de control
    if (_controllingDevices[device.id] == true) return;
    
    if (!device.canControl) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Dispozitivul nu poate fi controlat acum'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _controllingDevices[device.id] = true;
    });

    HapticFeedback.mediumImpact();

    try {
      final result = await _shellyService.controlDevice(device.id, action);
      
      if (result['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Comandă trimisă cu succes!'),
              backgroundColor: Colors.green,
            ),
          );
        }
        
        // Reîncarcă dispozitivele după 2 secunde
        Future.delayed(Duration(seconds: 2), () {
          if (mounted) {
            _loadDevices();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Eroare: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _controllingDevices[device.id] = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Control Inteligent Porți',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadDevices,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: Colors.blue,
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 64,
            ),
            SizedBox(height: 16),
            Text(
              'Eroare la încărcare',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(
                color: Colors.grey,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadDevices,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
              ),
              child: Text('Reîncearcă'),
            ),
          ],
        ),
      );
    }

    if (_devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.device_unknown,
              color: Colors.grey,
              size: 64,
            ),
            SizedBox(height: 16),
            Text(
              'Nu ai dispozitive Shelly',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Contactează instalatorul pentru a adăuga',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadDevices,
      color: Colors.blue,
      backgroundColor: Colors.grey[900],
      child: ListView.builder(
        padding: EdgeInsets.all(16),
        itemCount: _devices.length,
        itemBuilder: (context, index) {
          final device = _devices[index];
          return _buildDeviceCard(device);
        },
      ),
    );
  }

  Widget _buildDeviceCard(ShellyDevice device) {
    final statusColor = device.isOpen ? Colors.green : Colors.orange;
    final canControl = device.isOnline && device.canControl;

    return Card(
      color: Colors.grey[900],
      margin: EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: _isNavigating ? null : () async {
          if (_isNavigating) return;
          setState(() {
            _isNavigating = true;
          });
          
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ShellyDeviceDetailScreen(
                device: device,
                shellyService: _shellyService,
              ),
            ),
          );
          
          if (mounted) {
            setState(() {
              _isNavigating = false;
            });
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              // Header
              Row(
                children: [
                  // Icon
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: device.isOnline 
                        ? Colors.blue.withOpacity(0.2)
                        : Colors.grey.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      device.iconData,
                      color: device.isOnline ? Colors.blue : Colors.grey,
                      size: 28,
                    ),
                  ),
                  SizedBox(width: 16),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device.name,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                device.displayStatus,
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            SizedBox(width: 8),
                            if (!device.isOnline)
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'Offline',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Control button
                  if (canControl)
                    IconButton(
                      onPressed: (_controllingDevices[device.id] == true) 
                        ? null 
                        : () => _controlDevice(device, 'toggle'),
                      icon: (_controllingDevices[device.id] == true)
                        ? SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: statusColor,
                            ),
                          )
                        : Icon(
                            device.isOpen ? Icons.lock_open : Icons.lock,
                            color: statusColor,
                            size: 32,
                          ),
                      style: IconButton.styleFrom(
                        backgroundColor: statusColor.withOpacity(0.1),
                      ),
                    ),
                ],
              ),
              // Stats
              SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStat('Cicluri', device.totalCycles.toString()),
                  _buildStat('Ultima acțiune', device.lastActionAt ?? 'Niciodată'),
                  _buildStat('Tip', device.typeLabel),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey,
            fontSize: 12,
          ),
        ),
        SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
} 