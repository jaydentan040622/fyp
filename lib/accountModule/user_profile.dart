import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'caregiver_services.dart';
import 'auth_gate.dart';

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

  @override
  void initState() {
    super.initState();
    _loadUserData();
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
          _profileImageUrl = data?['profileImage']?.toString();
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

  Future<void> _saveProfile() async {
    // Validate inputs
    if (_usernameController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty) {
      _showSnackBar('Username and email are required', isError: true);
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
      
      // Prepare update data
      final updateData = <String, dynamic>{
        'username': _usernameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'emergencyContact': _emergencyContactController.text.trim(),
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
      
      // Update email in FirebaseAuth if changed
      if (_emailController.text.trim() != user.email) {
        try {
          await user.updateEmail(_emailController.text.trim());
          print('FirebaseAuth email updated');
        } catch (authError) {
          print('Error updating FirebaseAuth email: $authError');
          // Continue even if auth email update fails
        }
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

  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
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

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _emergencyContactController.dispose();
    _caregiverEmailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
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
                          Stack(
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
                                        image: NetworkImage(_profileImageUrl!),
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
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.camera_alt,
                                      color: Colors.grey[800],
                                      size: 24,
                                    ),
                                  ),
                                ),
                            ],
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
                        ),
                        const SizedBox(height: 24),
                        
                        _buildProfileField(
                          label: 'Email',
                          controller: _emailController,
                          enabled: _isEditing,
                          icon: Icons.email_outlined,
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
                            hintText: 'Enter new password (leave blank to keep current)',
                          ),
                          
                        if (_isEditing)
                          const SizedBox(height: 24),
                          
                        _buildProfileField(
                          label: 'Phone Number',
                          controller: _phoneController,
                          enabled: _isEditing,
                          icon: Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 24),
                        
                        _buildProfileField(
                          label: 'Family / Caregiver Contact',
                          controller: _emergencyContactController,
                          enabled: _isEditing,
                          icon: Icons.contact_phone_outlined,
                          keyboardType: TextInputType.phone,
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
                                : () {
                                    if (_isEditing) {
                                      _saveProfile();
                                    } else {
                                      setState(() {
                                        _isEditing = true;
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
                            onPressed: _isLoading ? null : _logout,
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
                      onPressed: _isLoading ? null : _removeCaregiver,
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
                  ),
                  const SizedBox(height: 16),
                  
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _addCaregiver,
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
            style: TextStyle(
              fontSize: 16,
              color: enabled ? Colors.black87 : Colors.black54,
            ),
            decoration: InputDecoration(
              hintText: hintText,
              prefixIcon: Icon(
                icon,
                color: enabled ? const Color(0xFF2561FA) : Colors.grey,
                size: 22,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
          ),
        ),
      ],
    );
  }
} 