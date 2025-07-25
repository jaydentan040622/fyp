import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'dart:math';

enum GestureType {
  swipeLeft,
  swipeRight,
  swipeUp,
  downwardLine,
  circleGesture,
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

  // Global announcement management
  static String? _currentActivePageId;
  static bool _isAnnouncementActive = false;

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
    
    // Check for circle gesture
    GestureType circleResult = _detectCircle();
    if (circleResult != GestureType.unknown) return circleResult;

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

  // Detect circle gesture
  GestureType _detectCircle() {
    // Need at least a certain number of points for a meaningful circle
    if (_gesturePoints.length < 10) return GestureType.unknown;
    
    // Calculate center of mass of all points
    double sumX = 0;
    double sumY = 0;
    for (var point in _gesturePoints) {
      sumX += point.x;
      sumY += point.y;
    }
    double centerX = sumX / _gesturePoints.length;
    double centerY = sumY / _gesturePoints.length;
    
    // Calculate average distance from center (expected radius)
    double totalRadius = 0;
    for (var point in _gesturePoints) {
      totalRadius += _distance(point.x, point.y, centerX, centerY);
    }
    double avgRadius = totalRadius / _gesturePoints.length;
    
    // Check if all points are roughly the same distance from the center (within tolerance)
    const radiusTolerance = 0.5; // 50% tolerance
    int pointsWithinTolerance = 0;
    
    for (var point in _gesturePoints) {
      double pointRadius = _distance(point.x, point.y, centerX, centerY);
      double relativeDifference = (pointRadius - avgRadius).abs() / avgRadius;
      
      if (relativeDifference < radiusTolerance) {
        pointsWithinTolerance++;
      }
    }
    
    // Calculate angle coverage to ensure we have something close to a full circle
    double angleStart = 0;
    double angleEnd = 0;
    bool angleInitialized = false;
    
    // Track minimum and maximum angles to check if we've covered a good portion of a circle
    for (var point in _gesturePoints) {
      double dx = point.x - centerX;
      double dy = point.y - centerY;
      double angle = (atan2(dy, dx) * 180 / pi + 360) % 360; // 0-360 range
      
      if (!angleInitialized) {
        angleStart = angle;
        angleEnd = angle;
        angleInitialized = true;
      } else {
        if ((angle - angleStart + 360) % 360 < (angleEnd - angleStart + 360) % 360) {
          angleStart = angle;
        }
        if ((angle - angleStart + 360) % 360 > (angleEnd - angleStart + 360) % 360) {
          angleEnd = angle;
        }
      }
    }
    
    double angleCoverage = (angleEnd - angleStart + 360) % 360;
    
    // Points within tolerance threshold and minimum angle coverage required for circle detection
    double pointsRatio = pointsWithinTolerance / _gesturePoints.length;
    const minAngleCoverage = 270.0; // At least 3/4 of a circle
    const minPointsRatio = 0.7;   // At least 70% of points should be on the circle path
    
    if (pointsRatio >= minPointsRatio && angleCoverage >= minAngleCoverage) {
      return GestureType.circleGesture;
    }
    
    return GestureType.unknown;
  }
  
  // Helper method to calculate distance between two points
  double _distance(double x1, double y1, double x2, double y2) {
    return sqrt(pow(x2 - x1, 2) + pow(y2 - y1, 2));
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
      case GestureType.circleGesture:
        Vibration.vibrate(pattern: [50, 50, 50, 100, 50, 100]);
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
      case GestureType.circleGesture:
        message = 'Circle gesture detected';
        break;
      default:
        return;
    }

    speak(message);
  }

  // Global announcement management methods
  bool setActiveAnnouncementSource(String pageId) {
    if (_isAnnouncementActive && _currentActivePageId != pageId) {
      // Another page is already making announcements
      return false;
    }
    _currentActivePageId = pageId;
    _isAnnouncementActive = true;
    return true;
  }

  void clearActiveAnnouncementSource(String pageId) {
    if (_currentActivePageId == pageId) {
      _currentActivePageId = null;
      _isAnnouncementActive = false;
      
      // Also stop any ongoing speech
      if (_isSpeaking) {
        _flutterTts.stop();
        _isSpeaking = false;
      }
    }
  }

  bool canMakeAnnouncements(String pageId) {
    return !_isAnnouncementActive || _currentActivePageId == pageId;
  }

  void stopAllAnnouncements() {
    _flutterTts.stop();
    _currentActivePageId = null;
    _isAnnouncementActive = false;
    _isSpeaking = false;
  }

  // Speak text
  Future<void> speak(String text, {String? pageId}) async {
    if (!_isInitialized) return;
    
    // Check if this page can speak
    if (pageId != null && !canMakeAnnouncements(pageId)) {
      _debugPrint('Speech blocked: another page ($_currentActivePageId) is active');
      return;
    }
    
    // If there's an ongoing announcement, wait for it to finish or stop it
    if (_isSpeaking) {
      await _flutterTts.stop();
      await Future.delayed(const Duration(milliseconds: 100));
    }
    
    try {
      // Update state before speaking
      if (pageId != null) {
        _currentActivePageId = pageId;
        _isAnnouncementActive = true;
      }
      
      _isSpeaking = true;
      _debugPrint('Speaking: $text');
      await _flutterTts.speak(text);
      
      // Note: we don't set _isSpeaking = false here because we now have a completion handler
    } catch (e) {
      _isSpeaking = false;
      _isAnnouncementActive = false;
      _debugPrint('Error speaking: $e');
    }
  }

  // Announce current page (for announcements that respect the active page)
  Future<void> announceCurrentPage(String pageName, {String? pageId}) async {
    if (pageId != null && !canMakeAnnouncements(pageId)) {
      _debugPrint('Page announcement blocked: another page is active');
      return; // Another page is making announcements
    }
    
    // Ensure we set this page as the active announcement source
    if (pageId != null) {
      setActiveAnnouncementSource(pageId);
    }
    
    await speak('Current page: $pageName', pageId: pageId);
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
    _isSpeaking = false;
  }
} 