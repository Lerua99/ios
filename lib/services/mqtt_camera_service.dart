import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/// Service MQTT pentru streaming cameră ESP32-CAM prin EMQX
///
/// Utilizare:
///   final service = MqttCameraService();
///   await service.connect();
///   service.startStream('24:0A:C4:12:34:56');
///   service.frameStream.listen((jpeg) => ...afișează frame...);
///   service.stopStream();
///   service.dispose();
class MqttCameraService {
  // EMQX Broker config — Cloudflare Load Balancer
  static const String _primaryBroker = 'mqtt.hopa.tritech.ro';
  static const String _fallbackBroker = 'mqtt.hopa.tritech.ro';
  static const int _port = 1883;
  static const String _username = 'hopa';
  static const String _password = 'superSecret';
  static const int _connectTimeoutMs = 5000; // 5 secunde per broker

  String _activeBroker = _primaryBroker;

  MqttServerClient? _client;
  String? _deviceMac;
  bool _isConnected = false;
  bool _isStreaming = false;

  // Stream controller pentru frame-uri JPEG
  final _frameController = StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get frameStream => _frameController.stream;

  // Status
  bool get isConnected => _isConnected;
  bool get isStreaming => _isStreaming;

  // FPS tracking
  int _frameCount = 0;
  DateTime? _fpsStart;
  double _currentFps = 0;
  double get currentFps => _currentFps;

  /// Conectare la EMQX broker cu fallback automat
  /// Încearcă primary (AlmaLinux), apoi fallback (Ubuntu), timeout 5s per broker.
  Future<bool> connect() async {
    // 1. Încearcă primary
    debugPrint('[MQTT_CAM] Încerc primary $_primaryBroker:$_port...');
    if (await _tryConnect(_primaryBroker)) {
      _activeBroker = _primaryBroker;
      return true;
    }

    // 2. Fallback
    debugPrint('[MQTT_CAM] ⚠️ Primary eșuat, încerc fallback $_fallbackBroker:$_port...');
    if (await _tryConnect(_fallbackBroker)) {
      _activeBroker = _fallbackBroker;
      return true;
    }

    debugPrint('[MQTT_CAM] ❌ Ambele brokere indisponibile');
    return false;
  }

  /// Încearcă conectarea la un broker specific cu timeout _connectTimeoutMs
  Future<bool> _tryConnect(String broker) async {
    try {
      // Închide clientul vechi dacă există
      _client?.disconnect();
      _client = null;

      final clientId = 'HOPA_APP_${DateTime.now().millisecondsSinceEpoch}';

      _client = MqttServerClient.withPort(broker, clientId, _port);
      _client!.keepAlivePeriod = 30;
      _client!.connectTimeoutPeriod = _connectTimeoutMs;
      _client!.autoReconnect = true;
      _client!.onAutoReconnect = _onAutoReconnect;
      _client!.onAutoReconnected = _onAutoReconnected;
      _client!.onDisconnected = _onDisconnected;
      _client!.onConnected = _onConnected;

      // Logging în debug
      _client!.logging(on: false);

      final connMsg = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .authenticateAs(_username, _password)
          .startClean()
          .withWillQos(MqttQos.atMostOnce);

      _client!.connectionMessage = connMsg;

      await _client!.connect();

      if (_client!.connectionStatus?.state == MqttConnectionState.connected) {
        _isConnected = true;
        debugPrint('[MQTT_CAM] ✅ Conectat la $broker:$_port');
        return true;
      } else {
        debugPrint('[MQTT_CAM] ❌ Conexiune eșuată la $broker: ${_client!.connectionStatus}');
        _client?.disconnect();
        _client = null;
        return false;
      }
    } catch (e) {
      debugPrint('[MQTT_CAM] ❌ Eroare conectare $broker: $e');
      _client?.disconnect();
      _client = null;
      return false;
    }
  }

  /// Pornește streaming de la camera cu MAC-ul specificat
  void startStream(String deviceMac) {
    if (!_isConnected || _client == null) {
      debugPrint('[MQTT_CAM] Nu sunt conectat!');
      return;
    }

    _deviceMac = deviceMac;
    _isStreaming = true;
    _frameCount = 0;
    _fpsStart = DateTime.now();

    // Subscribe la topic frame (QoS 0)
    final frameTopic = 'hopa/$deviceMac/camera/frame';
    _client!.subscribe(frameTopic, MqttQos.atMostOnce);
    debugPrint('[MQTT_CAM] Subscribe: $frameTopic');

    // Ascultă mesaje
    _client!.updates?.listen(_onMessage);

    // Publică "start" pe topic cmd (QoS 1)
    final cmdTopic = 'hopa/$deviceMac/camera/cmd';
    final builder = MqttClientPayloadBuilder();
    builder.addString('start');
    _client!.publishMessage(cmdTopic, MqttQos.atLeastOnce, builder.payload!);
    debugPrint('[MQTT_CAM] ▶ Publicat "start" pe $cmdTopic');
  }

  /// Oprește streaming
  void stopStream() {
    if (!_isConnected || _client == null || _deviceMac == null) return;

    _isStreaming = false;

    // Publică "stop" pe topic cmd
    final cmdTopic = 'hopa/$_deviceMac/camera/cmd';
    final builder = MqttClientPayloadBuilder();
    builder.addString('stop');
    _client!.publishMessage(cmdTopic, MqttQos.atLeastOnce, builder.payload!);
    debugPrint('[MQTT_CAM] ■ Publicat "stop" pe $cmdTopic');

    // Unsubscribe de la frame topic
    final frameTopic = 'hopa/$_deviceMac/camera/frame';
    _client!.unsubscribe(frameTopic);
    debugPrint('[MQTT_CAM] Unsubscribe: $frameTopic');
  }

  /// Procesare mesaje MQTT primite
  void _onMessage(List<MqttReceivedMessage<MqttMessage?>>? messages) {
    if (messages == null || !_isStreaming) return;

    for (final msg in messages) {
      final topic = msg.topic;
      final payload = msg.payload as MqttPublishMessage;
      final data = payload.payload.message;

      // Frame JPEG
      if (topic.contains('/camera/frame') && data.isNotEmpty) {
        _frameController.add(Uint8List.fromList(data));

        // FPS tracking
        _frameCount++;
        final now = DateTime.now();
        if (_fpsStart != null) {
          final elapsed = now.difference(_fpsStart!).inMilliseconds;
          if (elapsed >= 2000) {
            _currentFps = (_frameCount * 1000.0) / elapsed;
            _frameCount = 0;
            _fpsStart = now;
          }
        }
      }
    }
  }

  void _onConnected() {
    _isConnected = true;
    debugPrint('[MQTT_CAM] Conectat la $_activeBroker');
  }

  void _onDisconnected() {
    _isConnected = false;
    _isStreaming = false;
    debugPrint('[MQTT_CAM] Deconectat de la $_activeBroker');
  }

  void _onAutoReconnect() {
    debugPrint('[MQTT_CAM] Reconectare...');
  }

  void _onAutoReconnected() {
    _isConnected = true;
    debugPrint('[MQTT_CAM] Reconectat la $_activeBroker');

    // Re-subscribe dacă era streaming activ
    if (_deviceMac != null && _isStreaming) {
      final frameTopic = 'hopa/$_deviceMac/camera/frame';
      _client!.subscribe(frameTopic, MqttQos.atMostOnce);
      debugPrint('[MQTT_CAM] Re-subscribe: $frameTopic');
    }
  }

  /// Cleanup complet
  void dispose() {
    if (_isStreaming) stopStream();
    _client?.disconnect();
    _frameController.close();
    _client = null;
    _isConnected = false;
  }
}
