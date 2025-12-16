import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/notification_service.dart';

class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

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
        title: const Row(
          children: [
            Icon(Icons.notifications, color: Colors.amber),
            SizedBox(width: 8),
            Text('Setări Notificări', style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Consumer<NotificationService>(
            builder: (context, notificationService, _) {
              return Column(
                children: [
                  // Rândul 1
                  Row(
                    children: [
                      Expanded(
                        child: _buildCompactCard(
                          icon: Icons.notifications_active,
                          color: Colors.teal,
                          title: 'Push',
                          subtitle: 'Toate notificările',
                          value: notificationService.pushNotifications,
                          onChanged: (v) => notificationService.setPushNotifications(v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildCompactCard(
                          icon: Icons.groups,
                          color: Colors.lightBlue,
                          title: 'Familie',
                          subtitle: 'Deschidere poartă',
                          value: notificationService.familyNotifications,
                          onChanged: (v) => notificationService.setFamilyNotifications(v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Rândul 2
                  Row(
                    children: [
                      Expanded(
                        child: _buildCompactCard(
                          icon: Icons.warning_amber_rounded,
                          color: Colors.orange,
                          title: 'Tehnice',
                          subtitle: 'Probleme dispozitiv',
                          value: notificationService.technicalProblems,
                          onChanged: (v) => notificationService.setTechnicalProblems(v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildCompactCard(
                          icon: Icons.build,
                          color: Colors.green,
                          title: 'Service',
                          subtitle: 'Cicluri completate',
                          value: notificationService.serviceRequired,
                          onChanged: (v) => notificationService.setServiceRequired(v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Rândul 3
                  Row(
                    children: [
                      Expanded(
                        child: _buildCompactCard(
                          icon: Icons.campaign,
                          color: Colors.purple,
                          title: 'Marketing',
                          subtitle: 'Oferte & reduceri',
                          value: notificationService.marketingNotifications,
                          onChanged: (v) => notificationService.setMarketingNotifications(v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildCompactCard(
                          icon: Icons.assistant,
                          color: Colors.cyan,
                          title: 'Assistant',
                          subtitle: 'Comenzi vocale',
                          value: notificationService.voiceCommands,
                          onChanged: (v) => notificationService.setVoiceCommands(v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  // Buton Salvează cu confirmare
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        // Arată confirmare și rămâne în ecran
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Row(
                              children: [
                                Icon(Icons.check_circle, color: Colors.white),
                                SizedBox(width: 12),
                                Text('Setări salvate cu succes!'),
                              ],
                            ),
                            backgroundColor: Colors.green,
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        );
                        // Așteaptă 1 secundă apoi închide
                        Future.delayed(Duration(seconds: 1), () {
                          if (context.mounted) {
                            Navigator.pop(context);
                          }
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: const Text(
                        'Salvează',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  static Widget _buildCompactCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return Container(
      height: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Transform.scale(
            scale: 0.8,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeColor: color,
            ),
          ),
        ],
      ),
    );
  }
}

