import 'package:flutter/material.dart';
import '../models/shelly_device.dart';
import '../services/shelly_service.dart';

class ShellyDeviceDetailScreen extends StatefulWidget {
  final ShellyDevice device;
  final ShellyService shellyService;

  const ShellyDeviceDetailScreen({
    Key? key,
    required this.device,
    required this.shellyService,
  }) : super(key: key);

  @override
  State<ShellyDeviceDetailScreen> createState() => _ShellyDeviceDetailScreenState();
}

class _ShellyDeviceDetailScreenState extends State<ShellyDeviceDetailScreen> {
  bool _isLoadingHistory = true;
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final history = await widget.shellyService.getDeviceHistory(widget.device.id);
      setState(() {
        _history = history;
        _isLoadingHistory = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingHistory = false;
      });
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
        title: Text(
          widget.device.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Card
            Card(
              color: Colors.grey[900],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(
                      widget.device.iconData,
                      size: 64,
                      color: widget.device.isOnline ? Colors.blue : Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.device.displayStatus,
                      style: TextStyle(
                        color: widget.device.isOpen ? Colors.green : Colors.orange,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.device.isOnline ? 'Online' : 'Offline',
                      style: TextStyle(
                        color: widget.device.isOnline ? Colors.green : Colors.red,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Statistici
            Text(
              'STATISTICI',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 16),
            _buildInfoRow('Total cicluri', widget.device.totalCycles.toString()),
            _buildInfoRow('Ultima acțiune', widget.device.lastActionAt ?? 'Niciodată'),
            _buildInfoRow('Tip dispozitiv', widget.device.typeLabel),
            
            const SizedBox(height: 32),
            
            // Istoric
            Text(
              'ISTORIC RECENT',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 16),
            
            if (_isLoadingHistory)
              Center(
                child: CircularProgressIndicator(color: Colors.blue),
              )
            else if (_history.isEmpty)
              Center(
                child: Text(
                  'Niciun eveniment recent',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              ..._history.take(10).map((log) => _buildHistoryItem(log)).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 16,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(Map<String, dynamic> log) {
    final success = log['success'] ?? false;
    final action = log['action_label'] ?? log['action'];
    final trigger = log['trigger_label'] ?? log['trigger'];
    final time = log['created_at'] ?? '';

    return Card(
      color: Colors.grey[850],
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          success ? Icons.check_circle : Icons.error,
          color: success ? Colors.green : Colors.red,
        ),
        title: Text(
          action,
          style: const TextStyle(color: Colors.white),
        ),
        subtitle: Text(
          trigger,
          style: TextStyle(color: Colors.grey[400]),
        ),
        trailing: Text(
          time,
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
        ),
      ),
    );
  }
} 