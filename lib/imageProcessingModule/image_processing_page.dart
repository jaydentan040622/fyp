import 'dart:async';
import 'package:flutter/material.dart';
import '../gesture_recognition_service.dart';
import 'live_detection_page.dart';
import 'ocr_page.dart';

class ImageProcessingPage extends StatefulWidget {
  const ImageProcessingPage({super.key});

  @override
  State<ImageProcessingPage> createState() => _ImageProcessingPageState();
}

class _ImageProcessingPageState extends State<ImageProcessingPage> with WidgetsBindingObserver {
  final GestureRecognitionService _gestureService = GestureRecognitionService();
  Timer? _pageAnnouncementTimer;
  bool _gestureEnabled = true;
  bool _isInitialized = false;

  final List<String> _features = [
    'Live Detection - Swipe up to access',
    'OCR Text Recognition - Swipe down to access'
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeGestureService();
    _startPageAnnouncements();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && mounted && _isInitialized) {
      // When app resumes, restart announcements
      debugPrint('App resumed - restarting Image Processing announcements');
      _resumeAnnouncements();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageAnnouncementTimer?.cancel();
    _gestureService.clearActiveAnnouncementSource('image_processing_page');
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
              'Image Processing page loaded. Swipe up for Live Detection, swipe down for OCR, or swipe left to go back to main page.'
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
    if (!_gestureService.setActiveAnnouncementSource('image_processing_page')) {
      // Another page is already making announcements, stop all first
      _gestureService.stopAllAnnouncements();
      _gestureService.setActiveAnnouncementSource('image_processing_page');
    }

    _pageAnnouncementTimer = Timer.periodic(const Duration(seconds: 8), (timer) {
      if (mounted && _isInitialized && _gestureService.canMakeAnnouncements('image_processing_page')) {
        _announcePageContent();
      }
    });
  }

  void _announcePageContent() {
    String announcement = 'Image Processing page. Available features: ${_features.join(', ')}. Swipe left to return to main page.';
    _gestureService.speak(announcement);
  }

  void _handleGesture(GestureType gesture) {
    if (!_gestureEnabled) return;

    switch (gesture) {
      case GestureType.swipeUp:
        _navigateToLiveDetection();
        break;
      case GestureType.downwardLine:
        _navigateToOCR();
        break;
      case GestureType.swipeLeft:
        _goBackToMainPage();
        break;
      default:
        break;
    }
  }

  void _navigateToLiveDetection() {
    _gestureService.speak('Opening Live Detection');
    _pauseAnnouncements();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const LiveDetectionPage(),
      ),
    ).then((_) {
      // Always resume announcements when returning
      if (mounted) {
        debugPrint('Returned from Live Detection - resuming announcements');
        _resumeAnnouncements();
      }
    });
  }

  void _navigateToOCR() {
    _gestureService.speak('Opening OCR Text Recognition');
    _pauseAnnouncements();
    // Force stop all announcements to ensure clean transition
    _gestureService.stopAllAnnouncements();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const OCRPage(),
      ),
    ).then((_) {
      // Only resume if we're still on this page and it's mounted
      if (mounted && _isInitialized) {
        debugPrint('Returned from OCR - resuming announcements');
        _resumeAnnouncements();
      }
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
    _gestureService.clearActiveAnnouncementSource('image_processing_page');
  }

  void _resumeAnnouncements() {
    if (mounted && _isInitialized && ModalRoute.of(context)?.isCurrent == true) {
      // Only resume if this page is the top of the stack
      _startPageAnnouncements();
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
          _gestureService.speak('Returned to Image Processing page.');
        }
      });
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
                          'Image Processing',
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

                      // Live Detection button
                      _buildFeatureButton(
                        context: context,
                        icon: Icons.camera_alt_outlined,
                        title: 'Live Detection',
                        subtitle: 'Swipe up to access',
                        onTap: _navigateToLiveDetection,
                      ),

                      const SizedBox(height: 24),

                      // OCR button
                      _buildFeatureButton(
                        context: context,
                        icon: Icons.text_fields_outlined,
                        title: 'OCR',
                        subtitle: 'Swipe down to access',
                        onTap: _navigateToOCR,
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
                            'Gestures: Swipe ↑ for Live Detection • Swipe ↓ for OCR • Swipe ← to go back',
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