import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vibration/vibration.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'caregiver_services.dart';
import 'auth_gate.dart';
import 'connection_requests_screen.dart';
import '../gesture_recognition_service.dart';
import '../home.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({Key? key}) : super(key: key);

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emergencyContactController = TextEditingController();

  bool _isLoading = false;
  bool _isEditing = false;
  String? _profileImageUrl;
  String _userType = 'blind_user';
  String? _caregiverEmail;
  String? _caregiverId;
  final _caregiverEmailController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  bool _isUploadingImage = false;

  // Gesture recognition service
  final GestureRecognitionService _gestureService = GestureRecognitionService();
  static const String _pageId = 'user_profile';

  // Accessibility state management
  String? _currentFocusedField;
  Map<String, bool> _buttonConfirmationStates = {};
  bool _isAudioFeedbackEnabled = true;
  Map<String, FocusNode> _focusNodes = {};
  bool _hasAnnouncedPage = false;

  @override
  void initState() {
    super.initState();
    _initializeAccessibility();
    _initializeGestureService();
    _loadUserData();
  }

  void _initializeAccessibility() {
    // Initialize focus nodes for text fields
    _focusNodes['username'] = FocusNode();
    _focusNodes['email'] = FocusNode();
    _focusNodes['password'] = FocusNode();
    _focusNodes['phone'] = FocusNode();
    _focusNodes['emergency'] = FocusNode();
    _focusNodes['caregiver'] = FocusNode();
    
    // Add focus listeners for each field
    _focusNodes.forEach((key, node) {
      node.addListener(() => _onFieldFocusChanged(key, node.hasFocus));
    });
  }

  Future<void> _initializeGestureService() async {
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
    // Ensure we only announce once per page visit
    if (_hasAnnouncedPage) return;
    
    // Wait for page to fully load and any loading states to complete
    await Future.delayed(const Duration(milliseconds: 800));
    
    if (mounted && _gestureService.canMakeAnnouncements(_pageId) && !_isLoading) {
      _hasAnnouncedPage = true;
      await _gestureService.speak(
        'User Profile page. Manage your personal information, account settings, and caregiver connections. Swipe left to go back to home. Draw a circle to repeat this announcement.',
        pageId: _pageId
      );
    }
  }

  void _handleGesture(GestureType gestureType) {
    debugPrint('Gesture detected: $gestureType');
    
    switch (gestureType) {
      case GestureType.swipeLeft:
        _navigateToHome();
        break;
      case GestureType.circleGesture:
        _repeatPageAnnouncement();
        break;
      default:
        break;
    }
  }

  Future<void> _repeatPageAnnouncement() async {
    debugPrint('Circle gesture detected - repeating page announcement');
    
    // Provide haptic feedback for circle gesture
    _provideHapticFeedback('double');
    
    // Stop any ongoing speech first
    _gestureService.stopAllAnnouncements();
    
    // Wait a moment then announce
    await Future.delayed(const Duration(milliseconds: 300));
    
    if (mounted && _gestureService.canMakeAnnouncements(_pageId)) {
      String announcement = '';
      
      if (_isEditing) {
        announcement = 'User Profile page - Edit Mode. You are currently editing your profile information. Fill in the fields and click Save Changes when done. Swipe left to return to the home page.';
      } else {
        announcement = 'User Profile page - View Mode. Your personal information is displayed. Click Edit Profile to make changes. Swipe left to return to the home page.';
      }
      
      await _gestureService.speak(announcement, pageId: _pageId);
    }
  }

  void _navigateToHome() {
    _gestureService.clearActiveAnnouncementSource(_pageId);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const HomeScreen()),
    );
  }

  // Accessibility Methods
  void _onFieldFocusChanged(String fieldName, bool hasFocus) {
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
    if (!_isAudioFeedbackEnabled) return;
    
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
        guidance = 'Enter a new password to change it';
        break;
      case 'phone':
        announcement = 'Phone number field selected';
        guidance = 'Enter your phone number';
        break;
      case 'emergency':
        announcement = 'Emergency contact field selected';
        guidance = 'Enter emergency contact phone number';
        break;
      case 'caregiver':
        announcement = 'Caregiver email field selected';
        guidance = 'Enter caregiver email address';
        break;
    }
    
    await _gestureService.speak('$announcement. $guidance. Text input is ready.', pageId: _pageId);
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
      // First click - provide confirmation prompt
      _buttonConfirmationStates[buttonName] = true;
      _provideHapticFeedback('medium');
      
      String confirmationMessage = '';
      switch (buttonName) {
        case 'edit_profile':
          confirmationMessage = 'Edit Profile button selected. Click again to confirm and start editing.';
          break;
        case 'logout':
          confirmationMessage = 'Logout button selected. Click again to confirm and logout.';
          break;
        case 'save_profile':
          confirmationMessage = 'Save Profile button selected. Click again to confirm and save changes.';
          break;
        case 'add_caregiver':
          confirmationMessage = 'Add Caregiver button selected. Click again to confirm and send request.';
          break;
        case 'remove_caregiver':
          confirmationMessage = 'Remove Caregiver button selected. Click again to confirm removal.';
          break;
        default:
          confirmationMessage = '$buttonName button selected. Click again to confirm.';
      }
      
      await _gestureService.speak(confirmationMessage, pageId: _pageId);
      
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
      await _gestureService.speak('Action confirmed.', pageId: _pageId);
      action();
    }
  }

  Future<void> _loadUserData() async {
    setState(() { _isLoading = true; });
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (mounted) {
        setState(() { _isLoading = false; });
        _showSnackBar('User not authenticated', isError: true);
      }
      return;
    }

    try {
      print('Loading user data for UID: ${user.uid}');

      // Fetch data from "userprofile" collection
      final doc = await FirebaseFirestore.instance
          .collection('userprofile')
          .doc(user.uid)
          .get();

      print('Document exists: ${doc.exists}');

      if (doc.exists && mounted) {
        final data = doc.data();
        print('Document data: $data');

        setState(() {
          // Safely extract data with null checks
          _usernameController.text = data?['username']?.toString() ?? '';
          _emailController.text = data?['email']?.toString() ?? user.email ?? '';
          _passwordController.text = ''; // Never display password
          _phoneController.text = data?['phone']?.toString() ?? '';
          _emergencyContactController.text = data?['emergencyContact']?.toString() ?? '';
          // Check for base64 image first, then fallback to URL
          if (data?['profileImageBase64'] != null) {
            // Store base64 data for display
            _profileImageUrl = 'data:image/jpeg;base64,${data?['profileImageBase64']}';
            print('Profile image loaded from base64 data');
          } else if (data?['profileImage'] != null) {
            // Fallback to URL if no base64
            _profileImageUrl = data?['profileImage']?.toString();
            print('Profile image loaded from URL');
          } else {
            _profileImageUrl = null;
            print('No profile image found');
          }
          _userType = data?['userType']?.toString() ?? 'blind_user';
          _caregiverEmail = data?['caregiverEmail']?.toString();
          _caregiverId = data?['caregiverId']?.toString();
        });

        print('Profile data loaded successfully');
        print('User type: $_userType');
        print('Caregiver email: $_caregiverEmail');

      } else if (!doc.exists && mounted) {
        print('User profile document does not exist, creating default profile');

        // Create a default profile if it doesn't exist
        await _createDefaultProfile(user);

        // Reload data after creating default profile
        await _loadUserData();
        return;
      }
    } catch (e) {
      print('Error loading user data: $e');
      if (mounted) {
        _showSnackBar('Error loading profile data: ${e.toString()}', isError: true);
      }
    }

    if (mounted) {
      setState(() { _isLoading = false; });
    }
  }

  Future<void> _createDefaultProfile(User user) async {
    try {
      print('Creating default profile for user: ${user.uid}');

      final defaultData = {
        'username': user.displayName ?? '',
        'email': user.email ?? '',
        'phone': '',
        'emergencyContact': '',
        'userType': 'blind_user', // Default to blind user
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('userprofile')
          .doc(user.uid)
          .set(defaultData);

      print('Default profile created successfully');

    } catch (e) {
      print('Error creating default profile: $e');
      throw Exception('Failed to create user profile: $e');
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  // Email validation method
  bool _isValidEmail(String email) {
    final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    return emailRegex.hasMatch(email);
  }

  // Phone number validation method
  bool _isValidPhone(String phone) {
    // Remove all non-digit characters
    final digitsOnly = phone.replaceAll(RegExp(r'[^\d]'), '');
    // Check if it's 10 or 11 digits
    return digitsOnly.length >= 10 && digitsOnly.length <= 11;
  }

  // Clean phone number (remove symbols)
  String _cleanPhoneNumber(String phone) {
    return phone.replaceAll(RegExp(r'[^\d]'), '');
  }

  Future<void> _saveProfile() async {
    // Comprehensive validation
    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final emergencyContact = _emergencyContactController.text.trim();

    // Check if required fields are filled (except password)
    if (username.isEmpty) {
      _showSnackBar('Username is required', isError: true);
      return;
    }

    if (phone.isEmpty) {
      _showSnackBar('Phone number is required', isError: true);
      return;
    }

    if (emergencyContact.isEmpty) {
      _showSnackBar('Emergency contact is required', isError: true);
      return;
    }

    // Validate phone number
    if (!_isValidPhone(phone)) {
      _showSnackBar('Phone number must be 10 or 11 digits only (no symbols)', isError: true);
      return;
    }

    // Validate emergency contact
    if (!_isValidPhone(emergencyContact)) {
      _showSnackBar('Emergency contact must be 10 or 11 digits only (no symbols)', isError: true);
      return;
    }

    setState(() { _isLoading = true; });
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (mounted) {
        setState(() { _isLoading = false; });
        _showSnackBar('User not authenticated', isError: true);
      }
      return;
    }

    try {
      print('Saving profile for user: ${user.uid}');

      // Prepare update data with cleaned phone numbers
      final updateData = <String, dynamic>{
        'username': username,
        'email': email,
        'phone': _cleanPhoneNumber(phone),
        'emergencyContact': _cleanPhoneNumber(emergencyContact),
        'userType': _userType,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Only update password if a new one is provided
      if (_passwordController.text.trim().isNotEmpty) {
        updateData['password'] = _passwordController.text.trim();
      }

      // Preserve existing caregiver data if it exists
      if (_caregiverId != null) {
        updateData['caregiverId'] = _caregiverId;
      }
      if (_caregiverEmail != null) {
        updateData['caregiverEmail'] = _caregiverEmail;
      }

      print('Update data: $updateData');

      // Check if document exists, if not create it
      final docRef = FirebaseFirestore.instance.collection('userprofile').doc(user.uid);
      final docSnapshot = await docRef.get();

      if (docSnapshot.exists) {
        await docRef.update(updateData);
        print('Profile updated successfully');
      } else {
        // If document doesn't exist, create it
        updateData['createdAt'] = FieldValue.serverTimestamp();
        await docRef.set(updateData);
        print('Profile created successfully');
      }



      // Update password if not empty
      if (_passwordController.text.trim().isNotEmpty) {
        try {
          await user.updatePassword(_passwordController.text.trim());
          print('FirebaseAuth password updated');
        } catch (authError) {
          print('Error updating FirebaseAuth password: $authError');
          // Continue even if auth password update fails
        }
      }

      if (mounted) {
        setState(() {
          _isEditing = false;
          _passwordController.text = ''; // Clear password field after update
        });

        _showSnackBar('Profile updated successfully!');

        // Reload data to ensure UI is in sync
        await _loadUserData();
      }

    } catch (e) {
      print('Error saving profile: $e');
      if (mounted) {
        _showSnackBar('Error updating profile: ${e.toString()}', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  Future<void> _addCaregiver() async {
    final email = _caregiverEmailController.text.trim();
    if (email.isEmpty) {
      _showSnackBar('Please enter caregiver email address', isError: true);
      return;
    }

    if (!_isValidEmail(email)) {
      _showSnackBar('Please enter a valid email address', isError: true);
      return;
    }

    setState(() { _isLoading = true; });

    try {
      print('Adding caregiver: $email');
      await CaregiverServices.addCaregiverConnection(caregiverEmail: email);

      if (mounted) {
        _showSnackBar('Caregiver connection request sent successfully!');
        _caregiverEmailController.clear();

        // Reload user data to get updated caregiver info
        await _loadUserData();
      }
    } catch (e) {
      print('Error adding caregiver: $e');
      if (mounted) {
        _showSnackBar('Error: ${e.toString()}', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  Future<void> _pickAndUploadImage() async {
    try {
      setState(() {
        _isUploadingImage = true;
      });

      // Pick image from gallery
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );

      if (image == null) {
        setState(() {
          _isUploadingImage = false;
        });
        _showSnackBar('No image selected', isError: true);
        print('No image selected');
        return;
      }

      // Show the image immediately
      setState(() {
        _profileImageUrl = image.path;
      });

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showSnackBar('User not authenticated', isError: true);
        setState(() {
          _isUploadingImage = false;
        });
        print('User not authenticated');
        return;
      }

      // Convert image to base64 for storage in Firestore
      final File imageFile = File(image.path);
      final List<int> imageBytes = await imageFile.readAsBytes();
      final String base64Image = base64Encode(imageBytes);

      print('Image size: ${imageBytes.length} bytes');
      print('Base64 size: ${base64Image.length} characters');

      // Check if image is too large for Firestore (1MB limit)
      if (base64Image.length > 1000000) {
        _showSnackBar('Image too large. Please choose a smaller image.', isError: true);
        setState(() {
          _isUploadingImage = false;
        });
        return;
      }

      // Update Firestore with the base64 image data
      try {
        await FirebaseFirestore.instance
            .collection('userprofile')
            .doc(user.uid)
            .update({
          'profileImageBase64': base64Image,
          'profileImage': null, // Clear any previous URL
          'updatedAt': FieldValue.serverTimestamp(),
        });
        print('Firestore updated with base64 image data');
      } catch (e) {
        print('Error updating Firestore: $e');
        _showSnackBar('Error updating Firestore: $e', isError: true);
        setState(() {
          _isUploadingImage = false;
        });
        return;
      }

      // Update local state to show the image
      setState(() {
        _profileImageUrl = image.path; // Keep local file path for display
        _isUploadingImage = false;
      });

      _showSnackBar('Profile image updated successfully!');
    } catch (e) {
      print('Error uploading image: $e');
      _showSnackBar('Error uploading image: ${e.toString()}', isError: true);
      setState(() {
        _isUploadingImage = false;
      });
    }
  }

  Future<void> _takePhotoAndUpload() async {
    try {
      setState(() {
        _isUploadingImage = true;
      });

      // Take photo with camera
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );

      if (image == null) {
        setState(() {
          _isUploadingImage = false;
        });
        _showSnackBar('No photo taken', isError: true);
        print('No photo taken');
        return;
      }

      // Show the image immediately
      setState(() {
        _profileImageUrl = image.path;
      });

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showSnackBar('User not authenticated', isError: true);
        setState(() {
          _isUploadingImage = false;
        });
        print('User not authenticated');
        return;
      }

      // Convert image to base64 for storage in Firestore
      final File imageFile = File(image.path);
      final List<int> imageBytes = await imageFile.readAsBytes();
      final String base64Image = base64Encode(imageBytes);

      print('Photo size: ${imageBytes.length} bytes');
      print('Base64 size: ${base64Image.length} characters');

      // Check if image is too large for Firestore (1MB limit)
      if (base64Image.length > 1000000) {
        _showSnackBar('Photo too large. Please take a smaller photo.', isError: true);
        setState(() {
          _isUploadingImage = false;
        });
        return;
      }

      // Update Firestore with the base64 image data
      try {
        await FirebaseFirestore.instance
            .collection('userprofile')
            .doc(user.uid)
            .update({
          'profileImageBase64': base64Image,
          'profileImage': null, // Clear any previous URL
          'updatedAt': FieldValue.serverTimestamp(),
        });
        print('Firestore updated with base64 photo data');
      } catch (e) {
        print('Error updating Firestore: $e');
        _showSnackBar('Error updating Firestore: $e', isError: true);
        setState(() {
          _isUploadingImage = false;
        });
        return;
      }

      // Update local state to show the image
      setState(() {
        _profileImageUrl = image.path; // Keep local file path for display
        _isUploadingImage = false;
      });

      _showSnackBar('Profile photo updated successfully!');
    } catch (e) {
      print('Error uploading photo: $e');
      _showSnackBar('Error uploading photo: ${e.toString()}', isError: true);
      setState(() {
        _isUploadingImage = false;
      });
    }
  }

  Future<void> _showImagePickerDialog() async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Update Profile Image'),
          content: const Text('Choose how you want to update your profile image'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _pickAndUploadImage();
              },
              child: const Text('Choose from Gallery'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _takePhotoAndUpload();
              },
              child: const Text('Take Photo'),
            ),
            if (_profileImageUrl != null)
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _removeProfileImage();
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Remove Image'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _removeProfileImage() async {
    try {
      setState(() {
        _isUploadingImage = true;
      });

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showSnackBar('User not authenticated', isError: true);
        setState(() {
          _isUploadingImage = false;
        });
        return;
      }

      // Update Firestore to remove image data
      await FirebaseFirestore.instance
          .collection('userprofile')
          .doc(user.uid)
          .update({
        'profileImage': null,
        'profileImageBase64': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Update local state
      setState(() {
        _profileImageUrl = null;
        _isUploadingImage = false;
      });

      _showSnackBar('Profile image removed successfully!');
    } catch (e) {
      print('Error removing image: $e');
      _showSnackBar('Error removing image: ${e.toString()}', isError: true);
      setState(() {
        _isUploadingImage = false;
      });
    }
  }

  Future<void> _logout() async {
    // Show confirmation dialog
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text('Are you sure you want to log out? You will be returned to the sign-in page.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              'Log Out',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (shouldLogout != true) return;

    setState(() { _isLoading = true; });

    try {
      print('Logging out user...');

      // Sign out from Firebase Auth
      await FirebaseAuth.instance.signOut();

      print('User logged out successfully');

      if (mounted) {
        // Navigate to auth gate and remove all previous routes
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const AuthGate()),
              (route) => false,
        );
      }
    } catch (e) {
      print('Error during logout: $e');
      if (mounted) {
        setState(() { _isLoading = false; });
        _showSnackBar('Error logging out: ${e.toString()}', isError: true);
      }
    }
  }

  Future<void> _removeCaregiver() async {
    // Show confirmation dialog
    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Caregiver'),
        content: const Text('Are you sure you want to remove your caregiver connection? They will no longer be able to monitor your location or receive emergency alerts.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (shouldRemove != true) return;

    setState(() { _isLoading = true; });

    try {
      await CaregiverServices.removeCaregiverConnection();
      _showSnackBar('Caregiver connection removed successfully');

      // Reload user data to get updated caregiver info
      await _loadUserData();
    } catch (e) {
      _showSnackBar('Error: ${e.toString()}', isError: true);
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  // View connection requests from caregivers
  void _viewConnectionRequests() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ConnectionRequestsScreen(),
      ),
    );
  }

  @override
  void dispose() {
    // Stop all announcements and clear announcement sources
    _gestureService.stopAllAnnouncements();
    _gestureService.clearActiveAnnouncementSource(_pageId);
    _gestureService.clearGestureCallback();
    
    // Dispose controllers
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _emergencyContactController.dispose();
    _caregiverEmailController.dispose();
    
    // Dispose focus nodes
    _focusNodes.forEach((key, node) {
      node.dispose();
    });
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF2561FA)))
            : SingleChildScrollView(
        child: Column(
          children: [
            // Blue header section
            Container(
              height: 320,
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFF2561FA),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(40),
                  bottomRight: Radius.circular(40),
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    // Back button and title
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ),
                          const Expanded(
                            child: Center(
                              child: Text(
                                'Your Profile',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: IconButton(
                              icon: _isLoading
                                  ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                                  : const Icon(Icons.refresh, color: Colors.white, size: 24),
                              onPressed: _isLoading ? null : _loadUserData,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                    // Profile image
                    GestureDetector(
                      onTap: _isEditing ? _showImagePickerDialog : null,
                      behavior: HitTestBehavior.translucent,
                      child: Stack(
                        children: [
                          Container(
                            width: 160,
                            height: 160,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                              border: Border.all(color: Colors.white, width: 5),
                              image: _profileImageUrl != null
                                  ? DecorationImage(
                                image: _profileImageUrl!.startsWith('data:')
                                    ? MemoryImage(base64Decode(_profileImageUrl!.split(',')[1]))
                                    : _profileImageUrl!.startsWith('http')
                                    ? NetworkImage(_profileImageUrl!)
                                    : FileImage(File(_profileImageUrl!)) as ImageProvider,
                                fit: BoxFit.cover,
                              )
                                  : null,
                            ),
                            child: _profileImageUrl == null
                                ? const Icon(Icons.person, size: 100, color: Color(0xFF2561FA))
                                : null,
                          ),
                          if (_isEditing)
                            Positioned(
                              right: 10,
                              bottom: 10,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: _isUploadingImage
                                    ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2561FA)),
                                  ),
                                )
                                    : Icon(
                                  Icons.camera_alt,
                                  color: Colors.grey[800],
                                  size: 24,
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

            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 24),
              child: Column(
                children: [
                  _buildProfileField(
                    label: 'User Name',
                    controller: _usernameController,
                    enabled: _isEditing,
                    icon: Icons.person_outline,
                    fieldKey: 'username',
                  ),
                  const SizedBox(height: 24),

                  _buildProfileField(
                    label: 'Email',
                    controller: _emailController,
                    enabled: false, // Email cannot be modified
                    icon: Icons.email_outlined,
                    fieldKey: 'email',
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 24),

                  if (_isEditing)
                    _buildProfileField(
                      label: 'Password',
                      controller: _passwordController,
                      enabled: true,
                      isPassword: true,
                      icon: Icons.lock_outline,
                      fieldKey: 'password',
                      hintText: 'Leave blank to keep current password',
                    ),

                  if (_isEditing)
                    const SizedBox(height: 24),

                  _buildProfileField(
                    label: 'Phone Number',
                    controller: _phoneController,
                    enabled: _isEditing,
                    icon: Icons.phone_outlined,
                    fieldKey: 'phone',
                    keyboardType: TextInputType.phone,
                    hintText: '0121234567',
                  ),
                  const SizedBox(height: 24),

                  _buildProfileField(
                    label: 'Family / Caregiver Contact',
                    controller: _emergencyContactController,
                    enabled: _isEditing,
                    icon: Icons.contact_phone_outlined,
                    fieldKey: 'emergency',
                    keyboardType: TextInputType.phone,
                    hintText: '0121234567',
                  ),
                  const SizedBox(height: 32),

                  // Caregiver Management Section (only for blind users)
                  if (_userType == 'blind_user') ...[
                    _buildCaregiverSection(),
                    const SizedBox(height: 32),
                  ],

                  // Edit/Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                      onPressed: _isLoading
                          ? null
                          : () async {
                        if (_isEditing) {
                          await _handleButtonClick('save_profile', () {
                            _saveProfile();
                          });
                        } else {
                          await _handleButtonClick('edit_profile', () {
                            setState(() {
                              _isEditing = true;
                            });
                          });
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2561FA),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 5,
                        shadowColor: const Color(0xFF2561FA).withOpacity(0.5),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                          : Text(
                        _isEditing ? 'Save Changes' : 'Edit Profile',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Log Out Button
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : () async {
                        await _handleButtonClick('logout', _logout);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 5,
                        shadowColor: Colors.red.withOpacity(0.5),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text(
                        'Log Out',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.0,
                        ),
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
  Widget _buildCaregiverSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.favorite, color: Colors.blue.shade700, size: 24),
              const SizedBox(width: 8),
              Text(
                'Caregiver Connection',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _viewConnectionRequests,
              icon: Icon(Icons.people, color: Colors.blue.shade700, size: 20),
              label: const Text('View Requests'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.blue.shade700,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (_caregiverEmail != null) ...[
            // Current caregiver display
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Connected Caregiver',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _caregiverEmail!,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : () async {
                        await _handleButtonClick('remove_caregiver', _removeCaregiver);
                      },
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                      label: const Text(
                        'Remove Caregiver',
                        style: TextStyle(color: Colors.red),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            // Add caregiver form
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.orange.shade700, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'No Caregiver Connected',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Connect with a caregiver for enhanced safety monitoring and emergency support.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Email input field
                  TextField(
                    controller: _caregiverEmailController,
                    focusNode: _focusNodes['caregiver'],
                    decoration: InputDecoration(
                      labelText: 'Caregiver Email Address',
                      hintText: 'Enter the email of your caregiver',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF2561FA), width: 2),
                      ),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    onTap: () {
                      _provideHapticFeedback('light');
                    },
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : () async {
                        await _handleButtonClick('add_caregiver', _addCaregiver);
                      },
                      icon: _isLoading
                          ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                          : const Icon(Icons.person_add, color: Colors.white),
                      label: Text(
                        _isLoading ? 'Connecting...' : 'Add Caregiver',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2561FA),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.grey, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your caregiver must have a registered account in this app to connect.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileField({
    required String label,
    required TextEditingController controller,
    required bool enabled,
    required IconData icon,
    required String fieldKey, // New parameter for accessibility
    bool isPassword = false,
    String? hintText,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF2C3E50),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: enabled ? const Color(0xFF2561FA).withOpacity(0.3) : Colors.transparent,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            enabled: enabled,
            obscureText: isPassword,
            keyboardType: keyboardType,
            focusNode: _focusNodes[fieldKey],
            style: TextStyle(
              fontSize: 16,
              color: enabled ? Colors.black87 : Colors.black54,
            ),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 16,
              ),
              prefixIcon: Icon(
                icon,
                color: enabled ? const Color(0xFF2561FA) : Colors.grey,
                size: 22,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            // Accessibility features
            onTap: () {
              if (enabled) {
                _provideHapticFeedback('light');
              }
            },
          ),
        ),
      ],
    );
  }
} 