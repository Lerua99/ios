import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/mqtt_camera_service.dart';

/// Moduri de vizualizare cameră
enum CameraViewMode {
  mqtt,      // Remote prin MQTT (funcționează de oriunde)
  localLive, // WebView pe IP local (doar din rețea)
  snapshot,  // Captură individuală pe IP local
}

class CameraStreamScreen extends StatefulWidget {
  const CameraStreamScreen({
    super.key,
    this.cameraUrl,
    this.deviceMac,
  });

  final String? cameraUrl;
  final String? deviceMac;

  @override
  State<CameraStreamScreen> createState() => _CameraStreamScreenState();
}

class _CameraStreamScreenState extends State<CameraStreamScreen> {
  static const String _defaultBaseUrl = 'http://192.168.1.145';
  static const String _cameraPrefsKey = 'hopa_camera_url';
  static const String _cameraMacKey = 'hopa_camera_mac';

  CameraViewMode _mode = CameraViewMode.mqtt;
  String _baseUrl = _defaultBaseUrl;
  String? _deviceMac;
  String _snapshotUrl = '';
  bool _ready = false;
  bool _streamLoading = true;
  bool _snapshotAuto = true;
  bool _mqttConnecting = false;

  // MQTT camera service
  final MqttCameraService _mqttService = MqttCameraService();
  Uint8List? _latestFrame;
  StreamSubscription<Uint8List>? _frameSub;

  Timer? _snapshotTimer;
  Timer? _fpsUpdateTimer;
  late final WebViewController _webController;

  @override
  void initState() {
    super.initState();
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _streamLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _streamLoading = false);
          },
          onWebResourceError: (_) {
            if (mounted) setState(() => _streamLoading = false);
          },
        ),
      );
    _initCamera();
  }

  @override
  void dispose() {
    _snapshotTimer?.cancel();
    _fpsUpdateTimer?.cancel();
    _frameSub?.cancel();
    _mqttService.stopStream();
    _mqttService.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════
  //  INIT
  // ═══════════════════════════════════════════════════════════════
  Future<void> _initCamera() async {
    final prefs = await SharedPreferences.getInstance();

    // MAC-ul camerei (din argument sau din preferences)
    _deviceMac = widget.deviceMac ??
        prefs.getString(_cameraMacKey);
    if (_deviceMac != null && _deviceMac!.isNotEmpty) {
      await prefs.setString(_cameraMacKey, _deviceMac!);
    }

    // URL local (din argument sau preferences)
    final fromPush = widget.cameraUrl?.trim();
    final selectedRaw =
        (fromPush != null && fromPush.isNotEmpty) ? fromPush : _defaultBaseUrl;
    final base = _normalizeBaseUrl(selectedRaw);
    await prefs.setString(_cameraPrefsKey, base);

    if (!mounted) return;
    setState(() {
      _baseUrl = base;
      _ready = true;
    });

    // Dacă avem MAC → start MQTT automat
    if (_deviceMac != null && _deviceMac!.isNotEmpty) {
      _startMqttStream();
    } else {
      // Fallback la local live
      setState(() => _mode = CameraViewMode.localLive);
      _reloadLiveStream();
    }
  }

  String _normalizeBaseUrl(String? raw) {
    var value = (raw ?? '').trim();
    if (value.isEmpty || value.toLowerCase() == 'null') {
      return _defaultBaseUrl;
    }
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }
    try {
      final uri = Uri.parse(value);
      if (uri.host.isEmpty) return _defaultBaseUrl;
      final scheme = uri.scheme.isEmpty ? 'http' : uri.scheme;
      final port = uri.hasPort ? ':${uri.port}' : '';
      return '$scheme://${uri.host}$port';
    } catch (_) {
      return _defaultBaseUrl;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  MQTT STREAMING
  // ═══════════════════════════════════════════════════════════════
  Future<void> _startMqttStream() async {
    if (_mqttConnecting) return;
    setState(() {
      _mqttConnecting = true;
      _mode = CameraViewMode.mqtt;
    });

    final connected = await _mqttService.connect();
    if (!mounted) return;

    if (connected && _deviceMac != null) {
      _mqttService.startStream(_deviceMac!);

      _frameSub?.cancel();
      _frameSub = _mqttService.frameStream.listen((frame) {
        if (mounted) {
          setState(() => _latestFrame = frame);
        }
      });

      // Update FPS display la fiecare 2 secunde
      _fpsUpdateTimer?.cancel();
      _fpsUpdateTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (mounted) setState(() {});
      });

      setState(() => _mqttConnecting = false);
    } else {
      // Nu facem fallback automat pe local când MQTT nu se conectează.
      // În afara rețelei locale, fallback-ul pe IP intern eșuează mereu și
      // creează impresia că "nu merge camera". Utilizatorul poate alege manual
      // modul Local din meniu dacă este în LAN.
      setState(() => _mqttConnecting = false);
    }
  }

  void _stopMqttStream() {
    _frameSub?.cancel();
    _fpsUpdateTimer?.cancel();
    _mqttService.stopStream();
    setState(() => _latestFrame = null);
  }

  // ═══════════════════════════════════════════════════════════════
  //  LOCAL STREAMING (WebView) — existent, neatins
  // ═══════════════════════════════════════════════════════════════
  String get _streamUrl => '$_baseUrl/stream';
  String get _captureBase => '$_baseUrl/capture';

  void _reloadLiveStream() {
    final html = '''
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <style>
      html, body { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; background: #000; }
      .wrap { display: flex; width: 100%; height: 100%; align-items: center; justify-content: center; background: #000; }
      img { width: 100%; height: 100%; object-fit: contain; }
    </style>
  </head>
  <body>
    <div class="wrap"><img src="$_streamUrl" alt="stream"></div>
  </body>
</html>
''';
    setState(() => _streamLoading = true);
    _webController.loadHtmlString(html);
  }

  void _reloadSnapshot() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    setState(() => _snapshotUrl = '$_captureBase?t=$ts');
  }

  void _startSnapshotTimer() {
    _snapshotTimer?.cancel();
    if (_mode != CameraViewMode.snapshot || !_snapshotAuto) return;
    _snapshotTimer = Timer.periodic(const Duration(milliseconds: 280), (_) {
      if (!mounted || _mode != CameraViewMode.snapshot || !_snapshotAuto) return;
      _reloadSnapshot();
    });
  }

  // ═══════════════════════════════════════════════════════════════
  //  MODE SWITCHING
  // ═══════════════════════════════════════════════════════════════
  void _switchMode(CameraViewMode newMode) {
    if (_mode == newMode) return;

    // Oprește modul curent
    if (_mode == CameraViewMode.mqtt) _stopMqttStream();
    if (_mode == CameraViewMode.snapshot) _snapshotTimer?.cancel();

    setState(() => _mode = newMode);

    // Pornește noul mod
    switch (newMode) {
      case CameraViewMode.mqtt:
        _startMqttStream();
        break;
      case CameraViewMode.localLive:
        _reloadLiveStream();
        break;
      case CameraViewMode.snapshot:
        _reloadSnapshot();
        _startSnapshotTimer();
        break;
    }
  }

  void _refreshCurrent() {
    switch (_mode) {
      case CameraViewMode.mqtt:
        _stopMqttStream();
        _startMqttStream();
        break;
      case CameraViewMode.localLive:
        _reloadLiveStream();
        break;
      case CameraViewMode.snapshot:
        _reloadSnapshot();
        break;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  BUILD UI
  // ═══════════════════════════════════════════════════════════════
  Widget _buildMqttBody() {
    if (_mqttConnecting) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('Conectare MQTT...', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    if (_latestFrame == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.videocam, color: Colors.white38, size: 64),
            const SizedBox(height: 16),
            Text(
              _mqttService.isConnected
                  ? 'Aștept frame-uri de la cameră...'
                  : 'Nu sunt conectat la MQTT',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            if (_deviceMac != null) ...[
              const SizedBox(height: 8),
              Text(
                'MAC: $_deviceMac',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ],
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: Image.memory(
            _latestFrame!,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
          ),
        ),
        // FPS indicator
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${_mqttService.currentFps.toStringAsFixed(1)} FPS',
              style: const TextStyle(
                color: Colors.greenAccent,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLiveBody() {
    return Stack(
      children: [
        Positioned.fill(child: WebViewWidget(controller: _webController)),
        if (_streamLoading)
          const Center(child: CircularProgressIndicator(color: Colors.white)),
      ],
    );
  }

  Widget _buildSnapshotBody() {
    return Center(
      child: InteractiveViewer(
        minScale: 1,
        maxScale: 4,
        child: Image.network(
          _snapshotUrl,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          filterQuality: FilterQuality.low,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const CircularProgressIndicator(color: Colors.white70);
          },
          errorBuilder: (context, error, stackTrace) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.videocam_off, color: Colors.white54, size: 72),
                  const SizedBox(height: 14),
                  const Text(
                    'Camera snapshot nu răspunde.',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text('URL: $_captureBase',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: _reloadSnapshot,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Încearcă din nou'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_mode) {
      case CameraViewMode.mqtt:
        return _buildMqttBody();
      case CameraViewMode.localLive:
        return _buildLiveBody();
      case CameraViewMode.snapshot:
        return _buildSnapshotBody();
    }
  }

  String _modeLabel(CameraViewMode mode) {
    switch (mode) {
      case CameraViewMode.mqtt:
        return 'Remote';
      case CameraViewMode.localLive:
        return 'Local';
      case CameraViewMode.snapshot:
        return 'Snapshot';
    }
  }

  IconData _modeIcon(CameraViewMode mode) {
    switch (mode) {
      case CameraViewMode.mqtt:
        return Icons.cloud;
      case CameraViewMode.localLive:
        return Icons.wifi;
      case CameraViewMode.snapshot:
        return Icons.photo_camera;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Închide camera',
        ),
        title: Text('Camera ${_modeLabel(_mode)}'),
        actions: [
          // Mode selector
          PopupMenuButton<CameraViewMode>(
            icon: Icon(_modeIcon(_mode)),
            tooltip: 'Schimbă modul',
            onSelected: _switchMode,
            itemBuilder: (context) => CameraViewMode.values.map((m) {
              return PopupMenuItem(
                value: m,
                child: Row(
                  children: [
                    Icon(_modeIcon(m),
                        color: m == _mode ? Colors.blue : Colors.grey),
                    const SizedBox(width: 8),
                    Text(_modeLabel(m),
                        style: TextStyle(
                          fontWeight:
                              m == _mode ? FontWeight.bold : FontWeight.normal,
                        )),
                  ],
                ),
              );
            }).toList(),
          ),
          // Snapshot auto toggle
          if (_mode == CameraViewMode.snapshot)
            IconButton(
              icon: Icon(_snapshotAuto ? Icons.pause_circle : Icons.play_circle),
              tooltip: _snapshotAuto ? 'Pauză refresh' : 'Play refresh',
              onPressed: () {
                setState(() => _snapshotAuto = !_snapshotAuto);
                _startSnapshotTimer();
              },
            ),
          // Refresh
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _refreshCurrent,
          ),
        ],
      ),
      body: !_ready
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Stack(
              children: [
                Positioned.fill(child: _buildBody()),
                // Status bar
                Positioned(
                  left: 12, right: 12, bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        // Connection indicator
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _mode == CameraViewMode.mqtt
                                ? (_mqttService.isConnected
                                    ? Colors.greenAccent
                                    : Colors.redAccent)
                                : Colors.blueAccent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _mode == CameraViewMode.mqtt
                                ? 'MQTT ${_mqttService.isConnected ? "conectat" : "deconectat"}'
                                    '${_deviceMac != null ? " | $_deviceMac" : ""}'
                                : 'Local: $_baseUrl',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
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
}
