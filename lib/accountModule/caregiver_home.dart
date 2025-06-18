import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_profile.dart';

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

    FirebaseFirestore.instance
        .collection('emergencyAlerts')
        .where('caregiverId', isEqualTo: caregiverId)
        .where('status', isEqualTo: 'active')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _emergencyAlerts = snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          }).toList();
        });

        // Show notification for new alerts
        if (_emergencyAlerts.isNotEmpty) {
          _showEmergencyNotification(_emergencyAlerts.first);
        }
      }
    });
  }

  void _showEmergencyNotification(Map<String, dynamic> alert) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.red.shade50,
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.red.shade700, size: 28),
            const SizedBox(width: 8),
            const Text(
              'EMERGENCY ALERT',
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'From: ${alert['username'] ?? 'Unknown User'}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text('Message: ${alert['message'] ?? 'Emergency assistance needed'}'),
            if (alert['location'] != null) ...[
              const SizedBox(height: 8),
              Text('Location: ${alert['location']}'),
            ],
            const SizedBox(height: 8),
            Text(
              'Time: ${_formatTimestamp(alert['timestamp'])}',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Dismiss'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _respondToEmergency(alert);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Respond', style: TextStyle(color: Colors.white)),
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
    // Implementation for viewing user location
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
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const LiveLocationScreen(),
                            ),
                          ),
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
}

// Placeholder screens for caregiver features
class LiveLocationScreen extends StatelessWidget {
  final String? userId;
  
  const LiveLocationScreen({super.key, this.userId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Location'),
        backgroundColor: const Color(0xFF2561FA),
        foregroundColor: Colors.white,
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.location_on, size: 64, color: Colors.blue),
            SizedBox(height: 16),
            Text(
              'Live Location Tracking',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Real-time GPS location will be displayed here',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
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