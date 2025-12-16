import 'package:flutter/material.dart';

class ShellyDevice {
  final int id;
  final String name;
  final String type;
  final String typeLabel;
  final String status;
  final String statusIcon;
  final bool isOnline;
  final bool canControl;
  final int totalCycles;
  final String? lastActionAt;
  final Map<String, dynamic>? settings;

  ShellyDevice({
    required this.id,
    required this.name,
    required this.type,
    required this.typeLabel,
    required this.status,
    required this.statusIcon,
    required this.isOnline,
    required this.canControl,
    required this.totalCycles,
    this.lastActionAt,
    this.settings,
  });

  factory ShellyDevice.fromJson(Map<String, dynamic> json) {
    return ShellyDevice(
      id: json['id'],
      name: json['name'],
      type: json['type'],
      typeLabel: json['type_label'],
      status: json['status'],
      statusIcon: json['status_icon'],
      isOnline: json['is_online'],
      canControl: json['can_control'],
      totalCycles: json['total_cycles'],
      lastActionAt: json['last_action_at'],
      settings: json['settings'],
    );
  }

  bool get isOpen => status == 'open';
  bool get isClosed => status == 'closed';
  bool get isMoving => status == 'opening' || status == 'closing';
  
  String get displayStatus {
    switch (status) {
      case 'open':
        return 'Deschisă';
      case 'closed':
        return 'Închisă';
      case 'opening':
        return 'Se deschide...';
      case 'closing':
        return 'Se închide...';
      default:
        return 'Necunoscut';
    }
  }

  IconData get iconData {
    switch (type) {
      case 'gate':
        return Icons.door_front_door;
      case 'garage':
        return Icons.garage;
      case 'barrier':
        return Icons.block;
      case 'door':
        return Icons.sensor_door;
      default:
        return Icons.device_unknown;
    }
  }
} 