import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import 'gate_control_screen.dart';
import '../widgets/logo_widget.dart';

class ProvisionWaitScreen extends StatefulWidget {
  const ProvisionWaitScreen({super.key});

  @override
  State<ProvisionWaitScreen> createState() => _ProvisionWaitScreenState();
}

class _ProvisionWaitScreenState extends State<ProvisionWaitScreen> {
  bool _provisioned = false;
  bool _error = false;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _checkStatus();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _checkStatus());
  }

  Future<void> _checkStatus() async {
    try {
      final res = await ApiService.getGateStatus();
      if (res['provisioned'] == true) {
        if (mounted) {
          setState(() {
            _provisioned = true;
          });
          _timer.cancel();
          // Navighează la ecranul principal
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const GateControlScreen()),
          );
        }
      }
    } catch (_) {
      setState(() => _error = true);
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LogoWidget(size: 90, showText: false),
            const SizedBox(height: 30),
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 20),
            Text(
              _error ? 'Eroare conexiune. Reîncerc...' : 'Se configurează dispozitivul...',
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
} 