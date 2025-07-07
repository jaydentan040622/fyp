import 'dart:core';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:flutter/material.dart';
import 'accountModule/user_profile.dart';
import 'imageProcessingModule/image_processing_page.dart';
import 'navigationModule/navigation_page.dart';
import 'navigationModule/gesture_recognition_service.dart';
import 'crowdsourcingModule/crowdsourcing_page.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PageController _pageController = PageController();
  final GestureRecognitionService _gestureService = GestureRecognitionService();
  int _currentPage = 0;
  final int _totalPages = 3;
  Timer? _pageAnnouncementTimer;
  bool _gestureEnabled = true;
  bool _isInitialized = false;
  
  final List<String> _pageNames = [
    'Image Processing',
    'Crowdsourcing',
    'Navigation'
  ];
  
  @override
  void initState() {
    super.initState();
    _initializeGestureService();
    _startPageAnnouncements();
  }
  
  @override
  void dispose() {
    _pageController.dispose();
    _pageAnnouncementTimer?.cancel();
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
      
      // Set debug callback for development
      _gestureService.setDebugCallback((String message) {
        debugPrint('Gesture Debug: $message');
      });
      
      setState(() {
        _isInitialized = true;
      });
      
      // Welcome message
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          _gestureService.announceCurrentPage(_pageNames[_currentPage]);
                               _gestureService.speak(
            'Gesture navigation enabled. Swipe left or right to navigate pages, '
            'draw a line down to open profile, or swipe up to confirm selection.'
          );
        }
      });
      
    } catch (e) {
      debugPrint('Error initializing gesture service: $e');
    }
  }

  void _startPageAnnouncements() {
    _pageAnnouncementTimer?.cancel();
    _pageAnnouncementTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted && _isInitialized) {
        _gestureService.announceCurrentPage(_pageNames[_currentPage]);
      }
    });
  }

  void _pausePageAnnouncements() {
    _pageAnnouncementTimer?.cancel();
  }

  void _resumePageAnnouncements() {
    if (mounted && _isInitialized) {
      _startPageAnnouncements();
    }
  }

  void _handleGesture(GestureType gesture) {
    if (!_gestureEnabled) return;
    
    switch (gesture) {
      case GestureType.swipeLeft:
        _previousPage();
        break;
      case GestureType.swipeRight:
        _nextPage();
        break;
      case GestureType.swipeUp:
        _confirmPageSelection();
        break;
      case GestureType.downwardLine:
        _openProfile();
        break;
      default:
        break;
    }
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.animateToPage(
        _currentPage + 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
              _gestureService.speak('Already at the last page');
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.animateToPage(
        _currentPage - 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
              _gestureService.speak('Already at the first page');
    }
  }

  void _openProfile() {
    _gestureService.speak('Opening user profile');
    _pausePageAnnouncements();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const UserProfileScreen(),
      ),
    ).then((_) {
      // Resume announcements when returning to home page
      _resumePageAnnouncements();
    });
  }

  void _confirmPageSelection() {
    _gestureService.speak('Confirming selection for ${_pageNames[_currentPage]}');
    _pausePageAnnouncements();
    
    // Navigate to the selected page
    switch (_currentPage) {
      case 0:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const ImageProcessingPage(),
          ),
        ).then((_) {
          _resumePageAnnouncements();
        });
        break;
      case 1:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const CrowdsourcingPage(),
          ),
        ).then((_) {
          _resumePageAnnouncements();
        });
        break;
      case 2:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const NavigationPage(),
          ),
        ).then((_) {
          _resumePageAnnouncements();
        });
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
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
              // Header with welcome message and gesture toggle
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    const Expanded(child: UserWidget()),
                    // Gesture toggle button
                    IconButton(
                      icon: Icon(
                        _gestureEnabled ? Icons.gesture : Icons.gesture_outlined,
                        color: _gestureEnabled ? const Color(0xFF2561FA) : Colors.grey,
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
              
              // Main content with PageView
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() {
                      _currentPage = index;
                    });
                    
                    // Announce new page
                    if (_isInitialized) {
                      Future.delayed(const Duration(milliseconds: 300), () {
                        _gestureService.announceCurrentPage(_pageNames[_currentPage]);
                      });
                    }
                  },
                  children: const [
                    // Image Processing Module
                    ImageProcessingModule(),
                    
                    // Crowdsourcing Module
                    CrowdsourcingModule(),
                    
                    // Navigation Module
                    NavigationModule(),
                  ],
                ),
              ),
              
              // Page indicator and navigation arrows
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Previous arrow
                    IconButton(
                      icon: Icon(
                        Icons.arrow_back_ios_rounded,
                        color: _currentPage > 0 ? const Color(0xFF2561FA) : Colors.grey.shade400,
                      ),
                      onPressed: _currentPage > 0 ? _previousPage : null,
                    ),
                    
                    // Page indicators
                    ...List.generate(
                      _totalPages,
                      (index) => Container(
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _currentPage == index
                              ? const Color(0xFF2561FA)
                              : Colors.grey.shade300,
                        ),
                      ),
                    ),
                    
                    // Next arrow
                    IconButton(
                      icon: Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: _currentPage < _totalPages - 1 ? const Color(0xFF2561FA) : Colors.grey.shade400,
                      ),
                      onPressed: _currentPage < _totalPages - 1 ? _nextPage : null,
                    ),
                  ],
                ),
              ),
              
              // Bottom user profile button
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: ElevatedButton.icon(
                  onPressed: _openProfile,
                  icon: const Icon(Icons.person, color: Colors.white),
                  label: const Text(
                    'User Profile',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2561FA),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),
              ),
              
              // Gesture instruction panel (appears when gesture is enabled)
              if (_gestureEnabled && _isInitialized)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2561FA).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF2561FA).withOpacity(0.3)),
                  ),
                  child: const Text(
                    'Gestures: Swipe ← → to navigate • Draw ↓ line for profile • Swipe ↑ to confirm',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF2561FA),
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}

class UserWidget extends StatefulWidget {
  const UserWidget({super.key});

  @override
  State<UserWidget> createState() => _UserWidgetState();
}

class _UserWidgetState extends State<UserWidget> {
  User? _user;
  String _username = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }
  
  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
    });
    
    var user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _user = user;
      
      try {
        // Fetch username from 'userprofile' collection
        final doc = await FirebaseFirestore.instance.collection('userprofile').doc(user.uid).get();
        if (doc.exists && mounted) {
          setState(() {
            _username = doc['username'] ?? '';
            _isLoading = false;
          });
        }
      } catch (e) {
        debugPrint('Error loading user data: $e');
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF2561FA)))
        : Text(
            _username.isNotEmpty ? 'Welcome, $_username!' : 'Welcome!',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2C3E50),
            ),
          );
  }
}

// Image Processing Module
class ImageProcessingModule extends StatelessWidget {
  const ImageProcessingModule({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon or image for the module
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: const Color(0xFF2561FA).withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              Icons.image,
              size: 60,
              color: const Color(0xFF2561FA),
            ),
          ),
          const SizedBox(height: 24),
          
          // Title
          const Text(
            'Image Processing',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2C3E50),
            ),
          ),
          const SizedBox(height: 16),
          
          // Description
          const Text(
            'Analyze and process images with advanced AI tools',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Color(0xFF7F8C8D),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 40),
          
          // Action button
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ImageProcessingPage(),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2561FA),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              'Start Processing',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Crowdsourcing Module
class CrowdsourcingModule extends StatelessWidget {
  const CrowdsourcingModule({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon or image for the module
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: const Color(0xFF2561FA).withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              Icons.people,
              size: 60,
              color: const Color(0xFF2561FA),
            ),
          ),
          const SizedBox(height: 24),
          
          // Title
          const Text(
            'Crowdsourcing',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2C3E50),
            ),
          ),
          const SizedBox(height: 16),
          
          // Description
          const Text(
            'Collaborate with others to gather and share information',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Color(0xFF7F8C8D),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 40),
          
          // Action button
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CrowdsourcingPage(),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2561FA),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              'Join Community',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Navigation Module
class NavigationModule extends StatelessWidget {
  const NavigationModule({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon or image for the module
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: const Color(0xFF2561FA).withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              Icons.map,
              size: 60,
              color: const Color(0xFF2561FA),
            ),
          ),
          const SizedBox(height: 24),
          
          // Title
          const Text(
            'Navigation',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2C3E50),
            ),
          ),
          const SizedBox(height: 16),
          
          // Description
          const Text(
            'Get directions and navigate to your destination',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Color(0xFF7F8C8D),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 40),
          
          // Action button
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const NavigationPage(),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2561FA),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              'Start Navigation',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
