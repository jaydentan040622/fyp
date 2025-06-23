import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'caregiver_home.dart';

class ConnectionRequestsScreen extends StatefulWidget {
  const ConnectionRequestsScreen({super.key});

  @override
  State<ConnectionRequestsScreen> createState() => _ConnectionRequestsScreenState();
}

class _ConnectionRequestsScreenState extends State<ConnectionRequestsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _sentRequests = [];
  List<Map<String, dynamic>> _receivedRequests = [];
  List<Map<String, dynamic>> _connectedUsers = [];
  String? _userId;
  String _userType = '';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        Navigator.pop(context);
        return;
      }

      _userId = user.uid;

      // Get user type (blind_user or caregiver)
      final userDoc = await FirebaseFirestore.instance
          .collection('userprofile')
          .doc(_userId)
          .get();

      if (userDoc.exists) {
        _userType = userDoc['userType'] ?? '';
      }

      // Load requests based on user type
      await _loadConnections();
    } catch (e) {
      print('Error loading user data: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadConnections() async {
    if (_userId == null) return;

    try {
      print('Loading connections for user: $_userId with type: $_userType');
      
      // Load sent requests
      if (_userType == 'caregiver') {
        final sentQuery = await FirebaseFirestore.instance
            .collection('caregiverConnections')
            .where('caregiverId', isEqualTo: _userId)
            .where('status', isEqualTo: 'pending')
            .get();

        print('Found ${sentQuery.docs.length} sent connection requests');
        
        _sentRequests = sentQuery.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();
      }

      // Load received requests
      if (_userType == 'blind_user') {
        final receivedQuery = await FirebaseFirestore.instance
            .collection('caregiverConnections')
            .where('userId', isEqualTo: _userId)
            .where('status', isEqualTo: 'pending')
            .get();

        print('Found ${receivedQuery.docs.length} received connection requests');
        
        _receivedRequests = receivedQuery.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();
      }

      // Load connected users
      final String fieldToCheck = _userType == 'caregiver' ? 'caregiverId' : 'userId';
      
      final connectionsQuery = await FirebaseFirestore.instance
          .collection('caregiverConnections')
          .where(fieldToCheck, isEqualTo: _userId)
          .where('status', isEqualTo: 'accepted')
          .get();

      print('Found ${connectionsQuery.docs.length} accepted connections');
      
      _connectedUsers = connectionsQuery.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('Error loading connections: $e');
    }
  }

  Future<void> _acceptRequest(String requestId) async {
    try {
      print('Accepting connection request: $requestId');
      
      // Get the request details first
      final requestDoc = await FirebaseFirestore.instance
          .collection('caregiverConnections')
          .doc(requestId)
          .get();

      if (!requestDoc.exists) {
        throw Exception('Connection request not found');
      }
      
      final data = requestDoc.data()!;
      
      // Update the connection status
      await FirebaseFirestore.instance
          .collection('caregiverConnections')
          .doc(requestId)
          .update({
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
      });

      print('Connection request accepted successfully');
      
      // Send notification to caregiver
      await FirebaseFirestore.instance.collection('notifications').add({
        'userId': data['caregiverId'],
        'title': 'Connection Request Accepted',
        'message': '${data['userName']} has accepted your connection request',
        'type': 'connection_accepted',
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'data': {
          'connectionId': requestId,
        },
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connection request accepted'),
          backgroundColor: Colors.green,
        ),
      );

      _loadConnections();
    } catch (e) {
      print('Error accepting request: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error accepting request: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _rejectRequest(String requestId) async {
    try {
      print('Rejecting connection request: $requestId');
      
      // Get the request details first
      final requestDoc = await FirebaseFirestore.instance
          .collection('caregiverConnections')
          .doc(requestId)
          .get();

      if (!requestDoc.exists) {
        throw Exception('Connection request not found');
      }
      
      final data = requestDoc.data()!;
      
      // Update the connection status
      await FirebaseFirestore.instance
          .collection('caregiverConnections')
          .doc(requestId)
          .update({
        'status': 'rejected',
        'rejectedAt': FieldValue.serverTimestamp(),
      });

      print('Connection request rejected successfully');
      
      // Send notification to caregiver
      await FirebaseFirestore.instance.collection('notifications').add({
        'userId': data['caregiverId'],
        'title': 'Connection Request Rejected',
        'message': '${data['userName']} has rejected your connection request',
        'type': 'connection_rejected',
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connection request rejected'),
          backgroundColor: Colors.orange,
        ),
      );

      _loadConnections();
    } catch (e) {
      print('Error rejecting request: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error rejecting request: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _removeConnection(String connectionId) async {
    try {
      print('Removing connection: $connectionId');
      
      await FirebaseFirestore.instance
          .collection('caregiverConnections')
          .doc(connectionId)
          .delete();

      print('Connection removed successfully');
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connection removed'),
          backgroundColor: Colors.orange,
        ),
      );

      _loadConnections();
    } catch (e) {
      print('Error removing connection: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error removing connection: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connections'),
        backgroundColor: const Color(0xFF2561FA),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadConnections,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Received requests section (for blind users)
                    if (_userType == 'blind_user' && _receivedRequests.isNotEmpty) ...[
                      const Text(
                        'Pending Requests',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Caregivers who want to connect with you',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _receivedRequests.length,
                        itemBuilder: (context, index) {
                          final request = _receivedRequests[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: const Color(0xFF2561FA),
                                        child: Text(
                                          (request['caregiverName'] ?? 'C')[0].toUpperCase(),
                                          style: const TextStyle(color: Colors.white),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              request['caregiverName'] ?? 'Caregiver',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                            if (request['caregiverEmail'] != null)
                                              Text(
                                                request['caregiverEmail'],
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'This caregiver wants to connect with you to help monitor your location and provide assistance.',
                                    style: TextStyle(fontSize: 14),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      OutlinedButton(
                                        onPressed: () => _rejectRequest(request['id']),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.red,
                                          side: const BorderSide(color: Colors.red),
                                        ),
                                        child: const Text('Reject'),
                                      ),
                                      const SizedBox(width: 12),
                                      ElevatedButton(
                                        onPressed: () => _acceptRequest(request['id']),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF2561FA),
                                          foregroundColor: Colors.white,
                                        ),
                                        child: const Text('Accept'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                    ],
                    
                    // Sent requests section (for caregivers)
                    if (_userType == 'caregiver' && _sentRequests.isNotEmpty) ...[
                      const Text(
                        'Pending Requests',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Requests you\'ve sent to blind users',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _sentRequests.length,
                        itemBuilder: (context, index) {
                          final request = _sentRequests[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: Colors.orange,
                                    child: Text(
                                      (request['userName'] ?? 'U')[0].toUpperCase(),
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          request['userName'] ?? 'User',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        if (request['userEmail'] != null)
                                          Text(
                                            request['userEmail'],
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        const SizedBox(height: 4),
                                        const Text(
                                          'Waiting for user to accept',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontStyle: FontStyle.italic,
                                            color: Colors.orange,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                    ],
                    
                    // Connected users section
                    if (_connectedUsers.isNotEmpty) ...[
                      const Text(
                        'Connected Users',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _connectedUsers.length,
                        itemBuilder: (context, index) {
                          final connection = _connectedUsers[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xFF2561FA),
                                child: Text(
                                  (connection['userName'] ?? 'U')[0].toUpperCase(),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              title: Text(connection['userName'] ?? 'User'),
                              subtitle: Text('Connected'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.delete),
                                    color: Colors.red,
                                    onPressed: () => _removeConnection(connection['id']),
                                  ),
                                  if (_userType == 'caregiver')
                                    IconButton(
                                      icon: const Icon(Icons.location_on),
                                      color: const Color(0xFF2561FA),
                                      onPressed: () {
                                        // Navigate to live location screen
                                        Navigator.pop(context);
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => LiveLocationScreen(
                                              userId: connection['userId'],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],

                    // No connections state
                    if (_connectedUsers.isEmpty)
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 40),
                            Icon(
                              Icons.people_outline,
                              size: 80,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No connections yet',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _userType == 'caregiver'
                                  ? 'Add blind users to connect with them'
                                  : 'Wait for caregivers to send you connection requests',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            if (_userType == 'caregiver')
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                },
                                icon: const Icon(Icons.person_add),
                                label: const Text('Add Blind User'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2561FA),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 12,
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
      floatingActionButton: _userType == 'caregiver'
          ? FloatingActionButton(
              onPressed: () {
                Navigator.pop(context);
                // Show add blind user dialog
              },
              backgroundColor: const Color(0xFF2561FA),
              child: const Icon(Icons.person_add),
            )
          : null,
    );
  }
}
