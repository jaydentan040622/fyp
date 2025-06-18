import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:async';

class CaregiverServices {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // Send emergency alert to caregiver
  static Future<void> sendEmergencyAlert({
    required String caregiverId,
    required String message,
    Map<String, dynamic>? location,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Get user profile
      final userDoc = await _firestore.collection('userprofile').doc(user.uid).get();
      final userData = userDoc.data();

      await _firestore.collection('emergencyAlerts').add({
        'userId': user.uid,
        'username': userData?['username'] ?? 'Unknown User',
        'caregiverId': caregiverId,
        'message': message,
        'location': location,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'active',
        'type': 'emergency',
      });

      // Also create a notification for the caregiver
      await _firestore.collection('notifications').add({
        'userId': caregiverId,
        'title': 'Emergency Alert',
        'body': '${userData?['username'] ?? 'A user'} needs emergency assistance',
        'type': 'emergency',
        'data': {
          'alertUserId': user.uid,
          'username': userData?['username'],
          'message': message,
          'location': location,
        },
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
      });

      print('Emergency alert sent successfully');
    } catch (e) {
      print('Error sending emergency alert: $e');
      throw e;
    }
  }

  // Send route deviation alert
  static Future<void> sendRouteDeviationAlert({
    required String caregiverId,
    required Map<String, dynamic> currentLocation,
    required Map<String, dynamic> expectedRoute,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final userDoc = await _firestore.collection('userprofile').doc(user.uid).get();
      final userData = userDoc.data();

      await _firestore.collection('routeAlerts').add({
        'userId': user.uid,
        'username': userData?['username'] ?? 'Unknown User',
        'caregiverId': caregiverId,
        'currentLocation': currentLocation,
        'expectedRoute': expectedRoute,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'active',
        'deviation': 'User has strayed from expected route',
      });

      // Create notification
      await _firestore.collection('notifications').add({
        'userId': caregiverId,
        'title': 'Route Deviation Alert',
        'body': '${userData?['username'] ?? 'A user'} has deviated from their planned route',
        'type': 'route_deviation',
        'data': {
          'alertUserId': user.uid,
          'username': userData?['username'],
          'currentLocation': currentLocation,
          'expectedRoute': expectedRoute,
        },
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
      });

      print('Route deviation alert sent successfully');
    } catch (e) {
      print('Error sending route deviation alert: $e');
      throw e;
    }
  }

  // Update location for tracking
  static Future<void> updateLocation({
    required double latitude,
    required double longitude,
    String? address,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Update current location
      await _firestore.collection('userLocations').doc(user.uid).set({
        'userId': user.uid,
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        'timestamp': FieldValue.serverTimestamp(),
        'isActive': true,
      });

      // Add to location history
      await _firestore.collection('locationHistory').add({
        'userId': user.uid,
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        'timestamp': FieldValue.serverTimestamp(),
      });

      print('Location updated successfully');
    } catch (e) {
      print('Error updating location: $e');
      throw e;
    }
  }

  // Get caregiver's connected users
  static Stream<List<Map<String, dynamic>>> getConnectedUsers(String caregiverId) {
    return _firestore
        .collection('userprofile')
        .where('userType', isEqualTo: 'blind_user')
        .where('caregiverId', isEqualTo: caregiverId)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    });
  }

  // Get live location of a user
  static Stream<Map<String, dynamic>?> getUserLiveLocation(String userId) {
    return _firestore
        .collection('userLocations')
        .doc(userId)
        .snapshots()
        .map((doc) {
      if (doc.exists) {
        final data = doc.data()!;
        data['id'] = doc.id;
        return data;
      }
      return null;
    });
  }

  // Get location history of a user
  static Stream<List<Map<String, dynamic>>> getUserLocationHistory(
    String userId, {
    int limit = 50,
  }) {
    return _firestore
        .collection('locationHistory')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    });
  }

  // Get emergency alerts for caregiver
  static Stream<List<Map<String, dynamic>>> getEmergencyAlerts(String caregiverId) {
    return _firestore
        .collection('emergencyAlerts')
        .where('caregiverId', isEqualTo: caregiverId)
        .where('status', isEqualTo: 'active')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    });
  }

  // Get route alerts for caregiver
  static Stream<List<Map<String, dynamic>>> getRouteAlerts(String caregiverId) {
    return _firestore
        .collection('routeAlerts')
        .where('caregiverId', isEqualTo: caregiverId)
        .where('status', isEqualTo: 'active')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    });
  }

  // Mark emergency alert as resolved
  static Future<void> resolveEmergencyAlert(String alertId) async {
    try {
      await _firestore.collection('emergencyAlerts').doc(alertId).update({
        'status': 'resolved',
        'resolvedAt': FieldValue.serverTimestamp(),
      });
      print('Emergency alert resolved');
    } catch (e) {
      print('Error resolving emergency alert: $e');
      throw e;
    }
  }

  // Mark route alert as resolved
  static Future<void> resolveRouteAlert(String alertId) async {
    try {
      await _firestore.collection('routeAlerts').doc(alertId).update({
        'status': 'resolved',
        'resolvedAt': FieldValue.serverTimestamp(),
      });
      print('Route alert resolved');
    } catch (e) {
      print('Error resolving route alert: $e');
      throw e;
    }
  }

  // Add caregiver connection (called by blind user only)
  static Future<void> addCaregiverConnection({
    required String caregiverEmail,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    // Check if current user is a blind user
    final currentUserDoc = await _firestore.collection('userprofile').doc(user.uid).get();
    if (!currentUserDoc.exists) {
      throw Exception('User profile not found');
    }
    
    final currentUserType = currentUserDoc.data()?['userType'];
    if (currentUserType != 'blind_user') {
      throw Exception('Only blind users can add caregivers');
    }

    // Find caregiver by email
    final caregiverQuery = await _firestore
        .collection('userprofile')
        .where('email', isEqualTo: caregiverEmail)
        .where('userType', isEqualTo: 'caregiver')
        .get();

    if (caregiverQuery.docs.isEmpty) {
      throw Exception('Caregiver not found or email does not belong to a registered caregiver');
    }

    final caregiverDoc = caregiverQuery.docs.first;
    final caregiverId = caregiverDoc.id;
    final caregiverData = caregiverDoc.data();

    try {
      // CRITICAL OPERATION: Update user's profile with caregiver ID
      // This is the main operation that must succeed
      await _firestore.collection('userprofile').doc(user.uid).update({
        'caregiverId': caregiverId,
        'caregiverEmail': caregiverEmail,
        'caregiverConnectedAt': FieldValue.serverTimestamp(),
      });

      print('User profile updated with caregiver connection');

      // OPTIONAL OPERATIONS: These can fail without affecting the main connection
      // Create connection record (optional)
      try {
        await _firestore.collection('caregiverConnections').add({
          'userId': user.uid,
          'caregiverId': caregiverId,
          'userEmail': currentUserDoc.data()?['email'] ?? '',
          'userName': currentUserDoc.data()?['username'] ?? '',
          'caregiverEmail': caregiverEmail,
          'caregiverName': caregiverData['username'] ?? '',
          'connectedAt': FieldValue.serverTimestamp(),
          'status': 'active',
        });
        print('Connection record created successfully');
      } catch (connectionError) {
        print('Warning: Failed to create connection record: $connectionError');
        // Don't throw - connection is still valid without this record
      }

      // Notify caregiver (optional)
      try {
        await _firestore.collection('notifications').add({
          'userId': caregiverId,
          'title': 'New User Connection',
          'body': '${currentUserDoc.data()?['username'] ?? 'A user'} has added you as their caregiver',
          'type': 'connection',
          'data': {
            'userId': user.uid,
            'userName': currentUserDoc.data()?['username'] ?? '',
            'userEmail': currentUserDoc.data()?['email'] ?? '',
          },
          'timestamp': FieldValue.serverTimestamp(),
          'read': false,
        });
        print('Caregiver notification sent successfully');
      } catch (notificationError) {
        print('Warning: Failed to send notification to caregiver: $notificationError');
        // Don't throw - connection is still valid without notification
      }

      print('Caregiver connection added successfully');
      
    } catch (e) {
      print('Error in critical operation (updating user profile): $e');
      // Only throw if the critical operation fails
      throw Exception('Failed to add caregiver connection: ${e.toString()}');
    }
  }

  // Remove caregiver connection (called by blind user only)
  static Future<void> removeCaregiverConnection() async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Check if current user is a blind user
      final currentUserDoc = await _firestore.collection('userprofile').doc(user.uid).get();
      if (!currentUserDoc.exists) {
        throw Exception('User profile not found');
      }
      
      final currentUserType = currentUserDoc.data()?['userType'];
      if (currentUserType != 'blind_user') {
        throw Exception('Only blind users can remove caregivers');
      }

      // Remove caregiver from user profile
      await _firestore.collection('userprofile').doc(user.uid).update({
        'caregiverId': FieldValue.delete(),
        'caregiverEmail': FieldValue.delete(),
        'caregiverConnectedAt': FieldValue.delete(),
      });

      // Update connection status
      final connectionQuery = await _firestore
          .collection('caregiverConnections')
          .where('userId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'active')
          .get();

      for (final doc in connectionQuery.docs) {
        await doc.reference.update({
          'status': 'disconnected',
          'disconnectedAt': FieldValue.serverTimestamp(),
        });
      }

      print('Caregiver connection removed successfully');
    } catch (e) {
      print('Error removing caregiver connection: $e');
      throw e;
    }
  }

  // Get notifications for user
  static Stream<List<Map<String, dynamic>>> getNotifications(String userId) {
    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .limit(20)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    });
  }

  // Mark notification as read
  static Future<void> markNotificationAsRead(String notificationId) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).update({
        'read': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error marking notification as read: $e');
      throw e;
    }
  }
} 