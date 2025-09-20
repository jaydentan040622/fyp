import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:vibration/vibration.dart';
import '../home.dart';
import '../gesture_recognition_service.dart';
import 'login_page.dart';
import 'register_page.dart';
import 'caregiver_home.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  // Gesture recognition service
  final GestureRecognitionService _gestureService = GestureRecognitionService();
  static const String _pageId = 'auth_gate';
  
  // Accessibility state management
  Map<String, bool> _buttonConfirmationStates = {};
  bool _isAudioFeedbackEnabled = true;
  bool _hasAnnouncedPage = false;

  @override
  void initState() {
    super.initState();
    _initializeAccessibility();
  }

  Future<void> _initializeAccessibility() async {
    try {
      await _gestureService.initialize();
      _gestureService.setGestureCallback(_handleGesture);
      _gestureService.setActiveAnnouncementSource(_pageId);
      
      // Announce page after initialization
      _announceCurrentPage();
    } catch (e) {
      debugPrint('Failed to initialize gesture service: $e');
    }
  }

  Future<void> _announceCurrentPage() async {
    if (_hasAnnouncedPage) return;
    
    await Future.delayed(const Duration(milliseconds: 800));
    
    if (mounted && _gestureService.canMakeAnnouncements(_pageId)) {
      _hasAnnouncedPage = true;
      await _gestureService.speak(
        'OptiChat Authentication page. Welcome to OptiChat - empowering independence for the visually impaired. You can log in to your account, use the app as a guest, or register as a new user. Draw a circle to repeat this announcement.',
        pageId: _pageId
      );
    }
  }

  void _handleGesture(GestureType gestureType) {
    debugPrint('Gesture detected: $gestureType');
    
    switch (gestureType) {
      case GestureType.circleGesture:
        _repeatPageAnnouncement();
        break;
      default:
        break;
    }
  }

  Future<void> _repeatPageAnnouncement() async {
    debugPrint('Circle gesture detected - repeating page announcement');
    
    _provideHapticFeedback('double');
    _gestureService.stopAllAnnouncements();
    
    await Future.delayed(const Duration(milliseconds: 300));
    
    if (mounted && _gestureService.canMakeAnnouncements(_pageId)) {
      await _gestureService.speak(
        'OptiChat Authentication page. Choose to log in with existing account, use app as guest, or register as new user. Three buttons available: Log In, Use App as Guest, and Register as New User.',
        pageId: _pageId
      );
    }
  }

  void _provideHapticFeedback(String intensity) {
    switch (intensity) {
      case 'light':
        Vibration.vibrate(duration: 50);
        break;
      case 'medium':
        Vibration.vibrate(duration: 100);
        break;
      case 'heavy':
        Vibration.vibrate(duration: 200);
        break;
      case 'double':
        Vibration.vibrate(pattern: [50, 50, 100]);
        break;
    }
  }

  Future<void> _handleButtonClick(String buttonName, VoidCallback action) async {
    bool isConfirmed = _buttonConfirmationStates[buttonName] ?? false;
    
    if (!isConfirmed) {
      _buttonConfirmationStates[buttonName] = true;
      _provideHapticFeedback('medium');
      
      String confirmationMessage = '';
      switch (buttonName) {
        case 'login':
          confirmationMessage = 'Log In button selected. Click again to confirm and go to login page.';
          break;
        case 'guest':
          confirmationMessage = 'Use App as Guest button selected. Click again to confirm and continue without account.';
          break;
        case 'register':
          confirmationMessage = 'Register as New User button selected. Click again to confirm and go to registration page.';
          break;
        default:
          confirmationMessage = '$buttonName button selected. Click again to confirm.';
      }
      
      await _gestureService.speak(confirmationMessage, pageId: _pageId);
      
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _buttonConfirmationStates[buttonName] = false;
          });
        }
      });
    } else {
      _buttonConfirmationStates[buttonName] = false;
      _provideHapticFeedback('heavy');
      await _gestureService.speak('Action confirmed.', pageId: _pageId);
      action();
    }
  }

  @override
  void dispose() {
    _gestureService.stopAllAnnouncements();
    _gestureService.clearActiveAnnouncementSource(_pageId);
    _gestureService.clearGestureCallback();
    super.dispose();
  }

  Future<Widget> _getHomeScreen() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('userprofile')
            .doc(user.uid)
            .get();
        
        if (doc.exists) {
          String userType = doc.data()?['userType'] ?? 'blind_user';
          return userType == 'caregiver' 
              ? const CaregiverHomeScreen() 
              : const HomeScreen();
        }
      } catch (e) {
        print('Error getting user type: $e');
      }
    }
    return const HomeScreen(); // Default fallback
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Show loading while checking auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // If user is logged in, redirect to appropriate home
        if (snapshot.hasData) {
          return FutureBuilder<Widget>(
            future: _getHomeScreen(),
            builder: (context, homeSnapshot) {
              if (homeSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              return homeSnapshot.data ?? const HomeScreen();
            },
          );
        }

        // If not logged in, show auth options
        return Scaffold(
          body: GestureDetector(
            onPanStart: (details) {
              _gestureService.startGesture(details.localPosition);
            },
            onPanUpdate: (details) {
              _gestureService.updateGesture(details.localPosition);
            },
            onPanEnd: (details) {
              _gestureService.endGesture();
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                // Logo and Title
                Image.asset(
                  'assets/images/FYP LOGO.JPG',
                  width: 120,
                  height: 120,
                ),
                const SizedBox(height: 32),
                const Text(
                  "Let's Get You Started With OptiChat",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2C3E50),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  "Empowering independence for the visually impaired\nand peace of mind for caregivers",
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),

                // Login Button
                Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF2561FA)),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: TextButton(
                    onPressed: () async {
                      await _handleButtonClick('login', () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const LoginPage()),
                        );
                      });
                    },
                    child: const Text(
                      'LOG IN',
                      style: TextStyle(
                        color: Color(0xFF2C3E50),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Guest Button
                Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF2561FA)),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: TextButton(
                    onPressed: () async {
                      await _handleButtonClick('guest', () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (context) => const HomeScreen()),
                        );
                      });
                    },
                    child: const Text(
                      'USE APP AS GUEST',
                      style: TextStyle(
                        color: Color(0xFF2C3E50),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Register Button
                Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2561FA),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: TextButton(
                    onPressed: () async {
                      await _handleButtonClick('register', () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const RegisterPage()),
                        );
                      });
                    },
                    child: const Text(
                      'REGISTER AS NEW USER',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ),
        );
      },
    );
  }
}