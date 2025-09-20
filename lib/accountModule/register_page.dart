import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:vibration/vibration.dart';
import '../home.dart';
import 'caregiver_home.dart';
import '../gesture_recognition_service.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emergencyContactController = TextEditingController();
  bool _isLoading = false;
  String _selectedUserType = 'blind_user'; // Default to blind user

  // Gesture recognition service
  final GestureRecognitionService _gestureService = GestureRecognitionService();
  static const String _pageId = 'register_page';

  // Accessibility state management
  String? _currentFocusedField;
  final Map<String, bool> _buttonConfirmationStates = {};
  final Map<String, FocusNode> _focusNodes = {};
  bool _hasAnnouncedPage = false;
  bool _isGestureServiceInitialized = false;

  // Always enable accessibility initially (since default is blind_user)
  bool get _isAccessibilityEnabled => _selectedUserType == 'blind_user';

  @override
  void initState() {
    super.initState();
    _initializeAccessibility();
    // Initialize gesture service immediately since default is blind_user
    _initializeGestureServiceSync();
  }

  void _initializeAccessibility() {
    // Initialize focus nodes for text fields
    _focusNodes['username'] = FocusNode();
    _focusNodes['email'] = FocusNode();
    _focusNodes['password'] = FocusNode();
    _focusNodes['phone'] = FocusNode();
    _focusNodes['emergency'] = FocusNode();

    // Add focus listeners for each field
    _focusNodes.forEach((key, node) {
      node.addListener(() => _onFieldFocusChanged(key, node.hasFocus));
    });
  }

  void _initializeGestureServiceSync() {
    if (!_isAccessibilityEnabled) return;

    // Set initialization flag immediately
    _isGestureServiceInitialized = true;

    // Initialize asynchronously but don't wait for it
    _initializeGestureService();
  }

  Future<void> _initializeGestureService() async {
    if (!_isAccessibilityEnabled) return;

    try {
      await _gestureService.initialize();
      _gestureService.setGestureCallback(_handleGesture);
      _gestureService.setActiveAnnouncementSource(_pageId);

      // Announce page after initialization
      _announceCurrentPage();
    } catch (e) {
      debugPrint('Failed to initialize gesture service: $e');
      // Even if gesture service fails, keep accessibility features enabled
      _isGestureServiceInitialized = true;
    }
  }

  Future<void> _announceCurrentPage() async {
    if (!_isAccessibilityEnabled) return;

    // Ensure we only announce once per page visit
    if (_hasAnnouncedPage) return;

    // Wait for page to load, then announce immediately
    await Future.delayed(const Duration(milliseconds: 300));

    if (mounted && !_isLoading) {
      _hasAnnouncedPage = true;

      // Always try to announce, even if gesture service isn't fully initialized
      try {
        await _gestureService.initialize();
        _gestureService.setActiveAnnouncementSource(_pageId);
        await _gestureService.speak(
            'Registration page. Audio guidance is now active. Create a new account by filling in your information. Choose your user type and complete all required fields. Swipe left to go back. Draw a circle to repeat this announcement.',
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
    await Future.delayed(const Duration(milliseconds: 1000));

    if (mounted && _gestureService.canMakeAnnouncements(_pageId)) {
      String announcement = 'Registration page. Create a new account by filling in your information. Choose between Blind User and Caregiver account types. Fill in all required fields and click Register when ready. Swipe left to go back.';
      await _gestureService.speak(announcement, pageId: _pageId);
    }
  }

  void _navigateBack() {
    if (_isAccessibilityEnabled && _isGestureServiceInitialized) {
      _gestureService.clearActiveAnnouncementSource(_pageId);
    }
    Navigator.pop(context);
  }

  // Called when user type changes to reinitialize accessibility
  Future<void> _onUserTypeChanged(String newUserType) async {
    String oldUserType = _selectedUserType;
    setState(() {
      _selectedUserType = newUserType;
    });

    if (newUserType == 'blind_user' && oldUserType != 'blind_user') {
      // Switching to blind user - initialize accessibility
      _hasAnnouncedPage = false;
      _isGestureServiceInitialized = false;
      await _initializeGestureService();

      // Announce the change and inform user that accessibility is now active
      if (_isGestureServiceInitialized) {
        await _gestureService.speak(
            'Blind User selected. Audio guidance is now active. All buttons and text fields will provide audio feedback when you interact with them.',
            pageId: _pageId
        );
      }
    } else if (newUserType == 'caregiver' && oldUserType == 'blind_user') {
      // Switching to caregiver - disable accessibility
      if (_isGestureServiceInitialized) {
        await _gestureService.speak(
            'Caregiver selected. Accessibility features are now disabled.',
            pageId: _pageId
        );

        // Wait for announcement to finish before disabling
        await Future.delayed(const Duration(milliseconds: 2000));

        _gestureService.stopAllAnnouncements();
        _gestureService.clearActiveAnnouncementSource(_pageId);
        _gestureService.clearGestureCallback();
        _isGestureServiceInitialized = false;
        _hasAnnouncedPage = false;
      }
    }
  }

  // Accessibility Methods
  void _onFieldFocusChanged(String fieldName, bool hasFocus) {
    if (!_isAccessibilityEnabled) return;

    if (hasFocus) {
      _currentFocusedField = fieldName;
      _announceFieldSelection(fieldName);
      _provideHapticFeedback('light');
    } else {
      if (_currentFocusedField == fieldName) {
        _currentFocusedField = null;
      }
    }
  }

  Future<void> _announceFieldSelection(String fieldName) async {
    if (!_isAccessibilityEnabled) return;

    String announcement = '';
    String guidance = '';

    switch (fieldName) {
      case 'username':
        announcement = 'Username field selected';
        guidance = 'Enter your display name';
        break;
      case 'email':
        announcement = 'Email field selected';
        guidance = 'Enter your email address';
        break;
      case 'password':
        announcement = 'Password field selected';
        guidance = 'Enter a secure password';
        break;
      case 'phone':
        announcement = 'Phone number field selected';
        guidance = 'Enter your phone number - optional';
        break;
      case 'emergency':
        announcement = 'Emergency contact field selected';
        guidance = 'Enter emergency contact phone number - required for blind users';
        break;
    }

    // Always try to announce, with fallback if gesture service isn't ready
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
    // Provide haptic feedback for all users, not just accessibility mode
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
    // For non-accessibility mode (caregiver), execute action directly with haptic feedback
    if (!_isAccessibilityEnabled) {
      _provideHapticFeedback('medium');
      action();
      return;
    }

    // For accessibility mode (blind user), use double-click confirmation
    bool isConfirmed = _buttonConfirmationStates[buttonName] ?? false;

    if (!isConfirmed) {
      // First click - provide confirmation prompt
      _buttonConfirmationStates[buttonName] = true;
      _provideHapticFeedback('medium');

      String confirmationMessage = '';
      switch (buttonName) {
        case 'register':
          confirmationMessage = 'Register button selected. Click again to confirm and create your account.';
          break;
        case 'user_type_blind':
          confirmationMessage = 'Blind User option selected. Click again to confirm selection.';
          break;
        case 'user_type_caregiver':
          confirmationMessage = 'Caregiver option selected. Click again to confirm selection.';
          break;
        default:
          confirmationMessage = '$buttonName button selected. Click again to confirm.';
      }

      // Always try to announce, with fallback if gesture service isn't ready
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

    // Announce the message for accessibility users - always try with fallback
    if (_isAccessibilityEnabled) {
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

  Future<void> _register() async {
    // Validate inputs
    if (_usernameController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      _showSnackBar('Please fill in all required fields', isError: true);
      return;
    }

    // Validate emergency contact for blind users
    if (_selectedUserType == 'blind_user' && _emergencyContactController.text.trim().isEmpty) {
      _showSnackBar('Emergency contact is required for blind users', isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // Announce registration start for accessibility users
    if (_isAccessibilityEnabled && _isGestureServiceInitialized) {
      await _gestureService.speak('Creating your account, please wait.', pageId: _pageId);
    }

    try {
      // Create user with email and password
      final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // Store additional user data in Firestore collection named "userprofile"
      final firestore = FirebaseFirestore.instance;

      await firestore.collection('userprofile').doc(userCredential.user!.uid).set({
        'username': _usernameController.text.trim(),
        'email': _emailController.text.trim(),
        'password': _passwordController.text.trim(), // Note: In production, never store plain text passwords
        'phone': _phoneController.text.trim(),
        'emergencyContact': _emergencyContactController.text.trim(),
        'userType': _selectedUserType, // Store user type
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        // Show success message on the same page
        _showSnackBar('Successfully registered! Redirecting to your home page.');

        // Wait for snackbar to be visible
        await Future.delayed(const Duration(seconds: 2));

        // Navigate to appropriate home screen based on user type
        if (mounted) {
          if (_selectedUserType == 'caregiver') {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => const CaregiverHomeScreen()),
                  (route) => false,
            );
          } else {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => const HomeScreen()),
                  (route) => false,
            );
          }
        }
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'An error occurred';

      switch (e.code) {
        case 'weak-password':
          errorMessage = 'The password provided is too weak';
          break;
        case 'email-already-in-use':
          errorMessage = 'An account already exists for that email';
          break;
        case 'invalid-email':
          errorMessage = 'Please enter a valid email address';
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
    // Stop all announcements and clear announcement sources only if accessibility was enabled
    if (_isGestureServiceInitialized) {
      _gestureService.stopAllAnnouncements();
      _gestureService.clearActiveAnnouncementSource(_pageId);
      _gestureService.clearGestureCallback();
    }

    // Dispose controllers
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _emergencyContactController.dispose();

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
                'Create A New Account',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C3E50),
                ),
              ),
              const SizedBox(height: 32),

              // User Type Selection
              const Text(
                'I am a',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2C3E50),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        await _handleButtonClick('user_type_blind', () {
                          _onUserTypeChanged('blind_user');
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _selectedUserType == 'blind_user'
                              ? const Color(0xFF2561FA)
                              : Colors.grey[200],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _selectedUserType == 'blind_user'
                                ? const Color(0xFF2561FA)
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.accessibility,
                              color: _selectedUserType == 'blind_user'
                                  ? Colors.white
                                  : Colors.grey.shade600,
                              size: 32,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Blind User',
                              style: TextStyle(
                                color: _selectedUserType == 'blind_user'
                                    ? Colors.white
                                    : Colors.grey.shade600,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        await _handleButtonClick('user_type_caregiver', () {
                          _onUserTypeChanged('caregiver');
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _selectedUserType == 'caregiver'
                              ? const Color(0xFF2561FA)
                              : Colors.grey[200],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _selectedUserType == 'caregiver'
                                ? const Color(0xFF2561FA)
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.favorite,
                              color: _selectedUserType == 'caregiver'
                                  ? Colors.white
                                  : Colors.grey.shade600,
                              size: 32,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Caregiver',
                              style: TextStyle(
                                color: _selectedUserType == 'caregiver'
                                    ? Colors.white
                                    : Colors.grey.shade600,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Username Field
              const Text(
                'Username',
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
                  controller: _usernameController,
                  focusNode: _focusNodes['username'],
                  decoration: const InputDecoration(
                    hintText: 'Enter Username',
                    prefixIcon: Icon(Icons.person_outline),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onTap: () {
                    _provideHapticFeedback('light');
                  },
                ),
              ),
              const SizedBox(height: 24),

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
              const SizedBox(height: 24),

              // Phone Field
              const Text(
                'Phone Number (Optional)',
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
                  controller: _phoneController,
                  focusNode: _focusNodes['phone'],
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    hintText: 'Enter Phone Number',
                    prefixIcon: Icon(Icons.phone_outlined),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onTap: () {
                    _provideHapticFeedback('light');
                  },
                ),
              ),
              const SizedBox(height: 24),

              // Emergency Contact Field (only for blind users)
              if (_selectedUserType == 'blind_user') ...[
                const Text(
                  'Emergency Contact *',
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
                    controller: _emergencyContactController,
                    focusNode: _focusNodes['emergency'],
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      hintText: 'Enter Emergency Contact Number',
                      prefixIcon: Icon(Icons.emergency_outlined),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onTap: () {
                      _provideHapticFeedback('light');
                    },
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Register Button
              Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFF2561FA),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: TextButton(
                  onPressed: _isLoading ? null : () async {
                    await _handleButtonClick('register', _register);
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
                    'Register',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
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