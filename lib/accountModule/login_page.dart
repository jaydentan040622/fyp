import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:vibration/vibration.dart';
import '../home.dart';
import 'caregiver_home.dart';
import '../gesture_recognition_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _rememberPassword = false;
  bool _isLoading = false;

  // Gesture recognition service
  final GestureRecognitionService _gestureService = GestureRecognitionService();
  static const String _pageId = 'login_page';

  // Accessibility state management
  String? _currentFocusedField;
  final Map<String, bool> _buttonConfirmationStates = {};
  final Map<String, FocusNode> _focusNodes = {};
  bool _hasAnnouncedPage = false;
  bool _isGestureServiceInitialized = false;

  // Always enable accessibility for login (we don't know user type yet)
  bool get _isAccessibilityEnabled => true;

  @override
  void initState() {
    super.initState();
    _initializeAccessibility();
    // Initialize gesture service immediately
    _initializeGestureServiceSync();
  }

  void _initializeAccessibility() {
    // Initialize focus nodes for text fields
    _focusNodes['email'] = FocusNode();
    _focusNodes['password'] = FocusNode();

    // Add focus listeners for each field
    _focusNodes.forEach((key, node) {
      node.addListener(() => _onFieldFocusChanged(key, node.hasFocus));
    });
  }

  void _initializeGestureServiceSync() {
    if (!_isAccessibilityEnabled) return;

    // Set initialization flag immediately so accessibility works right away
    _isGestureServiceInitialized = true;

    // Initialize gesture service asynchronously
    _initializeGestureService();

    // Announce page immediately, don't wait for gesture service
    _announceCurrentPageImmediate();
  }

  Future<void> _initializeGestureService() async {
    if (!_isAccessibilityEnabled) return;

    try {
      await _gestureService.initialize();
      _gestureService.setGestureCallback(_handleGesture);
      _gestureService.setActiveAnnouncementSource(_pageId);
      debugPrint('Gesture service initialized successfully');
    } catch (e) {
      debugPrint('Failed to initialize gesture service: $e');
      // Keep accessibility features enabled even if gesture service fails
    }
  }

  Future<void> _announceCurrentPageImmediate() async {
    if (!_isAccessibilityEnabled) return;

    // Ensure we only announce once per page visit
    if (_hasAnnouncedPage) return;

    // Wait for page to load, then announce immediately
    await Future.delayed(const Duration(milliseconds: 300));

    if (mounted && !_isLoading) {
      _hasAnnouncedPage = true;

      // Try to announce, with immediate fallback
      try {
        await _gestureService.initialize();
        _gestureService.setActiveAnnouncementSource(_pageId);
        await _gestureService.speak(
            'Login page. Audio guidance is active. Welcome back! Enter your email and password to sign in. All text fields and buttons will provide audio feedback.',
            pageId: _pageId
        );
      } catch (e) {
        debugPrint('Error in immediate page announcement: $e');
      }
    }
  }

  Future<void> _announceCurrentPage() async {
    if (!_isAccessibilityEnabled) return;

    // Ensure we only announce once per page visit
    if (_hasAnnouncedPage) return;

    // Wait a bit for page to load, then announce immediately
    await Future.delayed(const Duration(milliseconds: 300));

    if (mounted && !_isLoading) {
      _hasAnnouncedPage = true;

      // Always try to announce, even if gesture service isn't fully initialized
      try {
        await _gestureService.initialize();
        _gestureService.setActiveAnnouncementSource(_pageId);
        await _gestureService.speak(
            'Login page. Audio guidance is now active. Welcome back! Enter your email and password to sign in. Swipe left to go back. Draw a circle to repeat this announcement.',
            pageId: _pageId
        );
      } catch (e) {
        debugPrint('Error in page announcement: $e');
      }
    }
  }

  void _handleGesture(GestureType gestureType) {
    debugPrint('Gesture detected: $gestureType');

    switch (gestureType) {
      case GestureType.swipeLeft:
        _navigateBack();
        break;
      case GestureType.circleGesture:
        _repeatPageAnnouncement();
        break;
      default:
        break;
    }
  }

  Future<void> _repeatPageAnnouncement() async {
    if (!_isAccessibilityEnabled || !_isGestureServiceInitialized) return;

    debugPrint('Circle gesture detected - repeating page announcement');

    // Provide haptic feedback for circle gesture
    _provideHapticFeedback('double');

    // Stop any ongoing speech first
    _gestureService.stopAllAnnouncements();

    // Wait a moment then announce
    await Future.delayed(const Duration(milliseconds: 300));

    if (mounted && _gestureService.canMakeAnnouncements(_pageId)) {
      String announcement = 'Login page. Welcome back! Enter your email and password to sign in to your account. Click the Sign In button when ready. Swipe left to go back.';
      await _gestureService.speak(announcement, pageId: _pageId);
    }
  }

  void _navigateBack() {
    if (_isAccessibilityEnabled && _isGestureServiceInitialized) {
      _gestureService.clearActiveAnnouncementSource(_pageId);
    }
    Navigator.pop(context);
  }

  // Accessibility Methods
  void _onFieldFocusChanged(String fieldName, bool hasFocus) {
    // Always provide haptic and audio feedback, don't check initialization status
    if (hasFocus) {
      _currentFocusedField = fieldName;
      _provideHapticFeedback('light');
      _announceFieldSelection(fieldName);
    } else {
      if (_currentFocusedField == fieldName) {
        _currentFocusedField = null;
      }
    }
  }

  Future<void> _announceFieldSelection(String fieldName) async {
    String announcement = '';
    String guidance = '';

    switch (fieldName) {
      case 'email':
        announcement = 'Email field selected';
        guidance = 'Enter your registered email address';
        break;
      case 'password':
        announcement = 'Password field selected';
        guidance = 'Enter your password';
        break;
    }

    // Always try to speak, with fallback if gesture service isn't ready
    try {
      if (_isGestureServiceInitialized && _gestureService.canMakeAnnouncements(_pageId)) {
        await _gestureService.speak('$announcement. $guidance. Text input is ready.', pageId: _pageId);
      } else {
        // Fallback: Try to initialize and speak
        await _gestureService.initialize();
        _gestureService.setActiveAnnouncementSource(_pageId);
        await _gestureService.speak('$announcement. $guidance. Text input is ready.', pageId: _pageId);
      }
    } catch (e) {
      debugPrint('Error making field announcement: $e');
    }
  }

  void _provideHapticFeedback(String intensity) {
    // Always provide haptic feedback immediately, no checks needed
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
    // Always provide immediate haptic feedback
    _provideHapticFeedback('medium');

    // For accessibility mode, use double-click confirmation
    bool isConfirmed = _buttonConfirmationStates[buttonName] ?? false;

    if (!isConfirmed) {
      // First click - provide confirmation prompt
      _buttonConfirmationStates[buttonName] = true;

      String confirmationMessage = '';
      switch (buttonName) {
        case 'sign_in':
          confirmationMessage = 'Sign In button selected. Click again to confirm and log in to your account.';
          break;
        case 'remember_password':
          confirmationMessage = _rememberPassword
              ? 'Remember Password checkbox. Currently checked. Click again to uncheck.'
              : 'Remember Password checkbox. Currently unchecked. Click again to check.';
          break;
        default:
          confirmationMessage = '$buttonName button selected. Click again to confirm.';
      }

      // Always try to speak, with fallback if gesture service isn't ready
      try {
        if (_isGestureServiceInitialized && _gestureService.canMakeAnnouncements(_pageId)) {
          await _gestureService.speak(confirmationMessage, pageId: _pageId);
        } else {
          // Fallback: Try to initialize and speak
          await _gestureService.initialize();
          _gestureService.setActiveAnnouncementSource(_pageId);
          await _gestureService.speak(confirmationMessage, pageId: _pageId);
        }
      } catch (e) {
        debugPrint('Error making button announcement: $e');
      }

      // Reset confirmation state after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _buttonConfirmationStates[buttonName] = false;
          });
        }
      });
    } else {
      // Second click - execute action
      _buttonConfirmationStates[buttonName] = false;
      _provideHapticFeedback('heavy');

      // Announce confirmation
      try {
        if (_isGestureServiceInitialized && _gestureService.canMakeAnnouncements(_pageId)) {
          await _gestureService.speak('Action confirmed.', pageId: _pageId);
        } else {
          // Fallback: Try to initialize and speak
          await _gestureService.initialize();
          _gestureService.setActiveAnnouncementSource(_pageId);
          await _gestureService.speak('Action confirmed.', pageId: _pageId);
        }
      } catch (e) {
        debugPrint('Error making confirmation announcement: $e');
      }

      action();
    }
  }

  void _showSnackBar(String message, {bool isError = false}) async {
    if (!mounted) return;

    // Always try to announce messages, with fallback if gesture service isn't ready
    try {
      if (_isGestureServiceInitialized && _gestureService.canMakeAnnouncements(_pageId)) {
        await _gestureService.speak(message, pageId: _pageId);
      } else {
        // Fallback: Try to initialize and speak
        await _gestureService.initialize();
        _gestureService.setActiveAnnouncementSource(_pageId);
        await _gestureService.speak(message, pageId: _pageId);
      }
    } catch (e) {
      debugPrint('Error making snackbar announcement: $e');
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Future<void> _signIn() async {
    // Validate inputs
    if (_emailController.text.trim().isEmpty || _passwordController.text.trim().isEmpty) {
      _showSnackBar('Please enter both email and password', isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // Announce sign in start for accessibility users
    if (_isAccessibilityEnabled && _isGestureServiceInitialized) {
      await _gestureService.speak('Signing you in, please wait.', pageId: _pageId);
    }

    try {
      final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // Get user type from Firestore
      final doc = await FirebaseFirestore.instance
          .collection('userprofile')
          .doc(userCredential.user!.uid)
          .get();

      if (mounted) {
        String userType = doc.data()?['userType'] ?? 'blind_user';

        // Announce successful login
        if (_isAccessibilityEnabled && _isGestureServiceInitialized) {
          String welcomeMessage = userType == 'caregiver'
              ? 'Welcome back! Redirecting to caregiver dashboard.'
              : 'Welcome back! Redirecting to your home page.';
          await _gestureService.speak(welcomeMessage, pageId: _pageId);
        }

        // Wait a moment for the announcement
        await Future.delayed(const Duration(milliseconds: 1500));

        if (userType == 'caregiver') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const CaregiverHomeScreen()),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
        }
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'An error occurred';

      switch (e.code) {
        case 'user-not-found':
          errorMessage = 'No account found with this email address';
          break;
        case 'wrong-password':
          errorMessage = 'Incorrect password';
          break;
        case 'invalid-email':
          errorMessage = 'Please enter a valid email address';
          break;
        case 'user-disabled':
          errorMessage = 'This account has been disabled';
          break;
        default:
          errorMessage = e.message ?? 'An error occurred';
      }

      _showSnackBar(errorMessage, isError: true);
    } catch (e) {
      _showSnackBar('An unexpected error occurred', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    // Stop all announcements and clear announcement sources
    if (_isGestureServiceInitialized) {
      _gestureService.stopAllAnnouncements();
      _gestureService.clearActiveAnnouncementSource(_pageId);
      _gestureService.clearGestureCallback();
    }

    // Dispose controllers
    _emailController.dispose();
    _passwordController.dispose();

    // Dispose focus nodes
    _focusNodes.forEach((key, node) {
      node.dispose();
    });

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isAccessibilityEnabled && _isGestureServiceInitialized
          ? GestureDetector(
        onPanStart: (details) {
          _gestureService.startGesture(details.localPosition);
        },
        onPanUpdate: (details) {
          _gestureService.updateGesture(details.localPosition);
        },
        onPanEnd: (details) {
          _gestureService.endGesture();
        },
        child: _buildMainContent(),
      )
          : _buildMainContent(),
    );
  }

  Widget _buildMainContent() {
    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Welcome',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C3E50),
                ),
              ),
              const SizedBox(height: 48),

              // Email Field
              const Text(
                'Email',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2C3E50),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: TextField(
                  controller: _emailController,
                  focusNode: _focusNodes['email'],
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    hintText: 'Enter Email Address',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onTap: () {
                    _provideHapticFeedback('light');
                  },
                ),
              ),
              const SizedBox(height: 24),

              // Password Field
              const Text(
                'Password',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2C3E50),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: TextField(
                  controller: _passwordController,
                  focusNode: _focusNodes['password'],
                  obscureText: true,
                  decoration: const InputDecoration(
                    hintText: 'Enter Password',
                    prefixIcon: Icon(Icons.lock_outline),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onTap: () {
                    _provideHapticFeedback('light');
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Remember Password Checkbox
              GestureDetector(
                onTap: () async {
                  await _handleButtonClick('remember_password', () {
                    setState(() {
                      _rememberPassword = !_rememberPassword;
                    });
                  });
                },
                child: Row(
                  children: [
                    Checkbox(
                      value: _rememberPassword,
                      onChanged: (value) async {
                        await _handleButtonClick('remember_password', () {
                          setState(() {
                            _rememberPassword = value ?? false;
                          });
                        });
                      },
                      activeColor: const Color(0xFF2561FA),
                    ),
                    const Text(
                      'Remember Password',
                      style: TextStyle(
                        color: Color(0xFF2C3E50),
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Sign In Button
              Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFF2561FA),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: TextButton(
                  onPressed: _isLoading ? null : () async {
                    await _handleButtonClick('sign_in', _signIn);
                  },
                  child: _isLoading
                      ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                      : const Text(
                    'Sign In',
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
        if (_isLoading)
          Container(
            color: Colors.black12,
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          ),
      ],
    );
  }
}