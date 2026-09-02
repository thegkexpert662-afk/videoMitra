import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../home/home_screen.dart';
import '../home/home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _loaderController;

  late Animation<double> _logoScale;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _loaderController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _logoScale = CurvedAnimation(
      parent: _logoController,
      curve: Curves.elasticOut,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _logoController,
      curve: const Interval(
        0.35,
        1.0,
        curve: Curves.easeIn,
      ),
    );

    _logoController.forward();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const HomeScreen(),
          ),
        );
      }
    });
  }


  @override
  void dispose() {
    _logoController.dispose();
    _loaderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030307),
      body: Stack(
        children: [
          // Background glow
          Positioned(
            top: 180,
            left: -100,
            child: _glow(
              color: const Color(0xFF7B2CFF),
              size: 300,
            ),
          ),

          Positioned(
            top: 300,
            right: -120,
            child: _glow(
              color: const Color(0xFF0066FF),
              size: 300,
            ),
          ),

          // Bottom waves
          const Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: 220,
              width: double.infinity,
              child: CustomPaint(
                painter: _WavePainter(),
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: Column(
                children: [
                  const Spacer(flex: 3),

                  // Animated V Logo
                  ScaleTransition(
                    scale: _logoScale,
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: CustomPaint(
                        size: const Size(220, 220),
                        painter: _VideoMitraLogoPainter(),
                      ),
                    ),
                  ),

                  const SizedBox(height: 35),

                  // VideoMitra name
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: ShaderMask(
                      shaderCallback: (bounds) {
                        return const LinearGradient(
                          colors: [
                            Colors.white,
                            Colors.white,
                            Color(0xFFFF2D75),
                            Color(0xFF9B3CFF),
                            Color(0xFF286BFF),
                          ],
                        ).createShader(bounds);
                      },
                      child: const Text(
                        'VideoMitra',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 42,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -2,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Tagline
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: const Text(
                      'EDIT  •  CREATE  •  SHARE',
                      style: TextStyle(
                        color: Color(0xFFA6A6B0),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 3,
                      ),
                    ),
                  ),

                  const Spacer(flex: 2),

                  // Animated Loader
                  AnimatedBuilder(
                    animation: _loaderController,
                    builder: (context, child) {
                      return Transform.rotate(
                        angle: _loaderController.value * math.pi * 2,
                        child: CustomPaint(
                          size: const Size(42, 42),
                          painter: _LoaderPainter(),
                        ),
                      );
                    },
                  ),

                  const Spacer(flex: 2),

                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: const Text(
                      'Create without limits',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 13,
                        letterSpacing: 1,
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glow({
    required Color color,
    required double size,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withOpacity(0.18),
            color.withOpacity(0.05),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}

// ================= VIDEO MITRA LOGO =================

class _VideoMitraLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;

    // Left V / Film strip
    final leftPath = Path()
      ..moveTo(25, 20)
      ..lineTo(78, 20)
      ..lineTo(centerX, 175)
      ..lineTo(130, 70)
      ..lineTo(165, 95)
      ..lineTo(118, 205)
      ..quadraticBezierTo(105, 225, 88, 200)
      ..close();

    final leftPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFFF2D75),
          Color(0xFFBC16B7),
          Color(0xFF623CFF),
          Color(0xFF176BFF),
        ],
      ).createShader(
        Rect.fromLTWH(0, 0, size.width, size.height),
      );

    canvas.drawPath(leftPath, leftPaint);

    // Right side / Play shape
    final rightPath = Path()
      ..moveTo(centerX, 175)
      ..lineTo(120, 55)
      ..quadraticBezierTo(130, 20, 165, 30)
      ..lineTo(200, 55)
      ..quadraticBezierTo(225, 70, 205, 100)
      ..close();

    final rightPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFFFD23F),
          Color(0xFFFF6B45),
          Color(0xFFFF2D75),
          Color(0xFF803CFF),
        ],
      ).createShader(
        Rect.fromLTWH(80, 20, 130, 170),
      );

    canvas.drawPath(rightPath, rightPaint);

    // Film holes
    final holePaint = Paint()..color = const Color(0xFF07070D);

    for (int i = 0; i < 5; i++) {
      final y = 48.0 + (i * 27);

      canvas.save();
      canvas.rotate(-0.28);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(38, y, 13, 17),
          const Radius.circular(3),
        ),
        holePaint,
      );
      canvas.restore();
    }

    // Play button
    final playPath = Path()
      ..moveTo(160, 58)
      ..lineTo(160, 100)
      ..lineTo(192, 79)
      ..close();

    canvas.drawPath(
      playPath,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );

    // Glow under logo
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX, 215),
        width: 120,
        height: 12,
      ),
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF743CFF).withOpacity(0.7),
            Colors.transparent,
          ],
        ).createShader(
          Rect.fromLTWH(50, 200, 120, 20),
        ),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ================= LOADER =================

class _LoaderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(3, 3, size.width - 6, size.height - 6);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        colors: [
          Color(0xFFFF2D75),
          Color(0xFFFFA13D),
          Color(0xFF8B3CFF),
          Color(0xFF176BFF),
        ],
      ).createShader(rect);

    canvas.drawArc(
      rect,
      0,
      math.pi * 1.45,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ================= BOTTOM WAVES =================

class _WavePainter extends CustomPainter {
  const _WavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final wave1 = Path()
      ..moveTo(0, 40)
      ..quadraticBezierTo(
        size.width * 0.25,
        170,
        size.width * 0.52,
        185,
      )
      ..quadraticBezierTo(
        size.width * 0.8,
        210,
        size.width,
        80,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final paint1 = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Color(0xFF3D075D),
          Color(0xFF160B4A),
          Color(0xFF051C63),
        ],
      ).createShader(
        Rect.fromLTWH(0, 0, size.width, size.height),
      );

    canvas.drawPath(wave1, paint1);

    final wave2 = Path()
      ..moveTo(0, 115)
      ..quadraticBezierTo(
        size.width * 0.35,
        205,
        size.width * 0.65,
        200,
      )
      ..quadraticBezierTo(
        size.width * 0.88,
        190,
        size.width,
        150,
      );

    canvas.drawPath(
      wave2,
      Paint()
        ..color = const Color(0xFF6F2BFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final wave3 = Path()
      ..moveTo(0, 55)
      ..quadraticBezierTo(
        size.width * 0.3,
        180,
        size.width * 0.58,
        200,
      )
      ..quadraticBezierTo(
        size.width * 0.8,
        220,
        size.width,
        90,
      );

    canvas.drawPath(
      wave3,
      Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0xFFFF2D75),
            Color(0xFF8B3CFF),
            Color(0xFF176BFF),
          ],
        ).createShader(
          Rect.fromLTWH(0, 0, size.width, size.height),
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}