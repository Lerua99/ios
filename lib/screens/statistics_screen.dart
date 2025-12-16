import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';

enum StatisticsPeriod { today, thisWeek, thisMonth, thisYear, allTime }

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({Key? key}) : super(key: key);

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  StatisticsPeriod _selectedPeriod = StatisticsPeriod.today;
  Map<String, dynamic>? _statsData;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService.getGateStats(_periodParam(_selectedPeriod));
      if (res['success'] == true) {
        setState(() {
          _statsData = res;
          _loading = false;
        });
      } else {
        setState(() { _error = res['message'] ?? 'Eroare'; _loading = false; });
      }
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String _getPeriodName(StatisticsPeriod period) {
    switch (period) {
      case StatisticsPeriod.today:
        return 'Astăzi';
      case StatisticsPeriod.thisWeek:
        return 'Săptămâna aceasta';
      case StatisticsPeriod.thisMonth:
        return 'Luna aceasta';
      case StatisticsPeriod.thisYear:
        return 'Anul acesta';
      case StatisticsPeriod.allTime:
        return 'Tot timpul';
    }
  }

  Color _getSourceColor(String source) {
    final s = source.toLowerCase();
    if (s.contains('bluetooth') || s.contains('hopa')) return Colors.blue;
    if (s == 'app' || s.contains('aplicat')) return Colors.green;
    if (s.contains('link') || s.contains('oaspet') || s.contains('guest')) return Colors.cyan;
    if (s.contains('vocal') || s.contains('voice')) return Colors.purple;
    if (s.contains('timer') || s.contains('schedule')) return Colors.orange;
    return Colors.grey;
  }

  Icon _getSourceIcon(String source) {
    final s = source.toLowerCase();
    if (s.contains('bluetooth') || s.contains('hopa')) {
      return Icon(Icons.bluetooth, color: Colors.blue, size: 16);
    }
    if (s == 'app' || s.contains('aplicat')) {
      return Icon(Icons.phone_android, color: Colors.green, size: 16);
    }
    if (s.contains('link') || s.contains('oaspet') || s.contains('guest')) {
      return Icon(Icons.link, color: Colors.cyan, size: 16);
    }
    if (s.contains('vocal') || s.contains('voice')) {
      return Icon(Icons.mic, color: Colors.purple, size: 16);
    }
    if (s.contains('timer') || s.contains('schedule')) {
      return Icon(Icons.schedule, color: Colors.orange, size: 16);
    }
    return Icon(Icons.help_outline, color: Colors.grey, size: 16);
  }

  String _periodParam(StatisticsPeriod p) {
    switch (p) {
      case StatisticsPeriod.today:
        return 'today';
      case StatisticsPeriod.thisWeek:
        return 'week';
      case StatisticsPeriod.thisMonth:
        return 'month';
      case StatisticsPeriod.thisYear:
        return 'year';
      case StatisticsPeriod.allTime:
        return 'all';
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final deviceName = authService.userData?['device'] ?? 'Poartă Principală';
    final currentData = _statsData ?? {'total_cycles': 0, 'last_action': '-', 'history': []};

    if (_loading) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.teal)),
      );
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: Text(_error!, style: TextStyle(color: Colors.red))),
      );
    }

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
          deviceName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          // Status indicator
          Container(
            margin: EdgeInsets.all(20),
            padding: EdgeInsets.symmetric(vertical: 12, horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.2),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: Colors.green, width: 2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, color: Colors.green, size: 12),
                SizedBox(width: 8),
                Text(
                  'Online',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // Period selector
          Container(
            margin: EdgeInsets.symmetric(horizontal: 20),
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: StatisticsPeriod.values.length,
              itemBuilder: (context, index) {
                final period = StatisticsPeriod.values[index];
                final isSelected = period == _selectedPeriod;
                
                return Container(
                  margin: EdgeInsets.only(right: 12),
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _selectedPeriod = period;
                      });
                      _loadStats();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSelected ? Colors.teal : Colors.grey[800],
                      foregroundColor: isSelected ? Colors.white : Colors.grey[400],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    child: Text(
                      _getPeriodName(period),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          SizedBox(height: 30),

          // Statistics cards
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'STATISTICI',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                SizedBox(height: 15),
                
                // Stats rows
                _buildStatRow('Total cicluri', currentData['total_cycles'].toString(), Icons.repeat),
                _buildStatRow('Ultima acțiune', currentData['last_action'] ?? '-', Icons.access_time),
                _buildStatRow('Tip dispozitiv', 'Poartă', Icons.door_front_door),
              ],
            ),
          ),

          SizedBox(height: 30),

          // History section
          Expanded(
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ISTORIC RECENT',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  SizedBox(height: 15),
                  
                  Expanded(
                    child: ListView.builder(
                      itemCount: (currentData['history'] as List).length,
                      itemBuilder: (context, index) {
                        final action = (currentData['history'] as List)[index];
                        
                        return Container(
                          margin: EdgeInsets.only(bottom: 15),
                          padding: EdgeInsets.symmetric(horizontal: 15, vertical: 20),
                          constraints: BoxConstraints(minHeight: 118),
                          decoration: BoxDecoration(
                            color: Colors.grey[900],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[800]!, width: 1),
                          ),
                          child: Row(
                            children: [
                              // Success icon
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.check, color: Colors.green, size: 20),
                              ),
                              
                              SizedBox(width: 15),
                              
                              // Action details
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      action['action'],
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _getSourceIcon(action['source'] ?? ''),
                                        SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              action['source'] ?? 'necunoscut',
                              style: TextStyle(
                                color: _getSourceColor(action['source'] ?? ''),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.visible,
                            ),
                            if (action['user_name'] != null) ...[
                              SizedBox(height: 2),
                              Text(
                                action['user_name'].toString(),
                                style: TextStyle(
                                  color: _getSourceColor(action['source'] ?? '').withOpacity(0.8),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w400,
                                  height: 1.2,
                                ),
                                maxLines: 5,
                                overflow: TextOverflow.visible,
                                softWrap: true,
                              ),
                            ],
                          ],
                        ),
                      ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              
                              // Time
                              Text(
                                action['time'],
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, IconData icon) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey[500], size: 20),
          SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 16,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

} 