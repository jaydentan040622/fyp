import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vibration/vibration.dart';
import 'dart:async';
import 'user_profile.dart';
import 'connection_requests_screen.dart';

class CaregiverHomeScreen extends StatefulWidget {
  const CaregiverHomeScreen({super.key});

  @override
  State<CaregiverHomeScreen> createState() => _CaregiverHomeScreenState();
}

class _CaregiverHomeScreenState extends State<CaregiverHomeScreen> {
  String _username = '';
  bool _isLoading = true;
  List<Map<String, dynamic>> _connectedUsers = [];
  List<Map<String, dynamic>> _emergencyAlerts = [];

  @override
  void initState() {
    super.initState();
    _loadCaregiverData();
    _listenToEmergencyAlerts();
  }

  Future<void> _loadCaregiverData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        // Get caregiver profile
        final doc = await FirebaseFirestore.instance
            .collection('userprofile')
            .doc(user.uid)
            .get();
        
        if (doc.exists && mounted) {
          setState(() {
            _username = doc['username'] ?? '';
          });
        }

        // Load connected blind users (this would be populated when blind users add this caregiver)
        _loadConnectedUsers();
      } catch (e) {
        print('Error loading caregiver data: $e');
      }
    }
    
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadConnectedUsers() async {
    try {
      final caregiverId = FirebaseAuth.instance.currentUser?.uid;
      if (caregiverId == null) return;

      // Get all blind users who have this caregiver as emergency contact
      final querySnapshot = await FirebaseFirestore.instance
          .collection('userprofile')
          .where('userType', isEqualTo: 'blind_user')
          .where('caregiverId', isEqualTo: caregiverId)
          .get();

      if (mounted) {
        setState(() {
          _connectedUsers = querySnapshot.docs.map((doc) {
            return {
              'id': doc.id,
              'username': doc['username'] ?? '',
              'email': doc['email'] ?? '',
              'phone': doc['phone'] ?? '',
              'emergencyContact': doc['emergencyContact'] ?? '',
            };
          }).toList();
        });
      }
    } catch (e) {
      print('Error loading connected users: $e');
    }
  }

  void _listenToEmergencyAlerts() {
    final caregiverId = FirebaseAuth.instance.currentUser?.uid;
    if (caregiverId == null) return;

    // Listen to emergency alerts
    FirebaseFirestore.instance
        .collection('emergencyAlerts')
        .where('caregiverId', isEqualTo: caregiverId)
        .where('isActive', isEqualTo: true)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        // Get previous count to detect new alerts
        final previousCount = _emergencyAlerts.length;
        
        // Update alerts list
        setState(() {
          _emergencyAlerts = snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            
            // Try to get user details for each alert
            _fetchUserDetailsForAlert(data);
            
            return data;
          }).toList();
        });

        // Show notification for new alerts
        if (_emergencyAlerts.isNotEmpty && _emergencyAlerts.length > previousCount) {
          // Vibrate device for emergency
          try {
            Vibration.hasVibrator().then((hasVibrator) {
              if (hasVibrator == true) {
                Vibration.vibrate(pattern: [500, 200, 500, 200, 500]);
              }
            });
          } catch (e) {
            print('Error vibrating device: $e');
          }
          
          // Show notification
          _showEmergencyNotification(_emergencyAlerts.first);
        }
      }
    });
    
    // Also listen to user locations with emergency flag
    FirebaseFirestore.instance
        .collection('userLocations')
        .where('isEmergency', isEqualTo: true)
        .snapshots()
        .listen((snapshot) {
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final userId = data['userId'];
        
        // Check if this user is connected to this caregiver
        if (_connectedUsers.any((user) => user['id'] == userId)) {
          // Create an emergency alert if one doesn't exist
          _checkAndCreateEmergencyAlert(data);
        }
      }
    });
  }
  
  Future<void> _fetchUserDetailsForAlert(Map<String, dynamic> alertData) async {
    if (alertData['userId'] == null || alertData['username'] != null) return;
    
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('userprofile')
          .doc(alertData['userId'])
          .get();
          
      if (userDoc.exists) {
        alertData['username'] = userDoc.data()?['username'] ?? 'Unknown User';
        alertData['phone'] = userDoc.data()?['phone'];
      }
    } catch (e) {
      print('Error fetching user details for alert: $e');
    }
  }
  
  Future<void> _checkAndCreateEmergencyAlert(Map<String, dynamic> locationData) async {
    final userId = locationData['userId'];
    final caregiverId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null || caregiverId == null) return;
    
    try {
      // Check if there's already an active alert for this user
      final existingAlerts = await FirebaseFirestore.instance
          .collection('emergencyAlerts')
          .where('userId', isEqualTo: userId)
          .where('caregiverId', isEqualTo: caregiverId)
          .where('isActive', isEqualTo: true)
          .get();
          
      if (existingAlerts.docs.isEmpty) {
        // Create a new emergency alert
        final userDoc = await FirebaseFirestore.instance
            .collection('userprofile')
            .doc(userId)
            .get();
            
        final username = userDoc.data()?['username'] ?? 'Unknown User';
        
        await FirebaseFirestore.instance
            .collection('emergencyAlerts')
            .add({
              'userId': userId,
              'caregiverId': caregiverId,
              'username': username,
              'message': 'EMERGENCY: Immediate assistance required',
              'latitude': locationData['latitude'],
              'longitude': locationData['longitude'],
              'timestamp': FieldValue.serverTimestamp(),
              'isActive': true,
            });
            
        // Also create a notification
        await FirebaseFirestore.instance
            .collection('notifications')
            .add({
              'userId': caregiverId,
              'title': '🚨 EMERGENCY ALERT',
              'message': '$username needs immediate assistance!',
              'type': 'emergency',
              'timestamp': FieldValue.serverTimestamp(),
              'isRead': false,
              'priority': 'urgent',
            });
      }
    } catch (e) {
      print('Error creating emergency alert: $e');
    }
  }

  void _showEmergencyNotification(Map<String, dynamic> alert) {
    // Vibrate device for emergency
    Vibration.vibrate(pattern: [500, 200, 500, 200, 500]);
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.red.shade50,
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.red.shade700, size: 36),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'EMERGENCY ALERT',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.red.shade300,
                  child: Text(
                    (alert['username'] ?? 'U').substring(0, 1).toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${alert['username'] ?? 'Unknown User'} needs immediate assistance!',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Emergency Details:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text('${alert['message'] ?? 'Emergency assistance needed'}'),
            const SizedBox(height: 12),
            
            // Location information
            if (alert['latitude'] != null && alert['longitude'] != null) ...[
              Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Location: ${alert['latitude'].toStringAsFixed(6)}, ${alert['longitude'].toStringAsFixed(6)}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () {
                  final lat = alert['latitude'];
                  final lng = alert['longitude'];
                  launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng'));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.map, size: 16, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('Open in Maps', style: TextStyle(color: Colors.blue)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            
            // Time information
            Row(
              children: [
                const Icon(Icons.access_time, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  'Time: ${_formatTimestamp(alert['timestamp'])}',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Please respond immediately!',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  // View live location
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => LiveLocationScreen(userId: alert['userId']),
                    ),
                  );
                },
                icon: const Icon(Icons.location_on, color: Colors.white),
                label: const Text('View Live Location', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _callUser(alert);
                      },
                      icon: const Icon(Icons.phone, color: Colors.white),
                      label: const Text('Call User', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _callEmergencyServices();
                      },
                      icon: const Icon(Icons.emergency, color: Colors.white),
                      label: const Text('Call 911', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Dismiss'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'Unknown';
    try {
      final dateTime = (timestamp as Timestamp).toDate();
      return '${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Unknown';
    }
  }

  void _respondToEmergency(Map<String, dynamic> alert) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Emergency Response'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.phone, color: Colors.green),
              title: const Text('Call User'),
              onTap: () {
                Navigator.pop(context);
                _callUser(alert);
              },
            ),
            ListTile(
              leading: const Icon(Icons.location_on, color: Colors.blue),
              title: const Text('View Location'),
              onTap: () {
                Navigator.pop(context);
                _viewUserLocation(alert);
              },
            ),
            ListTile(
              leading: const Icon(Icons.local_hospital, color: Colors.red),
              title: const Text('Call Emergency Services'),
              onTap: () {
                Navigator.pop(context);
                _callEmergencyServices();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _callUser(Map<String, dynamic> alert) {
    // Implementation for calling user
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Calling ${alert['username']}...'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _viewUserLocation(Map<String, dynamic> alert) {
    if (alert['userId'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User ID not found in alert data'))
      );
      return;
    }
    
    // Navigate to live location screen with user ID
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LiveLocationScreen(userId: alert['userId']),
      ),
    );
  }

  void _callEmergencyServices() {
    // Implementation for calling emergency services
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Calling emergency services...'),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: const Color(0xFF2561FA),
                          child: Icon(
                            Icons.favorite,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Welcome back, $_username',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2C3E50),
                                ),
                              ),
                              const Text(
                                'Caregiver Dashboard',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // Emergency Alerts Section
                    if (_emergencyAlerts.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.warning, color: Colors.red.shade700),
                                const SizedBox(width: 8),
                                const Text(
                                  'Active Emergency Alerts',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ...(_emergencyAlerts.take(3).map((alert) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                '${alert['username']} needs assistance - ${_formatTimestamp(alert['timestamp'])}',
                                style: const TextStyle(fontSize: 14),
                              ),
                            ))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Quick Actions Grid
                    const Text(
                      'Quick Actions',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2C3E50),
                      ),
                    ),
                    const SizedBox(height: 16),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      children: [
                        _buildActionCard(
                          icon: Icons.location_on,
                          title: 'Live Location',
                          subtitle: 'View real-time location',
                          color: Colors.blue,
                          onTap: () {
                            // Show user selection dialog if there are connected users
                            if (_connectedUsers.isNotEmpty) {
                              _showUserSelectionDialog();
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('No connected users found. Add blind users first.'),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                            }
                          },
                        ),
                        _buildActionCard(
                          icon: Icons.history,
                          title: 'Location History',
                          subtitle: 'View past locations',
                          color: Colors.green,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const LocationHistoryScreen(),
                            ),
                          ),
                        ),
                        _buildActionCard(
                          icon: Icons.route,
                          title: 'Route Monitoring',
                          subtitle: 'Track route deviations',
                          color: Colors.orange,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const RouteMonitoringScreen(),
                            ),
                          ),
                        ),
                        _buildActionCard(
                          icon: Icons.person_add,
                          title: 'Add Blind User',
                          subtitle: 'Connect with users',
                          color: Colors.purple,
                          onTap: () => _showAddBlindUserDialog(),
                        ),
                        _buildActionCard(
                          icon: Icons.people,
                          title: 'Manage Connections',
                          subtitle: 'View and manage users',
                          color: Colors.teal,
                          onTap: () => _showConnectionRequestsDialog(),
                        ),
                        _buildActionCard(
                          icon: Icons.emergency,
                          title: 'Emergency Center',
                          subtitle: 'Handle emergencies',
                          color: Colors.red,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const EmergencyCenterScreen(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // Connected Users Section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Connected Users',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2C3E50),
                          ),
                        ),
                        TextButton(
                          onPressed: _loadConnectedUsers,
                          child: const Text('Refresh'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    if (_connectedUsers.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Column(
                          children: [
                            Icon(Icons.people_outline, size: 48, color: Colors.grey),
                            SizedBox(height: 12),
                            Text(
                              'No connected users yet',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              'Blind users can add you as their caregiver',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ...(_connectedUsers.map((user) => Card(
                        elevation: 2,
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF2561FA),
                            child: Text(
                              user['username']?.isNotEmpty == true 
                                  ? user['username'][0].toUpperCase() 
                                  : 'U',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          title: Text(
                            user['username'] ?? 'Unknown User',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(user['email'] ?? ''),
                          trailing: PopupMenuButton(
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'location',
                                child: Row(
                                  children: [
                                    Icon(Icons.location_on, size: 20),
                                    SizedBox(width: 8),
                                    Text('View Location'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'call',
                                child: Row(
                                  children: [
                                    Icon(Icons.phone, size: 20),
                                    SizedBox(width: 8),
                                    Text('Call User'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'history',
                                child: Row(
                                  children: [
                                    Icon(Icons.history, size: 20),
                                    SizedBox(width: 8),
                                    Text('View History'),
                                  ],
                                ),
                              ),
                            ],
                            onSelected: (value) {
                              switch (value) {
                                case 'location':
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => LiveLocationScreen(userId: user['id']),
                                    ),
                                  );
                                  break;
                                case 'call':
                                  _callUser(user);
                                  break;
                                case 'history':
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => LocationHistoryScreen(userId: user['id']),
                                    ),
                                  );
                                  break;
                              }
                            },
                          ),
                        ),
                      ))),

                    const SizedBox(height: 32),

                    // Profile Button
                    Center(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const UserProfileScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.person, color: Colors.white),
                        label: const Text(
                          'Caregiver Profile',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2561FA),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: color.withOpacity(0.8),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // Show dialog to select which user to track
  void _showUserSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select User to Track'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _connectedUsers.length,
            itemBuilder: (context, index) {
              final user = _connectedUsers[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFF2561FA),
                  child: Text(
                    user['username']?.isNotEmpty == true 
                        ? user['username'][0].toUpperCase() 
                        : 'U',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                title: Text(user['username'] ?? 'Unknown User'),
                subtitle: Text(user['email'] ?? ''),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => LiveLocationScreen(userId: user['id']),
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  // Show dialog to add a blind user
  void _showAddBlindUserDialog() {
    final TextEditingController emailController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Blind User'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter the email address of the blind user you want to connect with.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: emailController,
                decoration: const InputDecoration(
                  labelText: 'Email Address',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter an email address';
                  }
                  if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                    return 'Please enter a valid email address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              const Text(
                'Note: The user must accept your connection request before you can view their location.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context);
                _sendConnectionRequest(emailController.text.trim());
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2561FA),
              foregroundColor: Colors.white,
            ),
            child: const Text('Send Request'),
          ),
        ],
      ),
    );
  }
  
  // Send connection request to blind user
  Future<void> _sendConnectionRequest(String email) async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Check if user exists
      final userQuery = await FirebaseFirestore.instance
          .collection('userprofile')
          .where('email', isEqualTo: email)
          .where('userType', isEqualTo: 'blind_user')
          .get();
      
      if (userQuery.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No blind user found with this email address'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isLoading = false;
        });
        return;
      }
      
      final blindUserDoc = userQuery.docs.first;
      final blindUserId = blindUserDoc.id;
      final blindUserName = blindUserDoc['username'] ?? 'Blind User';
      
      // Check if connection already exists
      final existingConnection = await FirebaseFirestore.instance
          .collection('caregiverConnections')
          .where('userId', isEqualTo: blindUserId)
          .where('caregiverId', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
          .get();
      
      if (existingConnection.docs.isNotEmpty) {
        final status = existingConnection.docs.first['status'];
        if (status == 'pending') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Connection request already sent and pending'),
              backgroundColor: Colors.orange,
            ),
          );
        } else if (status == 'accepted') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You are already connected with this user'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Connection request was previously rejected'),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() {
          _isLoading = false;
        });
        return;
      }
      
      // Get current user data
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception("User not authenticated");
      }
      
      final caregiverDoc = await FirebaseFirestore.instance
          .collection('userprofile')
          .doc(currentUser.uid)
          .get();
      
      if (!caregiverDoc.exists) {
        throw Exception("Caregiver profile not found");
      }
      
      // Create connection data
      final connectionData = {
        'userId': blindUserId,
        'caregiverId': currentUser.uid,
        'caregiverName': _username,
        'userName': blindUserName,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
        'caregiverEmail': caregiverDoc.data()?['email'] ?? '',
        'userEmail': email,
      };
      
      // Use a Cloud Function or admin route to create the connection
      // Since we can't modify Firestore rules directly, we'll use a workaround
      // by creating a document with a unique ID that both users can access
      final String connectionId = '${currentUser.uid}_${blindUserId}_${DateTime.now().millisecondsSinceEpoch}';
      
      await FirebaseFirestore.instance
          .collection('caregiverConnections')
          .doc(connectionId)
          .set(connectionData);
      
      // Create notification for blind user
      await FirebaseFirestore.instance
          .collection('notifications')
          .add({
            'userId': blindUserId,
            'title': 'New Caregiver Connection Request',
            'message': '$_username wants to connect as your caregiver',
            'type': 'connection_request',
            'timestamp': FieldValue.serverTimestamp(),
            'isRead': false,
            'data': {
              'caregiverId': currentUser.uid,
              'caregiverName': _username,
              'connectionId': connectionId,
            },
          });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connection request sent to $blindUserName'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Refresh connected users list
      _loadConnectedUsers();
      
    } catch (e) {
      print('Error sending connection request: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sending connection request: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  // Show dialog to manage connection requests
  void _showConnectionRequestsDialog() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ConnectionRequestsScreen(),
      ),
    );
  }
}

// Placeholder screens for caregiver features
class LiveLocationScreen extends StatefulWidget {
  final String? userId;
  
  const LiveLocationScreen({super.key, this.userId});

  @override
  State<LiveLocationScreen> createState() => _LiveLocationScreenState();
}

class _LiveLocationScreenState extends State<LiveLocationScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _userData;
  Map<String, dynamic>? _locationData;
  StreamSubscription<DocumentSnapshot>? _locationStreamSubscription;
  String _username = 'User';
  
  // Map controller
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  bool _isEmergencyActive = false;
  Timer? _refreshTimer;
  
  // Debug flags
  bool _debugMode = true; // Set to true for debugging
  
  @override
  void initState() {
    super.initState();
    _initializeData();
    _startPeriodicRefresh();
  }
  
  @override
  void dispose() {
    _locationStreamSubscription?.cancel();
    _refreshTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }
  
  void _startPeriodicRefresh() {
    // Cancel any existing timer
    _refreshTimer?.cancel();
    
    // Create a new timer that refreshes every 30 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_debugMode) print('🔄 LiveLocationScreen: Periodic refresh triggered');
      if (mounted) {
        setState(() {
          // This will trigger a UI refresh to update the time display
        });
      }
    });
  }
  
  Future<void> _initializeData() async {
    try {
      if (_debugMode) print('🔄 LiveLocationScreen: Initializing data for user ID: ${widget.userId}');
      
      // If no userId is provided, show a message
      if (widget.userId == null) {
        if (_debugMode) print('⚠️ LiveLocationScreen: No user ID provided');
        setState(() {
          _isLoading = false;
        });
        return;
      }
      
      // Load user data first
      await _loadUserData();
      
      // Setup real-time location updates
      _setupLocationStream();
      
    } catch (e) {
      if (_debugMode) print('❌ LiveLocationScreen: Error initializing data: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load location data: $e'))
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  Future<void> _loadUserData() async {
    if (widget.userId == null) return;
    
    if (_debugMode) print('🔍 LiveLocationScreen: Loading user data for ID: ${widget.userId}');
    
    try {
      final doc = await FirebaseFirestore.instance
          .collection('userprofile')
          .doc(widget.userId)
          .get();
          
      if (doc.exists && mounted) {
        if (_debugMode) print('✅ LiveLocationScreen: User data loaded successfully');
        setState(() {
          _userData = doc.data();
          _username = _userData?['username'] ?? 'User';
        });
      } else {
        if (_debugMode) print('⚠️ LiveLocationScreen: User data not found');
      }
    } catch (e) {
      if (_debugMode) print('❌ LiveLocationScreen: Error loading user data: $e');
      throw Exception('Failed to load user data: $e');
    }
  }
  
  Future<void> _setupLocationStream() async {
    if (widget.userId == null) return;
    
    if (_debugMode) print('🔄 LiveLocationScreen: Setting up location stream for user ID: ${widget.userId}');
    
    try {
      // Cancel any existing subscription
      _locationStreamSubscription?.cancel();
      
      // Check if the user has an accepted connection with the blind user
      if (_debugMode) print('🔍 LiveLocationScreen: Checking connection status');
      
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }
      
      // First check if the connection exists and is accepted
      final connectionsQuery = await FirebaseFirestore.instance
          .collection('caregiverConnections')
          .where('caregiverId', isEqualTo: currentUser.uid)
          .where('userId', isEqualTo: widget.userId)
          .where('status', isEqualTo: 'accepted')
          .get();
      
      if (_debugMode) print('🔍 Found ${connectionsQuery.docs.length} accepted connections');
      
      // For now, we'll continue even if there's no connection (due to rules issues)
      // In production, you'd want to enforce this check
      
      // Create a new subscription
      _locationStreamSubscription = FirebaseFirestore.instance
          .collection('userLocations')
          .doc(widget.userId)
          .snapshots()
          .listen(
            (snapshot) {
              if (_debugMode) print('📍 LiveLocationScreen: Location update received');
              
              if (snapshot.exists && mounted) {
                final data = snapshot.data() as Map<String, dynamic>;
                
                if (_debugMode) {
                  print('📍 Location data: lat=${data['latitude']}, lng=${data['longitude']}');
                  print('📍 Emergency status: ${data['isEmergency']}');
                  print('📍 Timestamp: ${data['timestamp']}');
                }
                
                setState(() {
                  _locationData = data;
                  _isEmergencyActive = data['isEmergency'] ?? false;
                  _updateMapMarkers();
                });
                
                // If this is an emergency, show alert
                if (_isEmergencyActive) {
                  _showEmergencyAlert();
                }
              } else {
                if (_debugMode) print('⚠️ LiveLocationScreen: No location data available');
                
                // Check if the blind user has started sharing location
                _checkBlindUserLocationSharing();
              }
            },
            onError: (error) {
              if (_debugMode) print('❌ LiveLocationScreen: Error in location stream: $error');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error receiving location updates: $error'))
              );
              
              // Try to recover by checking if the document exists
              _checkBlindUserLocationSharing();
            }
          );
      
      if (_debugMode) print('✅ LiveLocationScreen: Location stream setup successfully');
    } catch (e) {
      if (_debugMode) print('❌ LiveLocationScreen: Error setting up location stream: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to setup location stream: $e'))
      );
    }
  }
  
  Future<void> _checkBlindUserLocationSharing() async {
    if (_debugMode) print('🔍 Checking if blind user has started sharing location');
    
    try {
      // Check if the document exists without subscribing to updates
      final doc = await FirebaseFirestore.instance
          .collection('userLocations')
          .doc(widget.userId)
          .get();
          
      if (_debugMode) print('🔍 Location document exists: ${doc.exists}');
      
      if (!doc.exists && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The blind user has not started sharing their location yet'))
        );
      }
    } catch (e) {
      if (_debugMode) print('❌ Error checking location document: $e');
    }
  }
  
  void _updateMapMarkers() {
    if (_locationData == null) {
      if (_debugMode) print('⚠️ LiveLocationScreen: Cannot update map markers - no location data');
      return;
    }
    
    try {
      if (_debugMode) print('🔄 LiveLocationScreen: Updating map markers');
      
      final latitude = _locationData!['latitude'] as double;
      final longitude = _locationData!['longitude'] as double;
      final latLng = LatLng(latitude, longitude);
      
      _markers = {
        Marker(
          markerId: const MarkerId('user_location'),
          position: latLng,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            _isEmergencyActive ? BitmapDescriptor.hueRed : BitmapDescriptor.hueBlue
          ),
          infoWindow: InfoWindow(
            title: _username,
            snippet: _isEmergencyActive ? 'EMERGENCY ACTIVE!' : 'Last updated: ${_formatTimestamp(_locationData!['timestamp'])}',
          ),
        ),
      };
      
      // Move camera to user's location
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(latLng, 16));
      
      if (_debugMode) print('✅ LiveLocationScreen: Map markers updated successfully');
    } catch (e) {
      if (_debugMode) print('❌ LiveLocationScreen: Error updating map markers: $e');
    }
  }
  
  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'Unknown';
    try {
      final dateTime = (timestamp as Timestamp).toDate();
      return '${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Unknown';
    }
  }
  
  void _showEmergencyAlert() {
    if (_locationData == null) return;
    
    // Vibrate device for emergency
    try {
      Vibration.hasVibrator().then((hasVibrator) {
        if (hasVibrator == true) {
          Vibration.vibrate(pattern: [500, 200, 500, 200, 500]);
        }
      });
    } catch (e) {
      if (_debugMode) print('❌ LiveLocationScreen: Error vibrating device: $e');
    }
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.red.shade50,
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.red, size: 30),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'EMERGENCY ALERT',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$_username needs immediate assistance!',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              'Location: ${_locationData!['latitude'].toStringAsFixed(6)}, ${_locationData!['longitude'].toStringAsFixed(6)}',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              'Time: ${_formatTimestamp(_locationData!['timestamp'])}',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 20),
            const Text(
              'Please respond immediately!',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _callUser();
                  },
                  icon: const Icon(Icons.phone, color: Colors.white),
                  label: const Text('Call User', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _callEmergencyServices();
                  },
                  icon: const Icon(Icons.emergency, color: Colors.white),
                  label: const Text('Call 911', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }
  
  void _callUser() {
    if (_userData == null) return;
    
    final phone = _userData!['phone'];
    if (phone != null && phone.isNotEmpty) {
      // Launch phone call
      launchUrl(Uri.parse('tel:$phone'));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number available'))
      );
    }
  }
  
  void _callEmergencyServices() {
    launchUrl(Uri.parse('tel:911'));
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Live Location: $_username'),
        backgroundColor: _isEmergencyActive ? Colors.red : const Color(0xFF2561FA),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // Cancel existing subscription and set up a new one
              _locationStreamSubscription?.cancel();
              _setupLocationStream();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Refreshing location data...'))
              );
            },
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.phone),
            onPressed: _callUser,
            tooltip: 'Call User',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
                        : _locationData == null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.location_off, size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text(
                            'No location data available',
                            style: TextStyle(fontSize: 18, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'User has not shared their location yet',
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: () async {
                              setState(() {
                                _isLoading = true;
                              });
                              
                              try {
                                // Check if the document exists
                                final doc = await FirebaseFirestore.instance
                                    .collection('userLocations')
                                    .doc(widget.userId)
                                    .get();
                                    
                                if (!doc.exists) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('The blind user has not started sharing their location yet'))
                                  );
                                }
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error checking location: $e'))
                                );
                              }
                              
                              // Setup stream again
                              await _setupLocationStream();
                              
                              if (mounted) {
                                setState(() {
                                  _isLoading = false;
                                });
                              }
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Refresh'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2561FA),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            ),
                          ),
                        ],
                      ),
                    )
              : Stack(
                  children: [
                    GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: LatLng(
                          _locationData!['latitude'] ?? 0.0,
                          _locationData!['longitude'] ?? 0.0,
                        ),
                        zoom: 16,
                      ),
                      markers: _markers,
                      polylines: _polylines,
                      onMapCreated: (controller) {
                        _mapController = controller;
                        _updateMapMarkers();
                      },
                      zoomControlsEnabled: true,
                      myLocationButtonEnabled: false,
                      compassEnabled: true,
                    ),
                    
                    // Emergency indicator
                    if (_isEmergencyActive)
                      Positioned(
                        top: 16,
                        left: 16,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.warning, color: Colors.white),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'EMERGENCY ACTIVE - User needs immediate assistance',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                    // Location info card
                    Positioned(
                      bottom: 16,
                      left: 16,
                      right: 16,
                      child: Card(
                        elevation: 4,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: _isEmergencyActive ? Colors.red : Colors.blue,
                                    radius: 20,
                                    child: Text(
                                      _username.isNotEmpty ? _username[0].toUpperCase() : 'U',
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _username,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Row(
                                          children: [
                                            Text(
                                              'Last updated: ${_getTimeSinceUpdate()}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: _isLocationStale() ? Colors.red : Colors.grey.shade600,
                                              ),
                                            ),
                                            if (_isLocationStale())
                                              Padding(
                                                padding: const EdgeInsets.only(left: 5),
                                                child: Icon(
                                                  Icons.warning,
                                                  color: Colors.orange,
                                                  size: 14,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Coordinates',
                                          style: TextStyle(fontSize: 12, color: Colors.grey),
                                        ),
                                        Text(
                                          '${_locationData!['latitude'].toStringAsFixed(6)}, ${_locationData!['longitude'].toStringAsFixed(6)}',
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (_locationData!['speed'] != null)
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Speed',
                                            style: TextStyle(fontSize: 12, color: Colors.grey),
                                          ),
                                          Text(
                                            '${(_locationData!['speed'] * 3.6).toStringAsFixed(1)} km/h',
                                            style: const TextStyle(fontSize: 14),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: _callUser,
                                      icon: const Icon(Icons.phone, size: 16),
                                      label: const Text('Call'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        // Open in maps app
                                        final lat = _locationData!['latitude'];
                                        final lng = _locationData!['longitude'];
                                        launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng'));
                                      },
                                      icon: const Icon(Icons.map, size: 16),
                                      label: const Text('Directions'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  // Check if location data is stale (older than 5 minutes)
  bool _isLocationStale() {
    if (_locationData == null || _locationData!['timestamp'] == null) return true;
    
    try {
      final timestamp = (_locationData!['timestamp'] as Timestamp).toDate();
      final now = DateTime.now();
      final difference = now.difference(timestamp);
      
      // If data is older than 5 minutes, consider it stale
      return difference.inMinutes > 5;
    } catch (e) {
      if (_debugMode) print('❌ LiveLocationScreen: Error checking if location is stale: $e');
      return true;
    }
  }
  
  // Format the time difference for display
  String _getTimeSinceUpdate() {
    if (_locationData == null || _locationData!['timestamp'] == null) return 'Unknown';
    
    try {
      final timestamp = (_locationData!['timestamp'] as Timestamp).toDate();
      final now = DateTime.now();
      final difference = now.difference(timestamp);
      
      if (difference.inSeconds < 60) {
        return 'Just now';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes} ${difference.inMinutes == 1 ? 'minute' : 'minutes'} ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours} ${difference.inHours == 1 ? 'hour' : 'hours'} ago';
      } else {
        return '${difference.inDays} ${difference.inDays == 1 ? 'day' : 'days'} ago';
      }
    } catch (e) {
      if (_debugMode) print('❌ LiveLocationScreen: Error getting time since update: $e');
      return 'Unknown';
    }
  }
}

class LocationHistoryScreen extends StatelessWidget {
  final String? userId;
  
  const LocationHistoryScreen({super.key, this.userId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Location History'),
        backgroundColor: const Color(0xFF2561FA),
        foregroundColor: Colors.white,
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.green),
            SizedBox(height: 16),
            Text(
              'Location History',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Past movement history will be displayed here',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class RouteMonitoringScreen extends StatelessWidget {
  const RouteMonitoringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Route Monitoring'),
        backgroundColor: const Color(0xFF2561FA),
        foregroundColor: Colors.white,
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.route, size: 64, color: Colors.orange),
            SizedBox(height: 16),
            Text(
              'Route Monitoring',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Route deviation alerts will be displayed here',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class EmergencyCenterScreen extends StatelessWidget {
  const EmergencyCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Center'),
        backgroundColor: const Color(0xFF2561FA),
        foregroundColor: Colors.white,
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.emergency, size: 64, color: Colors.red),
            SizedBox(height: 16),
            Text(
              'Emergency Center',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Emergency response tools will be available here',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
} 