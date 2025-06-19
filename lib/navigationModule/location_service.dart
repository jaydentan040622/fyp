import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  StreamSubscription<Position>? _positionStream;
  String? _currentUserId;
  List<String> _caregiverIds = [];
  bool _isTracking = false;
  Position? _lastKnownPosition;

  // Initialize the service
  Future<void> initialize() async {
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (_currentUserId != null) {
      await _loadCaregivers();
    }
  }

  // Load connected caregivers
  Future<void> _loadCaregivers() async {
    if (_currentUserId == null) return;
    
    try {
      _caregiverIds.clear();
      
      // Check user profile for direct caregiver
      final userDoc = await FirebaseFirestore.instance
          .collection('userprofile')
          .doc(_currentUserId)
          .get();
      
      if (userDoc.exists) {
        final caregiverId = userDoc.data()?['caregiverId'];
        if (caregiverId != null) {
          _caregiverIds.add(caregiverId);
        }
      }
      
      // Check for caregiver connections
      final connections = await FirebaseFirestore.instance
          .collection('caregiverConnections')
          .where('userId', isEqualTo: _currentUserId)
          .where('status', isEqualTo: 'accepted')
          .get();
      
      for (var doc in connections.docs) {
        final caregiverId = doc.data()['caregiverId'];
        if (caregiverId != null && !_caregiverIds.contains(caregiverId)) {
          _caregiverIds.add(caregiverId);
        }
      }
    } catch (e) {
      print('Error loading caregivers: $e');
    }
  }

  // Start background location tracking
  Future<void> startBackgroundTracking() async {
    if (_isTracking || _currentUserId == null) return;

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position position) {
        _lastKnownPosition = position;
        _saveLocationToFirebase(position);
      },
      onError: (error) {
        print('Background location tracking error: $error');
      },
    );

    _isTracking = true;
  }

  // Stop background location tracking
  void stopBackgroundTracking() {
    _positionStream?.cancel();
    _positionStream = null;
    _isTracking = false;
  }

  // Save location to Firebase
  Future<void> _saveLocationToFirebase(Position position, {bool isEmergency = false}) async {
    if (_currentUserId == null) return;
    
    try {
      final locationData = {
        'userId': _currentUserId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'speed': position.speed,
        'heading': position.heading,
        'timestamp': FieldValue.serverTimestamp(),
        'isEmergency': isEmergency,
      };
      
      // Update current location
      await FirebaseFirestore.instance
          .collection('userLocations')
          .doc(_currentUserId)
          .set(locationData);
      
      // Save to location history (but limit to prevent excessive data)
      await FirebaseFirestore.instance
          .collection('locationHistory')
          .add(locationData);
          
      // Clean up old location history (keep only last 1000 entries)
      await _cleanupLocationHistory();
          
    } catch (e) {
      print('Error saving location to Firebase: $e');
    }
  }

  // Clean up old location history
  Future<void> _cleanupLocationHistory() async {
    if (_currentUserId == null) return;
    
    try {
      final query = await FirebaseFirestore.instance
          .collection('locationHistory')
          .where('userId', isEqualTo: _currentUserId)
          .orderBy('timestamp', descending: true)
          .limit(1001) // Get one more than we want to keep
          .get();
      
      if (query.docs.length > 1000) {
        // Delete the oldest entries
        final batch = FirebaseFirestore.instance.batch();
        for (int i = 1000; i < query.docs.length; i++) {
          batch.delete(query.docs[i].reference);
        }
        await batch.commit();
      }
    } catch (e) {
      print('Error cleaning up location history: $e');
    }
  }

  // Send emergency alert to all caregivers
  Future<void> sendEmergencyAlert(Position position, String message) async {
    if (_currentUserId == null || _caregiverIds.isEmpty) return;
    
    try {
      final emergencyData = {
        'userId': _currentUserId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'timestamp': FieldValue.serverTimestamp(),
        'message': message,
        'isActive': true,
      };
      
      // Send emergency alert to all caregivers
      for (String caregiverId in _caregiverIds) {
        await FirebaseFirestore.instance
            .collection('emergencyAlerts')
            .add({...emergencyData, 'caregiverId': caregiverId});
        
        // Create urgent notification
        await FirebaseFirestore.instance
            .collection('notifications')
            .add({
              'userId': caregiverId,
              'title': '🚨 EMERGENCY ALERT',
              'message': message,
              'type': 'emergency',
              'timestamp': FieldValue.serverTimestamp(),
              'isRead': false,
              'priority': 'urgent',
            });
      }
      
      // Save emergency location
      await _saveLocationToFirebase(position, isEmergency: true);
      
    } catch (e) {
      print('Error sending emergency alert: $e');
      throw Exception('Failed to send emergency alert');
    }
  }

  // Send route deviation alert
  Future<void> sendRouteDeviationAlert(Position position, double deviation, double maxAllowed) async {
    if (_currentUserId == null || _caregiverIds.isEmpty) return;
    
    try {
      final alertData = {
        'userId': _currentUserId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'deviationDistance': deviation,
        'maxAllowedDistance': maxAllowed,
        'timestamp': FieldValue.serverTimestamp(),
        'message': 'User has deviated ${deviation.toStringAsFixed(1)} meters from expected route',
      };
      
      for (String caregiverId in _caregiverIds) {
        await FirebaseFirestore.instance
            .collection('routeAlerts')
            .add({...alertData, 'caregiverId': caregiverId});
        
        // Also create a notification
        await FirebaseFirestore.instance
            .collection('notifications')
            .add({
              'userId': caregiverId,
              'title': 'Route Deviation Alert',
              'message': 'User has deviated from expected route',
              'type': 'route_deviation',
              'timestamp': FieldValue.serverTimestamp(),
              'isRead': false,
            });
      }
    } catch (e) {
      print('Error sending route deviation alert: $e');
    }
  }

  // Get real-time location updates for caregivers
  Stream<DocumentSnapshot> getLocationUpdates(String userId) {
    return FirebaseFirestore.instance
        .collection('userLocations')
        .doc(userId)
        .snapshots();
  }

  // Get location history
  Future<List<Map<String, dynamic>>> getLocationHistory(String userId, {int limit = 50}) async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('locationHistory')
          .where('userId', isEqualTo: userId)
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .get();
      
      return query.docs.map((doc) => {
        'id': doc.id,
        ...doc.data(),
      }).toList();
    } catch (e) {
      print('Error getting location history: $e');
      return [];
    }
  }

  // Calculate distance between two points
  double calculateDistance(LatLng point1, LatLng point2) {
    return Geolocator.distanceBetween(
      point1.latitude,
      point1.longitude,
      point2.latitude,
      point2.longitude,
    );
  }

  // Check if user is within geofence
  bool isWithinGeofence(Position position, LatLng center, double radiusInMeters) {
    double distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      center.latitude,
      center.longitude,
    );
    return distance <= radiusInMeters;
  }

  // Get current position
  Future<Position?> getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      print('Error getting current position: $e');
      return null;
    }
  }

  // Check location permissions
  Future<bool> checkPermissions() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      return permission == LocationPermission.whileInUse || 
             permission == LocationPermission.always;
    } catch (e) {
      print('Error checking permissions: $e');
      return false;
    }
  }

  // Getters
  bool get isTracking => _isTracking;
  Position? get lastKnownPosition => _lastKnownPosition;
  List<String> get caregiverIds => List.unmodifiable(_caregiverIds);

  // Dispose resources
  void dispose() {
    stopBackgroundTracking();
  }
} 