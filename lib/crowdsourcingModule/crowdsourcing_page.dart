import 'dart:async';
import 'package:flutter/material.dart';
import '../gesture_recognition_service.dart';
import 'assistance_page.dart';
import 'voice_note_page.dart';
import 'chatbot_page.dart';

class CrowdsourcingPage extends StatefulWidget {
  const CrowdsourcingPage({super.key});

  @override
  State<CrowdsourcingPage> createState() => _CrowdsourcingPageState();
}

class _CrowdsourcingPageState extends State<CrowdsourcingPage> {
  final GestureRecognitionService _gestureService = GestureRecognitionService();
  Timer? _pageAnnouncementTimer;
  bool _gestureEnabled = true;
  bool _isInitialized = false;

  final List<String> _features = [
    'Chatbot for assistance - Swipe up to access',
    'Voice Note recording - Swipe down to access'
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
    _gestureService.clearActiveAnnouncementSource('crowdsourcing_page');
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
              'Crowdsourcing page loaded. Swipe up for Chatbot, swipe down for Voice Note, or swipe left to go back to main page.'
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
    if (!_gestureService.setActiveAnnouncementSource('crowdsourcing_page')) {
      // Another page is already making announcements, stop all first
      _gestureService.stopAllAnnouncements();
      _gestureService.setActiveAnnouncementSource('crowdsourcing_page');
    }

    _pageAnnouncementTimer = Timer.periodic(const Duration(seconds: 8), (timer) {
      if (mounted && _isInitialized && _gestureService.canMakeAnnouncements('crowdsourcing_page')) {
        _announcePageContent();
      }
    });
  }

  void _announcePageContent() {
    String announcement = 'Crowdsourcing page. Available features: ${_features.join(', ')}. Swipe left to return to main page.';
    _gestureService.speak(announcement);
  }

  void _handleGesture(GestureType gesture) {
    if (!_gestureEnabled) return;

    switch (gesture) {
      case GestureType.swipeUp:
        _navigateToChatbot();
        break;
      case GestureType.downwardLine:
        _navigateToVoiceNote();
        break;
      case GestureType.swipeLeft:
        _goBackToMainPage();
        break;
      default:
        break;
    }
  }

  void _navigateToChatbot() {
    _gestureService.speak('Opening Chatbot');
    _pauseAnnouncements();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ChatbotPage(),
      ),
    ).then((_) {
      _resumeAnnouncements();
    });
  }

  void _navigateToVoiceNote() {
    _gestureService.speak('Opening Voice Note');
    _pauseAnnouncements();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const VoiceNotePage(),
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
    _gestureService.clearActiveAnnouncementSource('crowdsourcing_page');
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
                          'Crowdsourcing',
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

                      // Chatbot button
                      _buildFeatureButton(
                        context: context,
                        icon: Icons.chat_bubble_outline,
                        title: 'Chatbot',
                        subtitle: 'Swipe up to access',
                        onTap: _navigateToChatbot,
                      ),

                      const SizedBox(height: 24),

                      // Voice Note button
                      _buildFeatureButton(
                        context: context,
                        icon: Icons.mic_none_outlined,
                        title: 'Voice Note',
                        subtitle: 'Swipe down to access',
                        onTap: _navigateToVoiceNote,
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
                            'Gestures: Swipe ↑ for Chatbot • Swipe ↓ for Voice Note • Swipe ← to go back',
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