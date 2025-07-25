import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'accessibility_service.dart';
import '../gesture_recognition_service.dart';

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
  Timer? _locationUpdateTimer;
  Timer? _periodicAnnouncementTimer;
  
  // User Data
  String? _currentUserId;
  List<String> _caregiverIds = [];
  
  // UI States
  bool _isLoading = true;
  bool _emergencyMode = false;
  bool _showAccessibilityPanel = false;
  
  // Accessibility Service
  final AccessibilityService _accessibilityService = AccessibilityService();
  bool _accessibilityInitialized = false;
  
  // Voice Command States
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  String _lastWords = '';
  Timer? _voiceListeningTimer;
  bool _isListening = false;

  // Gesture Recognition
  final GestureRecognitionService _gestureService = GestureRecognitionService();
  final String _pageId = 'live_location_tracking_page';
  bool _gesturesEnabled = true;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeEverything();
    _initializeGestureService();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionStream?.cancel();
    _locationUpdateTimer?.cancel();
    _periodicAnnouncementTimer?.cancel();
    _voiceListeningTimer?.cancel();
    _accessibilityService.dispose();
    _gestureService.clearActiveAnnouncementSource(_pageId);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startListeningIfNeeded();
    } else if (state == AppLifecycleState.paused) {
      _stopListening();
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
      
      // Initialize speech recognition
      await _initializeSpeech();
      
      // Request permissions
      await _requestPermissions();
      
      // Get initial location
      await _getCurrentLocation();
      
      // Start periodic announcements
      _startPeriodicAnnouncements();
      
      // Start listening for voice commands
      _startListeningIfNeeded();
      
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        
        // Welcome message
        await _accessibilityService.speak(
          'Live location tracking loaded. You can now use voice commands. Say "Where am I" for your location, "Help" for emergency, or "Start" and "Stop" to control location sharing. Gesture controls are also available: swipe left to go back, swipe right for home, swipe up to start tracking, swipe down to stop tracking, draw a circle for emergency, and double-tap to cancel emergency.',
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

  Future<void> _initializeSpeech() async {
    try {
      _speechEnabled = await _speechToText.initialize();
      if (_speechEnabled) {
        print('✅ Speech recognition initialized successfully');
      } else {
        print('❌ Speech recognition failed to initialize');
      }
    } catch (e) {
      print('❌ Error initializing speech recognition: $e');
      _speechEnabled = false;
    }
  }
  
  void _startListeningIfNeeded() {
    if (!_isListening && _speechEnabled) {
      _startListening();
      
      // Set up timer to restart listening periodically
      _voiceListeningTimer?.cancel();
      _voiceListeningTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
        if (!_isListening && _speechEnabled) {
          _startListening();
        }
      });
    }
  }
  
  void _startListening() {
    if (!_speechEnabled) return;
    
    try {
      _speechToText.listen(
        onResult: _onSpeechResult,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        onSoundLevelChange: (level) {
          // Optional: Show visual feedback of sound level
        },
        cancelOnError: false,
        listenMode: ListenMode.confirmation,
      );
      
      setState(() {
        _isListening = true;
      });
      
      print('🎤 Started listening for voice commands...');
    } catch (e) {
      print('❌ Error starting speech recognition: $e');
      setState(() {
        _isListening = false;
      });
      
      // Try again after a short delay
      Future.delayed(const Duration(seconds: 2), () {
        _startListeningIfNeeded();
      });
    }
  }
  
  void _stopListening() {
    _speechToText.stop();
    setState(() {
      _isListening = false;
    });
    _voiceListeningTimer?.cancel();
    print('🛑 Stopped listening for voice commands.');
  }
  
  void _onSpeechResult(SpeechRecognitionResult result) {
    setState(() {
      _lastWords = result.recognizedWords.toLowerCase();
      print('🔊 Speech recognized: $_lastWords');
    });
    
    if (result.finalResult) {
      _handleVoiceCommand(_lastWords);
      
      // Restart listening after processing the command
      Future.delayed(const Duration(milliseconds: 1000), () {
        _startListeningIfNeeded();
      });
    }
  }
  
  void _handleVoiceCommand(String command) {
    print('🎯 Processing voice command: "$command"');
    
    // Show visual feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Voice command: $command'),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 2),
      ),
    );
    
    if (command.contains('where am i')) {
      _announceCurrentLocation();
    } else if (command.contains('help') || command.contains('emergency')) {
      _triggerEmergency();
    } else if (command.contains('start')) {
      _startLiveTracking();
    } else if (command.contains('stop')) {
      _stopLiveTracking();
    } else {
      // Unrecognized command
      _accessibilityService.speak(
        'Command not recognized. Please try again. Say "Where am I", "Help", "Start" or "Stop".',
        priority: false
      );
    }
  }
  
  void _announceCurrentLocation() async {
    if (_currentPosition == null) {
      _accessibilityService.speak('Getting your current location...', priority: true);
      await _getCurrentLocation();
    }
    
    if (_currentPosition != null) {
      // Get address information if available
      String locationMessage = 'Your current location is: Latitude ${_currentPosition!.latitude.toStringAsFixed(6)} and Longitude ${_currentPosition!.longitude.toStringAsFixed(6)}';
      _accessibilityService.speak(locationMessage, priority: true);
    } else {
      _accessibilityService.speak('Unable to determine your current location. Please check your GPS settings.', priority: true);
    }
  }

  Future<void> _initializeAccessibilityService() async {
    try {
      print('🔄 Initializing accessibility services...');
      await _accessibilityService.initialize();
      
      // Wait a moment for the initialization to complete properly
      await Future.delayed(const Duration(milliseconds: 500));
      
      _accessibilityInitialized = true;
      print('✅ Accessibility services initialized successfully');
      
      // Show a notification to indicate it's working
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Accessibility features activated!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );
      
    } catch (e) {
      print('❌ Failed to initialize accessibility service: $e');
      _showErrorSnackBar('Accessibility features may not work properly. Please restart the app.');
    }
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
        var micStatus = await Permission.microphone.request();
        if (micStatus.isGranted) {
          await _accessibilityService.speak('Microphone permission granted for voice commands.');
        } else {
          await _accessibilityService.speak('Microphone permission denied. Voice commands will not work.');
        }
        
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

  void _cancelEmergency() {
    setState(() {
      _emergencyMode = false;
    });
    
    if (_currentUserId != null) {
      try {
        // Update Firebase to indicate emergency has been cancelled
        FirebaseFirestore.instance
            .collection('emergencyAlerts')
            .where('userId', isEqualTo: _currentUserId)
            .where('isActive', isEqualTo: true)
            .get()
            .then((snapshot) {
              for (var doc in snapshot.docs) {
                doc.reference.update({'isActive': false});
              }
            });
        
        // Close any emergency dialogs
        Navigator.of(context).popUntil((route) {
          return route.settings.name != 'emergency_dialog';
        });
        
        _accessibilityService.speak('Emergency cancelled', priority: true);
        _showSuccessSnackBar('Emergency cancelled');
      } catch (e) {
        print('❌ Error cancelling emergency: $e');
      }
    }
  }

  void _showEmergencyDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      routeSettings: const RouteSettings(name: 'emergency_dialog'),
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
              const SizedBox(height: 10),
              const Text(
                'Double tap anywhere on screen to cancel emergency',
                style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
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
                _cancelEmergency();
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

  void _announceCurrentStatus() {
    String status = 'Current status: ';
    status += _permissionGranted ? 'GPS enabled. ' : 'GPS disabled. ';
    status += _isTracking ? 'Tracking active. ' : 'Tracking inactive. ';
    status += _speechEnabled ? 'Voice commands active. ' : 'Voice commands disabled. ';
    status += _gesturesEnabled ? 'Gesture controls active. ' : 'Gesture controls disabled. ';
    
    if (_caregiverIds.isNotEmpty) {
      status += '${_caregiverIds.length} caregiver${_caregiverIds.length > 1 ? 's' : ''} connected.';
    } else {
      status += 'No caregivers connected.';
    }
    
    _accessibilityService.speak(status, priority: true);
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

  // Initialize gesture recognition service
  Future<void> _initializeGestureService() async {
    try {
      await _gestureService.initialize();
      _gestureService.setGestureCallback(_handleGesture);
      print('✅ Gesture service initialized successfully');
    } catch (e) {
      print('❌ Failed to initialize gesture service: $e');
    }
  }
  
  // Handle detected gestures
  void _handleGesture(GestureType gestureType) {
    if (!_gesturesEnabled) return;
    
    print('🖐️ Gesture detected: $gestureType');
    
    switch (gestureType) {
      case GestureType.swipeLeft:
        _navigateToNavigationPage();
        break;
      case GestureType.swipeRight:
        _navigateToHomePage();
        break;
      case GestureType.swipeUp:
        if (!_isTracking) {
          _startLiveTracking();
        }
        break;
      case GestureType.downwardLine:
        if (_isTracking) {
          _stopLiveTracking();
        }
        break;
      case GestureType.circleGesture:
        _triggerEmergency();
        break;
      default:
        break;
    }
  }
  
  // Navigation methods for gestures
  void _navigateToNavigationPage() {
    _gestureService.speak('Going back to navigation page');
    Navigator.pop(context);
  }
  
  void _navigateToHomePage() {
    _gestureService.speak('Going to home page');
    Navigator.popUntil(context, (route) => route.isFirst);
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
          : GestureDetector(
              onPanStart: (details) {
                if (_gesturesEnabled) {
                  _gestureService.startGesture(details.localPosition);
                }
              },
              onPanUpdate: (details) {
                if (_gesturesEnabled) {
                  _gestureService.updateGesture(details.localPosition);
                }
              },
              onPanEnd: (_) {
                if (_gesturesEnabled) {
                  _gestureService.endGesture();
                }
              },
              onDoubleTap: () {
                // Cancel emergency if active
                if (_emergencyMode) {
                  _cancelEmergency();
                }
              },
              child: Stack(
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
                              isActive: _isListening,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  
                  // Voice command indicator
                  if (_isListening)
                    Positioned(
                      top: 100,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.mic, color: Colors.white),
                              SizedBox(width: 8),
                              Text(
                                'Listening...',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
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
                              
                              // Voice Commands Toggle
                              SwitchListTile(
                                title: const Text('Voice Commands', style: TextStyle(fontSize: 18)),
                                value: _speechEnabled,
                                onChanged: (value) {
                                  if (value) {
                                    _initializeSpeech().then((_) {
                                      _startListeningIfNeeded();
                                    });
                                  } else {
                                    _stopListening();
                                    setState(() {
                                      _speechEnabled = false;
                                    });
                                  }
                                },
                              ),
                              
                              // Gesture Recognition Toggle
                              SwitchListTile(
                                title: const Text('Gesture Controls', style: TextStyle(fontSize: 18)),
                                subtitle: const Text('Swipe left: back, right: home, up: start tracking, down: stop tracking, circle: emergency, double-tap: cancel emergency'),
                                value: _gesturesEnabled,
                                onChanged: (value) {
                                  setState(() {
                                    _gesturesEnabled = value;
                                  });
                                  _accessibilityService.speak(
                                    value ? 'Gesture controls enabled' : 'Gesture controls disabled',
                                    priority: false
                                  );
                                },
                              ),
                              
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () {
                                  _accessibilityService.speak(
                                    'Available voice commands: Say "Where am I" to hear your current location. '
                                    'Say "Help" for emergency assistance. '
                                    'Say "Start" to begin location sharing. '
                                    'Say "Stop" to stop location sharing.',
                                    priority: true
                                  );
                                },
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
          
          const SizedBox(height: 16),
          
          // Voice command button
          SizedBox(
            width: 70,
            height: 70,
            child: FloatingActionButton(
              heroTag: "voice",
              onPressed: _isListening ? _stopListening : _startListeningIfNeeded,
              backgroundColor: _isListening ? Colors.green : Colors.blue,
              foregroundColor: Colors.white,
              child: Icon(_isListening ? Icons.mic : Icons.mic_none, size: 30),
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