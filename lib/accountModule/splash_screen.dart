import 'dart:async';
import 'package:flutter/material.dart';
import 'auth_gate.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Navigate to AuthGate after 10 seconds
    Timer(const Duration(seconds: 10), () {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const AuthGate()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2561FA), Color(0xFF1D4ED8)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Main blue section with logo
              Expanded(
                flex: 7,
                child: Center(
                  child: Container(
                    width: 150,
                    height: 150,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/images/FYP LOGO.JPG',
                        width: 120,
                        height: 120,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
              
              // Bottom white curved section with welcome text
              Expanded(
                flex: 3,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Curved white background
                    ClipPath(
                      clipper: CurveClipper(),
                      child: Container(
                        color: Colors.white,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    ),
                    
                    // Welcome text
                    Positioned(
                      top: 70,
                      child: Text(
                        'Welcome to OptiChat',
                        style: TextStyle(
                          color: Color(0xFF2561FA),
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Custom clipper for the curved top section
class CurveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    
    // Start at top left
    path.moveTo(0, 0);
    
    // Draw curve from left to right
    path.quadraticBezierTo(
      size.width / 2, // control point x
      size.height / 2.5, // control point y - adjust this to change curve height
      size.width, // end point x
      0, // end point y
    );
    
    // Complete the shape
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
} 