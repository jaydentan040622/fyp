import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vibration/vibration.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

typedef VoiceCommandCallback = void Function(String command);

class AccessibilityService {
  static final AccessibilityService _instance = AccessibilityService._internal();
  factory AccessibilityService() => _instance;
  AccessibilityService._internal();

  // TTS and STT
  final FlutterTts _flutterTts = FlutterTts();
  final SpeechToText _speechToText = SpeechToText();
  
  // Sensors and Compass
  StreamSubscription<CompassEvent>? _compassSubscription;
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  
  // State variables
  bool _isInitialized = false;
  bool _voiceFeedbackEnabled = true;
  bool _isListening = false;
  bool _isSpeaking = false;
  double _speechRate = 0.5;
  double _speechVolume = 1.0;
  String _lastAnnouncement = '';
  VoiceCommandCallback? _voiceCommandCallback;
  
  // Navigation state
  double? _currentHeading;
  Position? _lastPosition;
  String _currentDirection = '';
  bool _isMoving = false;
  DateTime? _lastMovementTime;
  List<LatLng> _routeWaypoints = [];
  int _currentWaypointIndex = 0;
  
  // Location context
  String _currentLocationDescription = '';
  String _currentStreetName = '';
  List<String> _nearbyLandmarks = [];
  
  // Voice commands map
  final Map<String, String> _voiceCommands = {
    'emergency': 'emergency',
    'help': 'emergency', 
    'start tracking': 'start_tracking',
    'begin tracking': 'start_tracking',
    'stop tracking': 'stop_tracking',
    'end tracking': 'stop_tracking',
    'where am i': 'where_am_i',
    'where am i located': 'where_am_i',
    'what direction': 'what_direction',
    'which direction': 'what_direction',
    'repeat': 'repeat',
    'say again': 'repeat',
    'quiet': 'toggle_quiet',
    'silence': 'toggle_quiet',
    'speak': 'toggle_speak',
    'unmute': 'toggle_speak',
    'set route': 'set_route',
    'status': 'status',
    'current status': 'status',
  };

  // Getters
  bool get isInitialized => _isInitialized;
  bool get voiceFeedbackEnabled => _voiceFeedbackEnabled;
  bool get isListening => _isListening;
  bool get isSpeaking => _isSpeaking;
  double get speechRate => _speechRate;
  double get speechVolume => _speechVolume;
  String get currentDirection => _currentDirection;
  bool get isMoving => _isMoving;

  // Initialize the accessibility service
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Initialize TTS
      await _initializeTTS();
      
      // Initialize Speech Recognition
      await _initializeSpeechRecognition();
      
      // Initialize compass and sensors
      await _initializeCompass();
      _initializeMotionSensors();
      
      _isInitialized = true;
      await speak('Accessibility service initialized. Voice commands are now available.');
      
    } catch (e) {
      print('Error initializing accessibility service: $e');
      throw Exception('Failed to initialize accessibility service');
    }
  }

  // Initialize Text-to-Speech
  Future<void> _initializeTTS() async {
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(_speechRate);
    await _flutterTts.setVolume(_speechVolume);
    await _flutterTts.setPitch(1.0);
    
    _flutterTts.setStartHandler(() {
      _isSpeaking = true;
    });
    
    _flutterTts.setCompletionHandler(() {
      _isSpeaking = false;
    });
    
    _flutterTts.setErrorHandler((msg) {
      _isSpeaking = false;
      print('TTS Error: $msg');
    });
  }

  // Initialize Speech Recognition
  Future<void> _initializeSpeechRecognition() async {
    bool available = await _speechToText.initialize(
      onError: (error) {
        print('Speech recognition error: $error');
        _isListening = false;
      },
      onStatus: (status) {
        print('Speech recognition status: $status');
        if (status == 'done' || status == 'notListening') {
          _isListening = false;
        }
      },
    );
    
    if (!available) {
      throw Exception('Speech recognition not available');
    }
  }

  // Initialize compass
  Future<void> _initializeCompass() async {
    _compassSubscription = FlutterCompass.events?.listen((CompassEvent event) {
      if (event.heading != null) {
        _currentHeading = event.heading;
        _updateCurrentDirection(event.heading!);
      }
    });
  }

  // Initialize motion sensors
  void _initializeMotionSensors() {
    _accelerometerSubscription = accelerometerEventStream().listen((AccelerometerEvent event) {
      double magnitude = math.sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z
      );
      
      // Detect movement (threshold can be adjusted)
      bool wasMoving = _isMoving;
      _isMoving = magnitude > 1.2; // Gravity is ~9.8, so movement adds to this
      
      if (_isMoving) {
        _lastMovementTime = DateTime.now();
      } else if (wasMoving && !_isMoving) {
        // Just stopped moving
        Future.delayed(const Duration(seconds: 2), () {
          if (!_isMoving && DateTime.now().difference(_lastMovementTime ?? DateTime.now()).inSeconds > 3) {
            _announceStoppedMoving();
          }
        });
      }
    });
  }

  // Update current direction based on compass heading
  void _updateCurrentDirection(double heading) {
    String direction;
    if (heading >= 337.5 || heading < 22.5) {
      direction = 'North';
    } else if (heading >= 22.5 && heading < 67.5) {
      direction = 'Northeast';
    } else if (heading >= 67.5 && heading < 112.5) {
      direction = 'East';
    } else if (heading >= 112.5 && heading < 157.5) {
      direction = 'Southeast';
    } else if (heading >= 157.5 && heading < 202.5) {
      direction = 'South';
    } else if (heading >= 202.5 && heading < 247.5) {
      direction = 'Southwest';
    } else if (heading >= 247.5 && heading < 292.5) {
      direction = 'West';
    } else {
      direction = 'Northwest';
    }
    
    _currentDirection = direction;
  }

  // Speak text with priority control
  Future<void> speak(String text, {bool priority = false}) async {
    if (!_voiceFeedbackEnabled || text.isEmpty) return;
    
    try {
      _lastAnnouncement = text;
      
      if (priority && _isSpeaking) {
        await _flutterTts.stop();
      }
      
      if (!_isSpeaking || priority) {
        await _flutterTts.speak(text);
        
        // Add vibration for important announcements
        if (priority) {
          _vibrate(pattern: [100, 200, 100]);
        }
      }
    } catch (e) {
      print('Error speaking: $e');
    }
  }

  // Start listening for voice commands
  Future<void> startListening() async {
    if (!_isInitialized || _isListening) {
      print('Cannot start listening. Initialized: $_isInitialized, Already listening: $_isListening');
      return;
    }
    
    try {
      print('⭐ Starting speech recognition...');
      // Use default ListenMode and enable partialResults for better responsiveness
      _isListening = await _speechToText.listen(
        onResult: _onSpeechResult,
        listenFor: const Duration(seconds: 10), // Shorter duration for responsiveness
        pauseFor: const Duration(seconds: 1), // Shorter pause for responsiveness
        partialResults: true, // Enable partial results
        localeId: 'en_US', // Explicitly set locale
        listenMode: ListenMode.dictation, // Use dictation mode for continuous input
      );
      
      print('⭐ Listening started successfully: $_isListening');
      
      if (_isListening) {
        _vibrate(pattern: [50]);
        speak('Listening for commands', priority: false);
      } else {
        print('⚠️ Failed to start listening');
      }
    } catch (e) {
      print('⚠️ Error starting speech recognition: $e');
    }
  }

  // Handle speech recognition results
  void _onSpeechResult(result) {
    String command = result.recognizedWords.toLowerCase().trim();
    double confidence = result.hasConfidenceRating ? result.confidence : 0.0;
    
    print('🎤 Speech recognition result: "$command" with confidence ${(confidence * 100).toStringAsFixed(1)}%');
    
    // Accept any command with words, even with low confidence
    if (command.isNotEmpty) {
      _processVoiceCommand(command);
    }
  }

  // Process voice commands
  void _processVoiceCommand(String command) {
    print('🔍 Processing voice command: "$command"');
    String? mappedCommand;
    
    // Find matching command with more flexible matching
    for (String key in _voiceCommands.keys) {
      // Check if the command contains the key phrase or is very similar
      if (command.contains(key) || 
          _calculateSimilarity(command, key) > 0.7) {
        mappedCommand = _voiceCommands[key];
        print('✅ Command matched: "$command" → "${_voiceCommands[key]}"');
        break;
      }
    }
    
    // Direct matching for emergency commands (higher priority)
    if (command.contains('emergency') || command.contains('help') || command == 'sos') {
      mappedCommand = 'emergency';
      print('🚨 Emergency command detected');
    }
    
    // Direct matching for tracking commands (higher priority)
    if (command.contains('start track') || command.contains('begin track')) {
      mappedCommand = 'start_tracking';
      print('▶️ Start tracking command detected');
    }
    
    if (command.contains('stop track') || command.contains('end track')) {
      mappedCommand = 'stop_tracking';
      print('⏹️ Stop tracking command detected');
    }
    
    if (mappedCommand != null) {
      _handleCommand(mappedCommand);
    } else {
      print('❌ No matching command found for: "$command"');
      speak('Command not recognized. Say "help" for available commands.');
    }
  }
  
  // Simple string similarity calculation using Levenshtein distance
  double _calculateSimilarity(String s1, String s2) {
    if (s1.isEmpty || s2.isEmpty) return 0.0;
    if (s1 == s2) return 1.0;
    
    int maxLen = math.max(s1.length, s2.length);
    if (maxLen == 0) return 1.0;
    
    // Simple matching - determine how many characters match
    int matchingChars = 0;
    for (int i = 0; i < math.min(s1.length, s2.length); i++) {
      if (s1[i] == s2[i]) matchingChars++;
    }
    
    return matchingChars / maxLen;
  }

  // Handle specific commands
  void _handleCommand(String command) {
    switch (command) {
      case 'where_am_i':
        _announceCurrentLocation();
        break;
      case 'what_direction':
        _announceCurrentDirection();
        break;
      case 'repeat':
        if (_lastAnnouncement.isNotEmpty) {
          speak(_lastAnnouncement);
        } else {
          speak('No previous announcement to repeat.');
        }
        break;
      case 'toggle_quiet':
        _voiceFeedbackEnabled = false;
        speak('Voice feedback disabled.');
        break;
      case 'toggle_speak':
        _voiceFeedbackEnabled = true;
        speak('Voice feedback enabled.');
        break;
      case 'status':
        _announceStatus();
        break;
      default:
        // Pass other commands to the callback
        _voiceCommandCallback?.call(command);
        break;
    }
  }

  // Announce current location with details
  Future<void> _announceCurrentLocation() async {
    if (_lastPosition == null) {
      await speak('Current location not available.');
      return;
    }
    
    String announcement = '';
    
    if (_currentStreetName.isNotEmpty) {
      announcement += 'You are on $_currentStreetName. ';
    }
    
    if (_currentDirection.isNotEmpty) {
      announcement += 'Facing $_currentDirection. ';
    }
    
    if (_nearbyLandmarks.isNotEmpty) {
      announcement += 'Nearby landmarks: ${_nearbyLandmarks.take(2).join(', ')}. ';
    }
    
    if (announcement.isEmpty) {
      announcement = 'You are at latitude ${_lastPosition!.latitude.toStringAsFixed(6)}, longitude ${_lastPosition!.longitude.toStringAsFixed(6)}.';
    }
    
    await speak(announcement, priority: true);
  }

  // Announce current compass direction
  Future<void> _announceCurrentDirection() async {
    if (_currentDirection.isNotEmpty) {
      await speak('You are facing $_currentDirection.', priority: true);
    } else {
      await speak('Direction information not available.');
    }
  }

  // Announce current status
  Future<void> _announceStatus() async {
    String status = 'Current status: ';
    status += _isMoving ? 'Moving. ' : 'Stationary. ';
    status += _currentDirection.isNotEmpty ? 'Facing $_currentDirection. ' : '';
    
    await speak(status);
  }

  // Update location and get contextual information
  Future<void> updateNavigationProgress(Position position) async {
    _lastPosition = position;
    
    // Get location description
    await _updateLocationContext(position);
    
    // Check waypoint progress if route is active
    if (_routeWaypoints.isNotEmpty) {
      _checkWaypointProgress(position);
    }
  }

  // Update location context with street names and landmarks
  Future<void> _updateLocationContext(Position position) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude, 
        position.longitude
      );
      
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;
        
        String newStreetName = '';
        if (place.street?.isNotEmpty == true) {
          newStreetName = place.street!;
        } else if (place.thoroughfare?.isNotEmpty == true) {
          newStreetName = place.thoroughfare!;
        }
        
        // Announce street change
        if (newStreetName != _currentStreetName && newStreetName.isNotEmpty) {
          _currentStreetName = newStreetName;
          if (_isMoving) {
            await speak('Now on $_currentStreetName');
          }
        }
        
        // Update location description
        _currentLocationDescription = _buildLocationDescription(place);
      }
    } catch (e) {
      print('Error updating location context: $e');
    }
  }

  // Build detailed location description
  String _buildLocationDescription(Placemark place) {
    List<String> parts = [];
    
    if (place.street?.isNotEmpty == true) parts.add(place.street!);
    if (place.locality?.isNotEmpty == true) parts.add(place.locality!);
    if (place.administrativeArea?.isNotEmpty == true) parts.add(place.administrativeArea!);
    
    return parts.join(', ');
  }

  // Check waypoint progress for route navigation
  void _checkWaypointProgress(Position position) {
    if (_currentWaypointIndex >= _routeWaypoints.length) return;
    
    LatLng currentWaypoint = _routeWaypoints[_currentWaypointIndex];
    double distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      currentWaypoint.latitude,
      currentWaypoint.longitude,
    );
    
    if (distance < 20) { // Within 20 meters of waypoint
      _currentWaypointIndex++;
      
      if (_currentWaypointIndex < _routeWaypoints.length) {
        _announceNextWaypoint();
      } else {
        speak('You have reached your destination.', priority: true);
        _vibrate(pattern: [200, 100, 200, 100, 200]);
      }
    } else if (distance < 50) { // Approaching waypoint
      speak('Approaching waypoint ${_currentWaypointIndex + 1}. ${distance.toInt()} meters ahead.');
    }
  }

  // Announce next waypoint
  void _announceNextWaypoint() {
    if (_currentWaypointIndex < _routeWaypoints.length) {
      speak('Waypoint ${_currentWaypointIndex} reached. Continuing to waypoint ${_currentWaypointIndex + 1}.', priority: true);
      _vibrate(pattern: [100, 50, 100]);
    }
  }

  // Announce when user stops moving
  void _announceStoppedMoving() {
    if (_voiceFeedbackEnabled) {
      speak('You have stopped moving.');
    }
  }

  // Announce location updates
  Future<void> announceLocationUpdate(Position position) async {
    await _updateLocationContext(position);
    
    String announcement = 'Location updated. ';
    
    if (_currentStreetName.isNotEmpty) {
      announcement += 'On $_currentStreetName. ';
    }
    
    if (_currentDirection.isNotEmpty) {
      announcement += 'Facing $_currentDirection. ';
    }
    
    if (position.speed > 0.5) { // Moving faster than 0.5 m/s
      announcement += 'Speed: ${(position.speed * 3.6).toStringAsFixed(1)} kilometers per hour.';
    }
    
    await speak(announcement);
  }

  // Announce route deviation
  Future<void> announceRouteDeviation(double deviationDistance) async {
    await speak(
      'Route deviation alert! You are ${deviationDistance.toInt()} meters off your planned route. '
      'Consider returning to your original path.',
      priority: true
    );
    
    // Strong vibration pattern for route deviation
    _vibrate(pattern: [300, 200, 300, 200, 300]);
  }

  // Announce emergency activation
  Future<void> announceEmergency() async {
    await speak(
      'Emergency alert activated! Your caregivers have been notified of your location. '
      'Emergency services can be reached by saying "call emergency".',
      priority: true
    );
    
    // Emergency vibration pattern
    _vibrate(pattern: [500, 100, 500, 100, 500]);
  }

  // Announce navigation start
  Future<void> announceNavigationStart(List<LatLng> route) async {
    _routeWaypoints = List.from(route);
    _currentWaypointIndex = 0;
    
    await speak(
      'Navigation started with ${route.length} waypoints. '
      'You will receive audio guidance as you progress along your route.',
      priority: true
    );
  }

  // Vibration helper
  void _vibrate({List<int>? pattern}) {
    if (pattern != null) {
      Vibration.vibrate(pattern: pattern);
    } else {
      Vibration.vibrate(duration: 100);
    }
  }

  // Set voice command callback
  void setVoiceCommandCallback(VoiceCommandCallback callback) {
    _voiceCommandCallback = callback;
  }

  // Settings methods
  Future<void> setSpeechRate(double rate) async {
    _speechRate = rate.clamp(0.1, 1.0);
    await _flutterTts.setSpeechRate(_speechRate);
  }

  Future<void> setSpeechVolume(double volume) async {
    _speechVolume = volume.clamp(0.0, 1.0);
    await _flutterTts.setVolume(_speechVolume);
  }

  void setVoiceFeedbackEnabled(bool enabled) {
    _voiceFeedbackEnabled = enabled;
    if (enabled) {
      speak('Voice feedback enabled.');
    }
  }

  // Stop listening
  Future<void> stopListening() async {
    if (_isListening) {
      await _speechToText.stop();
      _isListening = false;
    }
  }

  // Dispose resources
  void dispose() {
    _compassSubscription?.cancel();
    _accelerometerSubscription?.cancel();
    _flutterTts.stop();
    _speechToText.stop();
    _isInitialized = false;
  }
} 