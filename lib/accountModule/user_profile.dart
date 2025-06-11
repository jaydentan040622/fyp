import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() { _isLoading = true; });
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        // Fetch data from "userprofile" collection
        final doc = await FirebaseFirestore.instance.collection('userprofile').doc(user.uid).get();
        if (doc.exists && mounted) {
          setState(() {
            _usernameController.text = doc['username'] ?? '';
            _emailController.text = doc['email'] ?? '';
            _passwordController.text = doc['password'] ?? '';
            _phoneController.text = doc['phone'] ?? '';
            _emergencyContactController.text = doc['emergencyContact'] ?? '';
            _profileImageUrl = doc['profileImage'];
          });
        }
      } catch (e) {
        if (mounted) {
          _showSnackBar('Error loading profile data', isError: true);
        }
      }
    }
    if (mounted) {
      setState(() { _isLoading = false; });
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
    if (user == null) return;
    
    try {
      // Update data in "userprofile" collection
      final updateData = {
        'username': _usernameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'emergencyContact': _emergencyContactController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      
      // Only update password if a new one is provided
      if (_passwordController.text.trim().isNotEmpty) {
        updateData['password'] = _passwordController.text.trim();
      }
      
      await FirebaseFirestore.instance.collection('userprofile').doc(user.uid).update(updateData);
      
      // Update email in FirebaseAuth if changed
      if (_emailController.text.trim() != user.email) {
        await user.updateEmail(_emailController.text.trim());
      }
      
      // Update password if not empty
      if (_passwordController.text.trim().isNotEmpty) {
        await user.updatePassword(_passwordController.text.trim());
      }
      
      setState(() { 
        _isEditing = false; 
        _passwordController.text = ''; // Clear password field after update
      });
      
      _showSnackBar('Profile updated successfully!');
      
    } catch (e) {
      _showSnackBar('Error updating profile: ${e.toString()}', isError: true);
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
                                const SizedBox(width: 48), // For balance
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
                        const SizedBox(height: 40),
                        
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
                      ],
                    ),
                  ),
                ],
              ),
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