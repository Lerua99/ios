import 'package:flutter/material.dart';
import 'dart:async';

enum PedestrianButtonState { closed, opening, open, closing }

class PedestrianButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final double size;
  final String label;

  const PedestrianButton({
    Key? key,
    this.onPressed,
    this.size = 200,
    this.label = 'HOPA',
  }) : super(key: key);

  @override
  State<PedestrianButton> createState() => _PedestrianButtonState();
}

class _PedestrianButtonState extends State<PedestrianButton>
    with TickerProviderStateMixin {
  late AnimationController _moveCtrl;
  PedestrianButtonState _state = PedestrianButtonState.closed;
  bool _animating = false;
  // dacă există un countdown activ, ignorăm tap-urile
  bool get _isCounting => _countdownTimer != null && _countdown > 0;
  double _countdown = 0;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _moveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _moveCtrl.dispose();
    super.dispose();
  }

  void _toggle() async {
    // Protecție robustă anti-double-tap
    if (_animating || _isCounting) return;
    
    setState(() {
      _animating = true;
    });

    final bool opening = _state == PedestrianButtonState.closed;
    setState(() => _state = opening
        ? PedestrianButtonState.opening
        : PedestrianButtonState.closing);

    // animația deplasării
    if (opening) {
      _moveCtrl.forward(from: 0);
    } else {
      _moveCtrl.reverse(from: 1);
    }

    // acțiunea reală
    Future.delayed(const Duration(milliseconds: 100), () {
      widget.onPressed?.call();
    });

    await Future.delayed(const Duration(milliseconds: 800));

    if (mounted) {
      if (opening) {
        // starea OPEN + countdown
        setState(() {
          _state = PedestrianButtonState.open;
          _animating = false;
        });
        _startCountdown();
      } else {
        setState(() {
          _state = PedestrianButtonState.closed;
          _animating = false;
        });
      }
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdown = 10;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() {
        _countdown -= 1;
      });
      if (_countdown <= 0) {
        t.cancel();
        // start closing
        _toggle();
      }
    });
  }

  Color get _color {
    switch (_state) {
      case PedestrianButtonState.open:
      case PedestrianButtonState.opening:
        return const Color(0xFFef4444); // roşu
      case PedestrianButtonState.closing:
      case PedestrianButtonState.closed:
      default:
        return const Color(0xFFfbbf24); // galben
    }
  }

  String get _stateText {
    switch (_state) {
      case PedestrianButtonState.opening:
        return 'se deschide...';
      case PedestrianButtonState.open:
        return _countdown > 0 ? _countdown.toStringAsFixed(0) : 'deschis';
      case PedestrianButtonState.closing:
        return 'se închide...';
      case PedestrianButtonState.closed:
      default:
        return 'închis';
    }
  }

  @override
  Widget build(BuildContext context) {
    final double offset = widget.size * 0.15; // 30px la 200px = 0.15

    return GestureDetector(
      onTap: _toggle,
      child: AnimatedBuilder(
        animation: _moveCtrl,
        builder: (_, __) {
          double dx = -offset * _moveCtrl.value;
          return Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.05),
              border: Border.all(color: _color.withOpacity(0.3), width: 2),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // inele concentrice
                for (int i = 0; i < 3; i++)
                  Container(
                    width: widget.size - 40 - i * 30,
                    height: widget.size - 40 - i * 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _color.withOpacity(0.3 - i * 0.05),
                        width: 1.5,
                      ),
                    ),
                  ),
                // emoji pieton, deplasat pe axa X
                Transform.translate(
                  offset: Offset(dx, 0),
                  child: Text(
                    '🚶',
                    style: TextStyle(fontSize: widget.size * 0.2),
                  ),
                ),
                // textul HOPA jos
                Positioned(
                  bottom: widget.size * 0.25,
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      color: _color,
                      fontSize: widget.size * 0.08,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                // text stare sus
                Positioned(
                  top: widget.size * 0.02,
                  child: Text(
                    _stateText,
                    style: TextStyle(
                      color: _color,
                      fontSize: widget.size * 0.05,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
