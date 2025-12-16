import 'package:flutter/material.dart';

enum GarageButtonState { closed, opening, open, closing }

class GarageButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final double size;
  final String label;

  const GarageButton({
    Key? key,
    this.onPressed,
    this.size = 200,
    this.label = 'HOPA',
  }) : super(key: key);

  @override
  State<GarageButton> createState() => _GarageButtonState();
}

class _GarageButtonState extends State<GarageButton>
    with TickerProviderStateMixin {
  late AnimationController _doorCtrl; // 0 = closed, 1 = open
  GarageButtonState _state = GarageButtonState.closed;
  bool _animating = false;

  @override
  void initState() {
    super.initState();
    _doorCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
  }

  @override
  void dispose() {
    _doorCtrl.dispose();
    super.dispose();
  }

  void _toggle() async {
    // Protecție robustă anti-double-tap
    if (_animating) return;
    
    setState(() {
      _animating = true;
    });

    final bool opening = _state == GarageButtonState.closed;
    setState(() => _state = opening
        ? GarageButtonState.opening
        : GarageButtonState.closing);

    if (opening) {
      _doorCtrl.forward(from: 0);
    } else {
      _doorCtrl.reverse(from: 1);
    }

    // Trigger real action after small delay
    Future.delayed(const Duration(milliseconds: 100), () {
      widget.onPressed?.call();
    });

    await Future.delayed(const Duration(milliseconds: 800));

    if (mounted) {
      setState(() {
        _state = opening ? GarageButtonState.open : GarageButtonState.closed;
        _animating = false;
      });
    }
  }

  Color get _color {
    switch (_state) {
      case GarageButtonState.open:
      case GarageButtonState.opening:
        return const Color(0xFFef4444); // red
      case GarageButtonState.closing:
      case GarageButtonState.closed:
      default:
        return const Color(0xFFfbbf24); // yellow
    }
  }

  String get _stateText {
    switch (_state) {
      case GarageButtonState.opening:
        return 'se deschide...';
      case GarageButtonState.open:
        return 'deschis';
      case GarageButtonState.closing:
        return 'se închide...';
      case GarageButtonState.closed:
      default:
        return 'închis';
    }
  }

  @override
  Widget build(BuildContext context) {
    final double doorWidth = widget.size * 0.4;
    final double doorHeight = widget.size * 0.3;
    final double carSize = widget.size * 0.18;

    return GestureDetector(
      onTap: _toggle,
      child: AnimatedBuilder(
        animation: _doorCtrl,
        builder: (_, __) {
          // Door translation from 0 (closed) to -doorHeight (open fully)
          final double translateY = -doorHeight * _doorCtrl.value;
          final double carOpacity = _doorCtrl.value;

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
                // concentric rings
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

                // Garage door frame
                Container(
                  width: doorWidth,
                  height: doorHeight,
                  decoration: BoxDecoration(
                    border: Border.all(color: _color, width: 3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),

                // Door slats (moving)
                Transform.translate(
                  offset: Offset(0, translateY),
                  child: SizedBox(
                    width: doorWidth,
                    height: doorHeight,
                    child: CustomPaint(
                      painter: _SlatsPainter(color: _color),
                    ),
                  ),
                ),

                // Car emoji appears when open
                Opacity(
                  opacity: carOpacity,
                  child: Text(
                    '🚗',
                    style: TextStyle(fontSize: carSize),
                  ),
                ),

                // label bottom
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

                // state text top
                Positioned(
                  top: widget.size * 0.02,
                  child: Text(
                    _stateText,
                    style: TextStyle(
                      color: _color,
                      fontSize: widget.size * 0.035,
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

class _SlatsPainter extends CustomPainter {
  final Color color;
  _SlatsPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final stripeHeight = size.height / 10; // draw 5 filled slats
    for (double y = 0; y < size.height; y += stripeHeight * 2) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, stripeHeight), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SlatsPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
