import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'accessibility_service.dart';

class LiveLocationTrackingPage extends StatefulWidget {
  const LiveLocationTrackingPage({super.key});

  @override
  State<LiveLocationTrackingPage> createState() => _LiveLocationTrackingPageState();
}

class _LiveLocationTrackingPageState extends State<LiveLocationTrackingPage> with WidgetsBindingObserver {
  // Map and Location
  GoogleMapController? _mapController;
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  Set<Circle> _circles = {};
  
  // Tracking State
  bool _isTracking = false;
  bool _permissionGranted = false;
  List<LatLng> _currentRoute = [];
  List<LatLng> _expectedRoute = [];
  bool _routeDeviationEnabled = false;
  double _maxDeviationDistance = 100.0;
  Timer? _locationUpdateTimer;
  Timer? _periodicAnnouncementTimer;
  Timer? _voiceListeningTimer;
  
  // User Data
  String? _currentUserId;
  List<String> _caregiverIds = [];
  
  // UI States
  bool _isLoading = true;
  bool _showRoutePanel = false;
  bool _emergencyMode = false;
  bool _showAccessibilityPanel = false;
  
  // Accessibility Service
  final AccessibilityService _accessibilityService = AccessibilityService();
  bool _accessibilityInitialized = false;
  
  // Voice Command States
  bool _isListeningForCommands = false;
  bool _continuousListening = true;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeEverything();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionStream?.cancel();
    _locationUpdateTimer?.cancel();
    _periodicAnnouncementTimer?.cancel();
    _voiceListeningTimer?.cancel();
    _accessibilityService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _accessibilityInitialized) {
      _startContinuousListening();
    } else if (state == AppLifecycleState.paused) {
      _stopContinuousListening();
    }
  }

  Future<void> _initializeEverything() async {
    try {
      setState(() {
        _isLoading = true;
      });
      
      // Initialize basic data
      _currentUserId = FirebaseAuth.instance.currentUser?.uid;
      await _loadCaregivers();
      
      // Initialize accessibility service first
      await _initializeAccessibilityService();
      
      // Request permissions
      await _requestPermissions();
      
      // Get initial location
      await _getCurrentLocation();
      
      // Start continuous listening and periodic announcements
      _startContinuousListening();
      _startPeriodicAnnouncements();
      
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        
        // Welcome message
        await _accessibilityService.speak(
          'Live location tracking loaded. You can now use voice commands. '
          'Say "help" for available commands or "start tracking" to begin.',
          priority: true
        );
      }
    } catch (e) {
      _showErrorSnackBar('Failed to initialize: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _initializeAccessibilityService() async {
    try {
      print('🔄 Initializing accessibility services...');
      await _accessibilityService.initialize();
      
      // Wait a moment for the initialization to complete properly
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Set up voice command callbacks
      _accessibilityService.setVoiceCommandCallback(_handleVoiceCommand);
      
      _accessibilityInitialized = true;
      print('✅ Accessibility services initialized successfully');
      
      // Show a notification to indicate it's working
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Voice commands activated! Say "help" for available commands.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );
      
    } catch (e) {
      print('❌ Failed to initialize accessibility service: $e');
      _showErrorSnackBar('Voice commands may not work properly. Please restart the app.');
    }
  }

  void _handleVoiceCommand(String command) {
    print('🎯 Handling voice command: "$command"');
    
    // Show visual feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Voice command: $command'),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 1),
      ),
    );
    
    switch (command) {
      case 'start_tracking':
        print('▶️ Starting live tracking');
        _startLiveTracking();
        break;
      case 'stop_tracking':
        print('⏹️ Stopping live tracking');
        _stopLiveTracking();
        break;
      case 'emergency':
        print('🚨 Triggering emergency');
        _triggerEmergency();
        break;
      case 'set_route':
        print('🔄 Toggling route panel');
        _toggleRoutePanel();
        break;
      case 'status':
        print('ℹ️ Announcing status');
        _announceCurrentStatus();
        break;
      case 'help':
        print('❓ Announcing help');
        _announceHelp();
        break;
      case 'where_am_i':
        print('🗺️ Announcing location');
        _accessibilityService.speak('Retrieving your location...', priority: false);
        _getCurrentLocation();
        break;
      default:
        print('⚠️ Unknown command: $command');
        _accessibilityService.speak('Command received: $command');
        break;
    }
  }

  void _startContinuousListening() {
    if (!_accessibilityInitialized || !_continuousListening) {
      print('Cannot start continuous listening: initialized=$_accessibilityInitialized, continuous=$_continuousListening');
      return;
    }
    
    print('🔁 Starting continuous listening service...');
    _voiceListeningTimer?.cancel();
    
    // Start the first voice recognition immediately
    _tryStartListening();
    
    // Then set up periodic attempts
    _voiceListeningTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) async {
      _tryStartListening();
    });
  }
  
  void _tryStartListening() async {
    if (!_accessibilityService.isListening && mounted && _accessibilityInitialized) {
      try {
        print('🎯 Trying to start voice listening...');
        await _accessibilityService.startListening();
      } catch (e) {
        print('❌ Error starting voice listening: $e');
      }
    }
  }

  void _stopContinuousListening() {
    _voiceListeningTimer?.cancel();
    _accessibilityService.stopListening();
  }

  void _startPeriodicAnnouncements() {
    _periodicAnnouncementTimer?.cancel();
    _periodicAnnouncementTimer = Timer.periodic(const Duration(minutes: 2), (timer) {
      if (_isTracking && _currentPosition != null) {
        _accessibilityService.announceLocationUpdate(_currentPosition!);
      }
    });
  }

  Future<void> _loadCaregivers() async {
    if (_currentUserId == null) return;
    
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('userprofile')
          .doc(_currentUserId)
          .get();
      
      if (userDoc.exists) {
        final caregiverId = userDoc.data()?['caregiverId'];
        if (caregiverId != null) {
          _caregiverIds = [caregiverId];
        }
        
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
      }
    } catch (e) {
      print('Error loading caregivers: $e');
    }
  }

  Future<void> _requestPermissions() async {
    try {
      // Location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      if (permission == LocationPermission.deniedForever) {
        await _accessibilityService.speak(
          'Location permissions are permanently denied. Please enable them in device settings.',
          priority: true
        );
        return;
      }
      
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        setState(() {
          _permissionGranted = true;
        });
        
        await _accessibilityService.speak('Location permissions granted.');
        
        // Request microphone permission for voice commands
        await Permission.microphone.request();
        await Permission.locationAlways.request();
      }
    } catch (e) {
      await _accessibilityService.speak('Failed to request permissions');
    }
  }

  Future<void> _getCurrentLocation() async {
    if (!_permissionGranted) return;
    
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      setState(() {
        _currentPosition = position;
        _updateMapMarkers();
      });
      
      if (_mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(position.latitude, position.longitude),
              zoom: 16.0,
            ),
          ),
        );
      }
      
      await _saveLocationToFirebase(position);
      await _accessibilityService.updateNavigationProgress(position);
      
    } catch (e) {
      await _accessibilityService.speak('Failed to get current location');
    }
  }

  void _updateMapMarkers() {
    if (_currentPosition == null) return;
    
    _markers.clear();
    _markers.add(
      Marker(
        markerId: const MarkerId('current_location'),
        position: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        infoWindow: InfoWindow(
          title: 'Your Location',
          snippet: 'Speed: ${_currentPosition!.speed.toStringAsFixed(1)} m/s',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      ),
    );
  }

  void _startLiveTracking() async {
    if (!_permissionGranted || _isTracking) {
      _accessibilityService.speak('Cannot start tracking. Check permissions.');
      return;
    }
    
    print('🔄 Starting live location tracking...');
    
    setState(() {
      _isTracking = true;
    });
    
    // Get current position immediately to update Firebase
    try {
      Position currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      // Update map and save to Firebase immediately
      _updateLocationOnMap(currentPosition);
      await _saveLocationToFirebase(currentPosition);
      
      print('✅ Initial position saved to Firebase');
    } catch (e) {
      print('❌ Error getting initial position: $e');
    }
    
    // Then start continuous tracking
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );
    
    _positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position position) {
        print('📍 Position update received: lat=${position.latitude}, lng=${position.longitude}');
        _updateLocationOnMap(position);
        _saveLocationToFirebase(position);
        _checkRouteDeviation(position);
        _accessibilityService.updateNavigationProgress(position);
      },
      onError: (error) {
        print('❌ Position stream error: $error');
        _accessibilityService.speak('Location tracking error occurred');
        _stopLiveTracking();
      },
    );
    
    _accessibilityService.speak('Live location tracking started. Your location is now being shared with caregivers.', priority: true);
  }

  void _stopLiveTracking() async {
    print('🔄 Stopping live location tracking...');
    
    setState(() {
      _isTracking = false;
    });
    
    _positionStream?.cancel();
    _positionStream = null;
    
    // Update Firebase to indicate tracking has stopped
    if (_currentUserId != null && _currentPosition != null) {
      try {
        await FirebaseFirestore.instance
            .collection('userLocations')
            .doc(_currentUserId)
            .update({
              'isTracking': false,
              'timestamp': FieldValue.serverTimestamp(),
            });
        print('✅ Tracking status updated in Firebase');
      } catch (e) {
        print('❌ Error updating tracking status in Firebase: $e');
      }
    }
    
    _accessibilityService.speak('Live location tracking stopped.', priority: true);
  }

  void _updateLocationOnMap(Position position) {
    setState(() {
      _currentPosition = position;
      
      _updateMapMarkers();
      
      _currentRoute.add(LatLng(position.latitude, position.longitude));
      
      if (_currentRoute.length > 1) {
        _polylines.clear();
        _polylines.add(
          Polyline(
            polylineId: const PolylineId('current_route'),
            points: _currentRoute,
            color: Colors.blue,
            width: 4,
          ),
        );
      }
    });
  }

  Future<void> _saveLocationToFirebase(Position position) async {
    if (_currentUserId == null) return;
    
    try {
      print('📍 Saving location to Firebase: lat=${position.latitude}, lng=${position.longitude}, emergency=${_emergencyMode}');
      
      final locationData = {
        'userId': _currentUserId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'speed': position.speed,
        'heading': position.heading,
        'timestamp': FieldValue.serverTimestamp(),
        'isEmergency': _emergencyMode,
        'isTracking': _isTracking,
      };
      
      // Save current location (this is what caregivers will monitor)
      await FirebaseFirestore.instance
          .collection('userLocations')
          .doc(_currentUserId)
          .set(locationData);
      
      // Also save to history for tracking purposes
      await FirebaseFirestore.instance
          .collection('locationHistory')
          .add(locationData);
      
      print('✅ Location saved successfully');
          
    } catch (e) {
      print('❌ Error saving location to Firebase: $e');
    }
  }

  void _checkRouteDeviation(Position position) {
    if (!_routeDeviationEnabled || _expectedRoute.isEmpty) return;
    
    double minDistance = double.infinity;
    
    for (LatLng expectedPoint in _expectedRoute) {
      double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        expectedPoint.latitude,
        expectedPoint.longitude,
      );
      
      if (distance < minDistance) {
        minDistance = distance;
      }
    }
    
    if (minDistance > _maxDeviationDistance) {
      _sendRouteDeviationAlert(position, minDistance);
      _accessibilityService.announceRouteDeviation(minDistance);
    }
  }

  Future<void> _sendRouteDeviationAlert(Position position, double deviation) async {
    if (_currentUserId == null || _caregiverIds.isEmpty) return;
    
    try {
      final alertData = {
        'userId': _currentUserId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'deviationDistance': deviation,
        'maxAllowedDistance': _maxDeviationDistance,
        'timestamp': FieldValue.serverTimestamp(),
        'message': 'User has deviated ${deviation.toStringAsFixed(1)} meters from expected route',
      };
      
      for (String caregiverId in _caregiverIds) {
        await FirebaseFirestore.instance
            .collection('routeAlerts')
            .add({...alertData, 'caregiverId': caregiverId});
        
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

  Future<void> _triggerEmergency() async {
    if (_currentUserId == null || _currentPosition == null) {
      await _accessibilityService.speak('Cannot trigger emergency: Location not available');
      return;
    }
    
    setState(() {
      _emergencyMode = true;
    });
    
    try {
      final emergencyData = {
        'userId': _currentUserId,
        'latitude': _currentPosition!.latitude,
        'longitude': _currentPosition!.longitude,
        'timestamp': FieldValue.serverTimestamp(),
        'message': 'EMERGENCY: Immediate assistance required',
        'isActive': true,
      };
      
      for (String caregiverId in _caregiverIds) {
        await FirebaseFirestore.instance
            .collection('emergencyAlerts')
            .add({...emergencyData, 'caregiverId': caregiverId});
        
        await FirebaseFirestore.instance
            .collection('notifications')
            .add({
              'userId': caregiverId,
              'title': '🚨 EMERGENCY ALERT',
              'message': 'User needs immediate assistance!',
              'type': 'emergency',
              'timestamp': FieldValue.serverTimestamp(),
              'isRead': false,
              'priority': 'urgent',
            });
      }
      
      await _saveLocationToFirebase(_currentPosition!);
      await _accessibilityService.announceEmergency();
      
      _showEmergencyDialog();
      
    } catch (e) {
      await _accessibilityService.speak('Failed to send emergency alert');
      setState(() {
        _emergencyMode = false;
      });
    }
  }

  void _showEmergencyDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.red.shade50,
          title: Row(
            children: [
              Icon(Icons.warning, color: Colors.red.shade700, size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'EMERGENCY ACTIVE',
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Emergency alert sent to caregivers!',
                style: TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 20),
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton.icon(
                      onPressed: () => _callEmergencyServices(),
                      icon: const Icon(Icons.phone, size: 30),
                      label: const Text('Call Emergency Services', style: TextStyle(fontSize: 18)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton.icon(
                      onPressed: () => _shareLocationViaMessage(),
                      icon: const Icon(Icons.share, size: 30),
                      label: const Text('Share Location via SMS', style: TextStyle(fontSize: 18)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  _emergencyMode = false;
                });
                Navigator.of(context).pop();
                _accessibilityService.speak('Emergency cancelled.');
              },
              child: const Text('Cancel Emergency', style: TextStyle(fontSize: 16)),
            ),
          ],
        );
      },
    );
  }

  void _callEmergencyServices() async {
    const phoneNumber = 'tel:911';
    if (await canLaunchUrl(Uri.parse(phoneNumber))) {
      await launchUrl(Uri.parse(phoneNumber));
      await _accessibilityService.speak('Calling emergency services');
    } else {
      await _accessibilityService.speak('Could not make emergency call');
    }
  }

  void _shareLocationViaMessage() async {
    if (_currentPosition == null) return;
    
    final locationUrl = 'https://www.google.com/maps?q=${_currentPosition!.latitude},${_currentPosition!.longitude}';
    final message = 'EMERGENCY: I need help! My location: $locationUrl';
    final smsUrl = 'sms:?body=${Uri.encodeComponent(message)}';
    
    if (await canLaunchUrl(Uri.parse(smsUrl))) {
      await launchUrl(Uri.parse(smsUrl));
      await _accessibilityService.speak('Opening SMS to share location');
    } else {
      await _accessibilityService.speak('Could not open SMS app');
    }
  }

  void _toggleRoutePanel() {
    setState(() {
      _showRoutePanel = !_showRoutePanel;
    });
    
    if (_showRoutePanel) {
      _accessibilityService.speak('Route settings panel opened. You can now set your expected route by tapping on the map.');
    } else {
      _accessibilityService.speak('Route settings panel closed.');
    }
  }

  void _toggleAccessibilityPanel() {
    setState(() {
      _showAccessibilityPanel = !_showAccessibilityPanel;
    });
    
    if (_showAccessibilityPanel) {
      _accessibilityService.speak('Accessibility settings panel opened.');
    } else {
      _accessibilityService.speak('Accessibility settings panel closed.');
    }
  }

  void _onMapTapped(LatLng position) {
    if (_showRoutePanel && !_routeDeviationEnabled) {
      setState(() {
        _expectedRoute.add(position);
        
        _markers.add(
          Marker(
            markerId: MarkerId('route_point_${_expectedRoute.length}'),
            position: position,
            infoWindow: InfoWindow(title: 'Route Point ${_expectedRoute.length}'),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          ),
        );
        
        if (_expectedRoute.length > 1) {
          _polylines.removeWhere((polyline) => polyline.polylineId.value == 'expected_route');
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('expected_route'),
              points: _expectedRoute,
              color: Colors.green,
              width: 3,
              patterns: [PatternItem.dash(20), PatternItem.gap(10)],
            ),
          );
        }
      });
      
      _accessibilityService.speak('Route point ${_expectedRoute.length} added.');
    }
  }

  void _activateRouteDeviation() {
    if (_expectedRoute.length < 2) {
      _accessibilityService.speak('Please set at least 2 route points before activating route monitoring.');
      return;
    }
    
    setState(() {
      _routeDeviationEnabled = true;
      _showRoutePanel = false;
    });
    
    _accessibilityService.announceNavigationStart(_expectedRoute);
  }

  void _announceCurrentStatus() {
    String status = 'Current status: ';
    status += _permissionGranted ? 'GPS enabled. ' : 'GPS disabled. ';
    status += _isTracking ? 'Tracking active. ' : 'Tracking inactive. ';
    status += _routeDeviationEnabled ? 'Route monitoring active. ' : 'Route monitoring inactive. ';
    
    if (_caregiverIds.isNotEmpty) {
      status += '${_caregiverIds.length} caregiver${_caregiverIds.length > 1 ? 's' : ''} connected.';
    } else {
      status += 'No caregivers connected.';
    }
    
    _accessibilityService.speak(status, priority: true);
  }

  void _announceHelp() {
    const helpText = 'Available voice commands: '
        'Say "start tracking" to begin location sharing. '
        'Say "stop tracking" to stop sharing. '
        'Say "emergency" or "help" for immediate assistance. '
        'Say "where am I" for current location. '
        'Say "what direction" for compass direction. '
        'Say "status" for current system status. '
        'Say "set route" to configure expected path. '
        'Say "repeat" to hear the last announcement again. '
        'Say "quiet" to disable voice feedback, or "speak" to enable it.';
    
    _accessibilityService.speak(helpText, priority: true);
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 16)),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 16)),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF2561FA),
        foregroundColor: Colors.white,
        title: const Text('Live Location Tracking', style: TextStyle(fontSize: 20)),
        actions: [
          // Large touch target for tracking toggle
          Container(
            margin: const EdgeInsets.all(4),
            child: ElevatedButton.icon(
              onPressed: _isTracking ? _stopLiveTracking : _startLiveTracking,
              icon: Icon(_isTracking ? Icons.pause : Icons.play_arrow, size: 24),
              label: Text(_isTracking ? 'Stop' : 'Start', style: const TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isTracking ? Colors.orange : Colors.green,
                foregroundColor: Colors.white,
                minimumSize: const Size(80, 40),
              ),
            ),
          ),
          // Settings button
          IconButton(
            icon: const Icon(Icons.settings_accessibility, size: 28),
            onPressed: _toggleAccessibilityPanel,
            tooltip: 'Accessibility Settings',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(strokeWidth: 6),
                  SizedBox(height: 20),
                  Text(
                    'Initializing accessibility services...',
                    style: TextStyle(fontSize: 18),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                // Google Map
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _currentPosition != null
                        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                        : const LatLng(37.7749, -122.4194),
                    zoom: 16.0,
                  ),
                  onMapCreated: (GoogleMapController controller) {
                    _mapController = controller;
                  },
                  onTap: _onMapTapped,
                  markers: _markers,
                  polylines: _polylines,
                  circles: _circles,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  zoomControlsEnabled: true,
                  compassEnabled: true,
                ),
                
                // Large Status indicators at top
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Card(
                    elevation: 8,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildLargeStatusIndicator(
                            icon: Icons.location_on,
                            label: 'GPS',
                            isActive: _permissionGranted,
                          ),
                          _buildLargeStatusIndicator(
                            icon: Icons.track_changes,
                            label: 'Tracking',
                            isActive: _isTracking,
                          ),
                          _buildLargeStatusIndicator(
                            icon: Icons.mic,
                            label: 'Voice',
                            isActive: _accessibilityService.isListening,
                          ),
                          _buildLargeStatusIndicator(
                            icon: Icons.route,
                            label: 'Route',
                            isActive: _routeDeviationEnabled,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                
                // Route settings panel
                if (_showRoutePanel)
                  Positioned(
                    bottom: 100,
                    left: 16,
                    right: 16,
                    child: Card(
                      elevation: 8,
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Route Deviation Settings',
                              style: Theme.of(context).textTheme.headlineSmall,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Max deviation: ${_maxDeviationDistance.toInt()}m',
                              style: const TextStyle(fontSize: 18),
                            ),
                            Slider(
                              value: _maxDeviationDistance,
                              min: 50,
                              max: 500,
                              divisions: 9,
                              label: '${_maxDeviationDistance.toInt()}m',
                              onChanged: (value) {
                                setState(() {
                                  _maxDeviationDistance = value;
                                });
                                _accessibilityService.speak('Deviation distance set to ${value.toInt()} meters');
                              },
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Route points: ${_expectedRoute.length}',
                              style: const TextStyle(fontSize: 18),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () {
                                      setState(() {
                                        _expectedRoute.clear();
                                        _routeDeviationEnabled = false;
                                        _markers.removeWhere((marker) => 
                                          marker.markerId.value.startsWith('route_point_'));
                                        _polylines.removeWhere((polyline) => 
                                          polyline.polylineId.value == 'expected_route');
                                      });
                                      _accessibilityService.speak('Route cleared. Tap on the map to set new route points.');
                                    },
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: const Size(0, 50),
                                      textStyle: const TextStyle(fontSize: 16),
                                    ),
                                    child: const Text('Clear Route'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _expectedRoute.length >= 2 ? _activateRouteDeviation : null,
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: const Size(0, 50),
                                      textStyle: const TextStyle(fontSize: 16),
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text('Activate'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                
                // Accessibility settings panel
                if (_showAccessibilityPanel)
                  Positioned(
                    bottom: 100,
                    left: 16,
                    right: 16,
                    child: Card(
                      elevation: 8,
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Accessibility Settings',
                              style: Theme.of(context).textTheme.headlineSmall,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 20),
                            
                            // Speech Rate
                            Text(
                              'Speech Rate: ${(_accessibilityService.speechRate * 100).toInt()}%',
                              style: const TextStyle(fontSize: 18),
                            ),
                            Slider(
                              value: _accessibilityService.speechRate,
                              min: 0.1,
                              max: 1.0,
                              divisions: 9,
                              onChanged: (value) {
                                _accessibilityService.setSpeechRate(value);
                                setState(() {});
                              },
                            ),
                            const SizedBox(height: 16),
                            
                            // Speech Volume
                            Text(
                              'Speech Volume: ${(_accessibilityService.speechVolume * 100).toInt()}%',
                              style: const TextStyle(fontSize: 18),
                            ),
                            Slider(
                              value: _accessibilityService.speechVolume,
                              min: 0.0,
                              max: 1.0,
                              divisions: 10,
                              onChanged: (value) {
                                _accessibilityService.setSpeechVolume(value);
                                setState(() {});
                              },
                            ),
                            const SizedBox(height: 16),
                            
                            // Voice Feedback Toggle
                            SwitchListTile(
                              title: const Text('Voice Feedback', style: TextStyle(fontSize: 18)),
                              value: _accessibilityService.voiceFeedbackEnabled,
                              onChanged: (value) {
                                _accessibilityService.setVoiceFeedbackEnabled(value);
                                setState(() {});
                              },
                            ),
                            
                            // Continuous Listening Toggle
                            SwitchListTile(
                              title: const Text('Continuous Voice Commands', style: TextStyle(fontSize: 18)),
                              value: _continuousListening,
                              onChanged: (value) {
                                setState(() {
                                  _continuousListening = value;
                                });
                                if (value) {
                                  _startContinuousListening();
                                  _accessibilityService.speak('Continuous voice commands enabled');
                                } else {
                                  _stopContinuousListening();
                                  _accessibilityService.speak('Continuous voice commands disabled');
                                }
                              },
                            ),
                            
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _announceHelp,
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size(0, 50),
                                textStyle: const TextStyle(fontSize: 16),
                              ),
                              child: const Text('Voice Commands Help'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
      
      // Large floating action buttons
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Emergency button - extra large and prominent
          SizedBox(
            width: 80,
            height: 80,
            child: FloatingActionButton(
              heroTag: "emergency",
              onPressed: _triggerEmergency,
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              child: const Icon(Icons.warning, size: 40),
            ),
          ),
          const SizedBox(height: 16),
          
          // Route settings button
          SizedBox(
            width: 70,
            height: 70,
            child: FloatingActionButton(
              heroTag: "route",
              onPressed: _toggleRoutePanel,
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              child: const Icon(Icons.route, size: 30),
            ),
          ),
          const SizedBox(height: 16),
          
          // Location refresh button
          SizedBox(
            width: 70,
            height: 70,
            child: FloatingActionButton(
              heroTag: "location",
              onPressed: _getCurrentLocation,
              backgroundColor: const Color(0xFF2561FA),
              foregroundColor: Colors.white,
              child: const Icon(Icons.my_location, size: 30),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLargeStatusIndicator({
    required IconData icon,
    required String label,
    required bool isActive,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          color: isActive ? Colors.green : Colors.grey,
          size: 32,
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isActive ? Colors.green : Colors.grey,
          ),
        ),
      ],
    );
  }
} 