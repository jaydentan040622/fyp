
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';

enum GestureType {
  swipeLeft,
  swipeRight,
  swipeUp,
  downwardLine,
  unknown
}

class GesturePoint {
  final double x;
  final double y;
  final DateTime timestamp;

  GesturePoint(this.x, this.y, this.timestamp);
}

class GestureRecognitionService {
  static final GestureRecognitionService _instance = GestureRecognitionService._internal();
  factory GestureRecognitionService() => _instance;
  GestureRecognitionService._internal();

  final FlutterTts _flutterTts = FlutterTts();
  final List<GesturePoint> _gesturePoints = [];
  bool _isInitialized = false;
  bool _isRecording = false;
  
  // Gesture detection parameters
  static const double _minSwipeDistance = 100.0;
  static const double _maxSwipeVerticalDeviation = 50.0;
  static const double _minDownwardLineDistance = 80.0;
  static const double _maxDownwardLineHorizontalDeviation = 30.0;
  static const double _minUpwardSwipeDistance = 100.0;
  static const double _maxUpwardSwipeHorizontalDeviation = 50.0;
  
  // Callbacks
  Function(GestureType)? _onGestureDetected;
  Function(String)? _onDebugMessage;

  // Initialize the service
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      await _flutterTts.setLanguage('en-US');
      await _flutterTts.setSpeechRate(0.6);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      
      _isInitialized = true;
      debugPrint('GestureRecognitionService initialized successfully');
    } catch (e) {
      debugPrint('Error initializing GestureRecognitionService: $e');
      throw Exception('Failed to initialize gesture recognition service');
    }
  }

  // Set gesture detection callback
  void setGestureCallback(Function(GestureType) callback) {
    _onGestureDetected = callback;
  }

  // Set debug message callback
  void setDebugCallback(Function(String) callback) {
    _onDebugMessage = callback;
  }

  // Start recording a gesture
  void startGesture(Offset position) {
    _isRecording = true;
    _gesturePoints.clear();
    _addGesturePoint(position);
    _debugPrint('Started recording gesture at (${position.dx.toStringAsFixed(1)}, ${position.dy.toStringAsFixed(1)})');
  }

  // Update gesture with new point
  void updateGesture(Offset position) {
    if (!_isRecording) return;
    _addGesturePoint(position);
  }

  // End gesture recording and analyze
  void endGesture() {
    if (!_isRecording) return;
    _isRecording = false;
    
    if (_gesturePoints.length < 2) {
      _debugPrint('Gesture too short, ignoring');
      return;
    }

    GestureType detectedGesture = _analyzeGesture();
    _debugPrint('Gesture analysis complete: ${detectedGesture.toString()}');
    
    if (detectedGesture != GestureType.unknown) {
      _triggerHapticFeedback(detectedGesture);
      _announceGesture(detectedGesture);
      _onGestureDetected?.call(detectedGesture);
    }
    
    _gesturePoints.clear();
  }

  // Add a point to the current gesture
  void _addGesturePoint(Offset position) {
    _gesturePoints.add(GesturePoint(position.dx, position.dy, DateTime.now()));
  }

  // Analyze the recorded gesture
  GestureType _analyzeGesture() {
    if (_gesturePoints.length < 2) return GestureType.unknown;

    // Check for swipe gestures first (including upward swipe)
    GestureType swipeResult = _detectSwipe();
    if (swipeResult != GestureType.unknown) return swipeResult;

    // Check for downward line
    GestureType lineResult = _detectDownwardLine();
    if (lineResult != GestureType.unknown) return lineResult;

    return GestureType.unknown;
  }

  // Detect swipe gestures (left/right/up)
  GestureType _detectSwipe() {
    if (_gesturePoints.length < 2) return GestureType.unknown;

    double startX = _gesturePoints.first.x;
    double endX = _gesturePoints.last.x;
    double startY = _gesturePoints.first.y;
    double endY = _gesturePoints.last.y;

    double horizontalDistance = (endX - startX).abs();
    double verticalDistance = (endY - startY).abs();

    // Check for horizontal swipe (left/right)
    if (horizontalDistance >= _minSwipeDistance && 
        verticalDistance <= _maxSwipeVerticalDeviation) {
      
      if (endX > startX) {
        return GestureType.swipeRight;
      } else {
        return GestureType.swipeLeft;
      }
    }

    // Check for upward swipe
    if (verticalDistance >= _minUpwardSwipeDistance && 
        horizontalDistance <= _maxUpwardSwipeHorizontalDeviation) {
      
      if (endY < startY) { // Negative means upward
        return GestureType.swipeUp;
      }
    }

    return GestureType.unknown;
  }

  // Detect downward line gesture
  GestureType _detectDownwardLine() {
    if (_gesturePoints.length < 2) return GestureType.unknown;

    double startX = _gesturePoints.first.x;
    double endX = _gesturePoints.last.x;
    double startY = _gesturePoints.first.y;
    double endY = _gesturePoints.last.y;

    double horizontalDistance = (endX - startX).abs();
    double verticalDistance = endY - startY; // Positive means downward

    // Check if downward movement is significant and horizontal is minimal
    if (verticalDistance >= _minDownwardLineDistance && 
        horizontalDistance <= _maxDownwardLineHorizontalDeviation) {
      return GestureType.downwardLine;
    }

    return GestureType.unknown;
  }



  // Trigger haptic feedback based on gesture type
  void _triggerHapticFeedback(GestureType gestureType) {
    switch (gestureType) {
      case GestureType.swipeLeft:
      case GestureType.swipeRight:
        Vibration.vibrate(duration: 100);
        break;
      case GestureType.swipeUp:
        Vibration.vibrate(pattern: [50, 50, 50, 50, 50]);
        break;
      case GestureType.downwardLine:
        Vibration.vibrate(pattern: [100, 50, 100]);
        break;
      default:
        break;
    }
  }

  // Announce gesture detection
  void _announceGesture(GestureType gestureType) {
    String message = '';
    switch (gestureType) {
      case GestureType.swipeLeft:
        message = 'Swipe left detected';
        break;
      case GestureType.swipeRight:
        message = 'Swipe right detected';
        break;
      case GestureType.swipeUp:
        message = 'Swipe up detected';
        break;
      case GestureType.downwardLine:
        message = 'Downward line detected';
        break;
      default:
        return;
    }
    
    speak(message);
  }

  // Speak text
  Future<void> speak(String text) async {
    if (!_isInitialized) return;
    try {
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint('Error speaking: $e');
    }
  }

  // Announce current page
  Future<void> announceCurrentPage(String pageName) async {
    await speak('Current page: $pageName');
  }

  // Debug print helper
  void _debugPrint(String message) {
    debugPrint('GestureRecognition: $message');
    _onDebugMessage?.call(message);
  }

  // Dispose resources
  void dispose() {
    _flutterTts.stop();
    _gesturePoints.clear();
    _isInitialized = false;
    _isRecording = false;
  }
} 