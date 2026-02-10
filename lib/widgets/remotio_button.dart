import 'package:flutter/material.dart';

enum ButtonState { closed, opening, open, closing }

class RemotioButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final String label;
  final double size;

  const RemotioButton({
    super.key,
    this.onPressed,
    this.label = 'HOPA',
    this.size = 200,
  });

  @override
  State<RemotioButton> createState() => _RemotioButtonState();
}

class _RemotioButtonState extends State<RemotioButton>
    with TickerProviderStateMixin {
  late AnimationController _rotateCtrl;
  late AnimationController _pressCtrl;
  late Animation<double> _scaleAnim;
  ButtonState _state = ButtonState.closed;
  bool _animating = false;

  @override
  void initState() {
    super.initState();
    _rotateCtrl = AnimationController(
      duration: const Duration(seconds: 7),
      vsync: this,
    );
    _pressCtrl = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnim = Tween(begin: 1.0, end: 0.95).animate(_pressCtrl);
  }

  @override
  void dispose() {
    _rotateCtrl.dispose();
    _pressCtrl.dispose();
    super.dispose();
  }

  void _toggle() async {
    // Protecție robustă anti-double-tap
    if (_animating) return;
    
    setState(() {
      _animating = true;
    });
    
    final bool opening = _state == ButtonState.closed;
    setState(() => _state = opening ? ButtonState.opening : ButtonState.closing);

    // Pornește rotația doar pe durata tranziției (rapid ca în demo)
    _rotateCtrl.repeat(period: const Duration(milliseconds: 800));

    // Execută comanda după 100ms de animație frumoasă
    Future.delayed(const Duration(milliseconds: 100), () {
      widget.onPressed?.call();
    });

    await Future.delayed(const Duration(milliseconds: 800));
    
    if (mounted) {
      setState(() {
        _state = opening ? ButtonState.open : ButtonState.closed;
        _animating = false;
      });

      // Oprește rotația la final
      _rotateCtrl.stop();
    }
  }

  Color get _color {
    // PRO permanent — portocaliu (închis) / verde (deschis)
    switch (_state) {
      case ButtonState.open:
      case ButtonState.opening:
        return const Color(0xFF4ade80);
      case ButtonState.closing:
      case ButtonState.closed:
        return const Color(0xFFfb923c);
    }
  }

  String get _stateText {
    switch (_state) {
      case ButtonState.opening:
        return 'Deschis...';
      case ButtonState.open:
        return 'DESCHIS';
      case ButtonState.closing:
        return 'Închis...';
      case ButtonState.closed:
        return 'ÎNCHIS';
    }
  }

  IconData get _lockIcon =>
      (_state == ButtonState.open || _state == ButtonState.opening)
          ? Icons.lock_open_rounded
          : Icons.lock_outlined;

  @override
  Widget build(BuildContext context) {
    final double ringStroke = 1.5;
    return GestureDetector(
      onTapDown: (_) {
        if (!_animating) _pressCtrl.forward();
      },
      onTapUp: (_) {
        _pressCtrl.reverse();
        _toggle();
      },
      onTapCancel: () => _pressCtrl.reverse(),
      child: AnimatedBuilder(
        animation: Listenable.merge([_rotateCtrl, _scaleAnim]),
        builder: (_, a) {
          return Transform.scale(
            scale: _scaleAnim.value,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _color.withValues(alpha: 0.3), width: 2),
                color: Colors.white.withValues(alpha: 0.05),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // rings
                  for (int i = 0; i < 3; i++)
                    Container(
                      width: widget.size - 40 - i * 30,
                      height: widget.size - 40 - i * 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _color.withValues(alpha: 0.3 - i * 0.05),
                          width: ringStroke,
                        ),
                      ),
                    ),
                  // rotating arrows
                  Transform.rotate(
                    angle: _rotateCtrl.value * 2 * 3.1416 *
                        ((_state == ButtonState.opening) ? 1 : (_state == ButtonState.closing ? -1 : 0)),
                    child: _Arrows(color: _color, size: widget.size),
                  ),
                  // lock icon
                  Icon(_lockIcon, color: _color, size: widget.size * 0.12),
                  // label bottom
                  Positioned(
                    bottom: widget.size * 0.25,
                    child: Text(widget.label,
                        style: TextStyle(
                            color: _color,
                            fontSize: widget.size * 0.08,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.5)),
                  ),
                  // state text top, mai mic și mai sus
                  Positioned(
                    top: widget.size * 0.02,
                    child: Text(
                      _stateText,
                      style: TextStyle(
                        color: _color,
                        fontSize: widget.size * 0.035,
                        fontWeight:
                            (_state == ButtonState.open) ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Arrows extends StatelessWidget {
  final Color color;
  final double size;
  const _Arrows({required this.color, required this.size});
  @override
  Widget build(BuildContext context) {
    final double offset = 15;
    final double arrowSize = size * 0.08;
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          top: offset,
          child: Text('↑', style: TextStyle(color: color, fontSize: arrowSize, fontWeight: FontWeight.bold)),
        ),
        Positioned(
          right: offset,
          child: Text('→', style: TextStyle(color: color, fontSize: arrowSize, fontWeight: FontWeight.bold)),
        ),
        Positioned(
          bottom: offset,
          child: Text('↓', style: TextStyle(color: color, fontSize: arrowSize, fontWeight: FontWeight.bold)),
        ),
        Positioned(
          left: offset,
          child: Text('←', style: TextStyle(color: color, fontSize: arrowSize, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
} 