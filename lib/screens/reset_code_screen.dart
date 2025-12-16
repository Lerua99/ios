import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ResetCodeScreen extends StatefulWidget {
  const ResetCodeScreen({Key? key}) : super(key: key);

  @override
  State<ResetCodeScreen> createState() => _ResetCodeScreenState();
}

class _ResetCodeScreenState extends State<ResetCodeScreen> {
  final _emailController = TextEditingController();
  bool _isLoading = false;
  String _message = '';

  Future<void> _requestCode() async {
    setState(() {
      _isLoading = true;
      _message = '';
    });

    try {
      final response = await ApiService.requestActivationCode(_emailController.text.trim());
      if (response['success'] == true) {
        setState(() {
          _message = '📧 Codul existent a fost trimis pe email! Verifică inbox-ul.';
        });
      } else {
        setState(() {
          _message = response['message'] ?? 'Eroare neașteptată';
        });
      }
    } catch (e) {
      setState(() {
        _message = 'Eroare: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _regenerateCode() async {
    setState(() {
      _isLoading = true;
      _message = '';
    });

    try {
      final response = await ApiService.regenerateActivationCode(_emailController.text.trim());
      if (response['success'] == true) {
        setState(() {
          _message = '🔄 Un cod NOU a fost generat și trimis pe email!';
        });
      } else {
        setState(() {
          _message = response['message'] ?? 'Eroare neașteptată';
        });
      }
    } catch (e) {
      setState(() {
        _message = 'Eroare: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recuperează / generează cod'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email folosit la crearea contului',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _requestCode,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('📧 Trimite codul existent', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _isLoading ? null : _regenerateCode,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('🔄 Generează cod NOU', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 24),
            if (_message.isNotEmpty)
              Text(
                _message,
                style: TextStyle(
                  color: (_message.startsWith('📧') || _message.startsWith('🔄')) ? Colors.green : Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ),
    );
  }
} 