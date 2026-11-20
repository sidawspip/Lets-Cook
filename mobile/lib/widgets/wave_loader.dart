import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class WaveLoader extends StatefulWidget {
  const WaveLoader({
    super.key,
    this.label = 'Starting video',
    this.showScrim = false,
    this.size = 58,
  });

  final String label;
  final bool showScrim;
  final double size;

  @override
  State<WaveLoader> createState() => _WaveLoaderState();
}

class _WaveLoaderState extends State<WaveLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ColoredBox(
      color: widget.showScrim ? const Color(0x88000000) : Colors.transparent,
      child: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final pulse = .98 + .16 * math.sin(_controller.value * math.pi * 2);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  scale: pulse,
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xE610161C),
                      border: Border.all(color: const Color(0x88A8EF45)),
                      boxShadow: const [
                        BoxShadow(color: Color(0x709C5CFF), blurRadius: 28),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        final phase =
                            (_controller.value + index * .11) * math.pi * 2;
                        final height = 8 + 22 * ((math.sin(phase) + 1) / 2);
                        return Container(
                          width: 4,
                          height: height,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: AppColors.lime.withValues(
                              alpha: .48 + .52 * (height - 8) / 22,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
                if (widget.label.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    widget.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .9,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    ),
  );
}
