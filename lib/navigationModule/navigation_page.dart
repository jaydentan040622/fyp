import 'dart:async';
import 'package:flutter/material.dart';
import '../gesture_recognition_service.dart';
import 'live_location_tracking_page.dart';
import 'transportation_page.dart';

class NavigationPage extends StatefulWidget {
  const NavigationPage({super.key});

  @override
  State<NavigationPage> createState() => _NavigationPageState();
}

class _NavigationPageState extends State<NavigationPage> {
  final GestureRecognitionService _gestureService = GestureRecognitionService();
  Timer? _pageAnnouncementTimer;
  bool _gestureEnabled = true;
  bool _isInitialized = false;
  
  final List<String> _features = [
    'Live Location Tracking - Swipe up to access',
    'Transportation routes - Swipe down to access'
  ];
  
  @override
  void initState() {
    super.initState();
    _initializeGestureService();
    _startPageAnnouncements();
  }
  
  @override
  void dispose() {
    _pageAnnouncementTimer?.cancel();
    _gestureService.clearActiveAnnouncementSource('navigation_page');
    _gestureService.dispose();
    super.dispose();
  }

  Future<void> _initializeGestureService() async {
    try {
      await _gestureService.initialize();
      
      // Set gesture callback
      _gestureService.setGestureCallback((GestureType gesture) {
        _handleGesture(gesture);
      });
      
      setState(() {
        _isInitialized = true;
      });
      
      // Welcome message
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          _gestureService.speak(
            'Navigation page loaded. Swipe up for Live Location Tracking, swipe down for Transportation, or swipe left to go back to main page.'
          );
        }
      });
      
    } catch (e) {
      debugPrint('Error initializing gesture service: $e');
    }
  }

  void _startPageAnnouncements() {
    _pageAnnouncementTimer?.cancel();
    
    // Register this page as the active announcement source
    if (!_gestureService.setActiveAnnouncementSource('navigation_page')) {
      // Another page is already making announcements, stop all first
      _gestureService.stopAllAnnouncements();
      _gestureService.setActiveAnnouncementSource('navigation_page');
    }
    
    _pageAnnouncementTimer = Timer.periodic(const Duration(seconds: 8), (timer) {
      if (mounted && _isInitialized && _gestureService.canMakeAnnouncements('navigation_page')) {
        _announcePageContent();
      }
    });
  }

  void _announcePageContent() {
    String announcement = 'Navigation page. Available features: ${_features.join(', ')}. Swipe left to return to main page.';
    _gestureService.speak(announcement);
  }

  void _handleGesture(GestureType gesture) {
    if (!_gestureEnabled) return;
    
    switch (gesture) {
      case GestureType.swipeUp:
        _navigateToLiveLocationTracking();
        break;
      case GestureType.downwardLine:
        _navigateToTransportation();
        break;
      case GestureType.swipeLeft:
        _goBackToMainPage();
        break;
      default:
        break;
    }
  }

  void _navigateToLiveLocationTracking() {
    _gestureService.speak('Opening Live Location Tracking');
    _pauseAnnouncements();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const LiveLocationTrackingPage(),
      ),
    ).then((_) {
      _resumeAnnouncements();
    });
  }

  void _navigateToTransportation() {
    _gestureService.speak('Opening Transportation');
    _pauseAnnouncements();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const TransportationPage(),
      ),
    ).then((_) {
      _resumeAnnouncements();
    });
  }

  void _goBackToMainPage() {
    _gestureService.speak('Returning to main page');
    // Ensure proper cleanup before navigating back
    _pauseAnnouncements();
    // Force clear any remaining announcement control
    _gestureService.stopAllAnnouncements();
    Navigator.pop(context);
  }

  void _pauseAnnouncements() {
    _pageAnnouncementTimer?.cancel();
    _gestureService.clearActiveAnnouncementSource('navigation_page');
  }

  void _resumeAnnouncements() {
    if (mounted && _isInitialized) {
      _startPageAnnouncements();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onPanStart: (details) {
          if (_gestureEnabled && _isInitialized) {
            _gestureService.startGesture(details.localPosition);
          }
        },
        onPanUpdate: (details) {
          if (_gestureEnabled && _isInitialized) {
            _gestureService.updateGesture(details.localPosition);
          }
        },
        onPanEnd: (details) {
          if (_gestureEnabled && _isInitialized) {
            _gestureService.endGesture();
          }
        },
        child: Column(
          children: [
            // Blue header
            Container(
              width: double.infinity,
              height: 120,
              color: const Color(0xFF2561FA),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: _goBackToMainPage,
                      ),
                      const Expanded(
                        child: Text(
                          'Navigation',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      // Gesture toggle button
                      IconButton(
                        icon: Icon(
                          _gestureEnabled ? Icons.gesture : Icons.gesture_outlined,
                          color: _gestureEnabled ? Colors.white : Colors.grey,
                        ),
                        onPressed: () {
                          setState(() {
                            _gestureEnabled = !_gestureEnabled;
                          });
                          _gestureService.speak(
                            _gestureEnabled ? 'Gesture navigation enabled' : 'Gesture navigation disabled'
                          );
                        },
                        tooltip: 'Toggle gesture navigation',
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            // Main content
            Expanded(
              child: Container(
                color: const Color(0xFFF0F4F8), // Light blue-grey background
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 20),
                      
                      // Live Location Tracking button
                      _buildFeatureButton(
                        context: context,
                        icon: Icons.location_on_outlined,
                        title: 'Live Location Tracking',
                        subtitle: 'Swipe up to access',
                        onTap: _navigateToLiveLocationTracking,
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Transportation button
                      _buildFeatureButton(
                        context: context,
                        icon: Icons.directions_bus_outlined,
                        title: 'Transportation',
                        subtitle: 'Swipe down to access',
                        onTap: _navigateToTransportation,
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Gesture instruction panel
                      if (_gestureEnabled && _isInitialized)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2561FA).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF2561FA).withOpacity(0.3)),
                          ),
                          child: const Text(
                            'Gestures: Swipe ↑ for Live Location • Swipe ↓ for Transportation • Swipe ← to go back',
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF2561FA),
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildFeatureButton({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 60,
              color: Colors.black87,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
} 