import 'dart:core';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'accountModule/user_profile.dart';
import 'accountModule/login_page.dart';
import 'accountModule/auth_gate.dart';
import 'imageProcessingModule/image_processing_page.dart';
import 'navigationModule/navigation_page.dart';
import 'crowdsourcingModule/crowdsourcing_page.dart';

// Dedicated gesture types for home page
enum HomeGestureType {
  swipeLeft,
  swipeRight,
  swipeUp,
  downwardLine,
  unknown
}

class HomeGesturePoint {
  final double x;
  final double y;
  final DateTime timestamp;
  HomeGesturePoint(this.x, this.y, this.timestamp);
}

// Dedicated gesture service for home page only
class HomeGestureService {
  static final HomeGestureService _instance = HomeGestureService._internal();
  factory HomeGestureService() => _instance;
  HomeGestureService._internal();

  final FlutterTts _flutterTts = FlutterTts();
  final List<HomeGesturePoint> _gesturePoints = [];
  bool _isInitialized = false;
  bool _isRecording = false;
  Function(HomeGestureType)? _onGestureDetected;

  // Gesture detection parameters
  static const double _minSwipeDistance = 100.0;
  static const double _maxSwipeVerticalDeviation = 50.0;
  static const double _minDownwardLineDistance = 80.0;
  static const double _maxDownwardLineHorizontalDeviation = 30.0;
  static const double _minUpwardSwipeDistance = 100.0;
  static const double _maxUpwardSwipeHorizontalDeviation = 50.0;

  Future<void> initialize() async {
    try {
      await _flutterTts.setLanguage('en-US');
      await _flutterTts.setSpeechRate(0.6);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      _isInitialized = true;
      debugPrint('HomeGestureService initialized successfully');
    } catch (e) {
      debugPrint('Error initializing HomeGestureService: $e');
    }
  }

  void setGestureCallback(Function(HomeGestureType) callback) {
    _onGestureDetected = callback;
  }

  Future<void> speak(String text) async {
    if (!_isInitialized) return;
    try {
      await _flutterTts.stop();
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint('Error speaking: $e');
    }
  }

  void startGesture(Offset position) {
    _isRecording = true;
    _gesturePoints.clear();
    _gesturePoints.add(HomeGesturePoint(position.dx, position.dy, DateTime.now()));
  }

  void updateGesture(Offset position) {
    if (!_isRecording) return;
    _gesturePoints.add(HomeGesturePoint(position.dx, position.dy, DateTime.now()));
  }

  void endGesture() {
    if (!_isRecording) return;
    _isRecording = false;

    if (_gesturePoints.length < 2) return;

    HomeGestureType detectedGesture = _analyzeGesture();

    if (detectedGesture != HomeGestureType.unknown) {
      _triggerHapticFeedback(detectedGesture);
      _announceGesture(detectedGesture);
      _onGestureDetected?.call(detectedGesture);
    }

    _gesturePoints.clear();
  }

  HomeGestureType _analyzeGesture() {
    if (_gesturePoints.length < 2) return HomeGestureType.unknown;

    double startX = _gesturePoints.first.x;
    double endX = _gesturePoints.last.x;
    double startY = _gesturePoints.first.y;
    double endY = _gesturePoints.last.y;

    double horizontalDistance = (endX - startX).abs();
    double verticalDistance = (endY - startY).abs();

    // Check for horizontal swipe (left/right)
    if (horizontalDistance >= _minSwipeDistance &&
        verticalDistance <= _maxSwipeVerticalDeviation) {
      return endX > startX ? HomeGestureType.swipeRight : HomeGestureType.swipeLeft;
    }

    // Check for upward swipe
    if (verticalDistance >= _minUpwardSwipeDistance &&
        horizontalDistance <= _maxUpwardSwipeHorizontalDeviation) {
      if (endY < startY) return HomeGestureType.swipeUp;
    }

    // Check for downward line
    double verticalMovement = endY - startY;
    if (verticalMovement >= _minDownwardLineDistance &&
        horizontalDistance <= _maxDownwardLineHorizontalDeviation) {
      return HomeGestureType.downwardLine;
    }

    return HomeGestureType.unknown;
  }

  void _triggerHapticFeedback(HomeGestureType gestureType) {
    switch (gestureType) {
      case HomeGestureType.swipeLeft:
      case HomeGestureType.swipeRight:
        Vibration.vibrate(duration: 100);
        break;
      case HomeGestureType.swipeUp:
        Vibration.vibrate(pattern: [50, 50, 50, 50, 50]);
        break;
      case HomeGestureType.downwardLine:
        Vibration.vibrate(pattern: [100, 50, 100]);
        break;
      default:
        break;
    }
  }

  void _announceGesture(HomeGestureType gestureType) {
    String message = '';
    switch (gestureType) {
      case HomeGestureType.swipeLeft:
        message = 'Swipe left detected';
        break;
      case HomeGestureType.swipeRight:
        message = 'Swipe right detected';
        break;
      case HomeGestureType.swipeUp:
        message = 'Swipe up detected';
        break;
      case HomeGestureType.downwardLine:
        message = 'Downward line detected';
        break;
      default:
        return;
    }
    speak(message);
  }

  void dispose() {
    _flutterTts.stop();
    _gesturePoints.clear();
    _onGestureDetected = null;
    _isInitialized = false;
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver, RouteAware {
  final PageController _pageController = PageController();
  final HomeGestureService _gestureService = HomeGestureService();
  int _currentPage = 0;
  final int _totalPages = 3;
  Timer? _pageAnnouncementTimer;
  Timer? _initializationTimer;
  bool _gestureEnabled = true;
  bool _isInitialized = false;
  bool _isActive = false;

  final List<String> _pageNames = [
    'Image Processing',
    'Crowdsourcing',
    'Navigation'
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeSystem();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _pageAnnouncementTimer?.cancel();
    _initializationTimer?.cancel();
    _gestureService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _checkAndReinitialize();
    }
  }

  void _initializeSystem() {
    debugPrint('HomeScreen: Initializing system...');
    _isActive = true;

    // Cancel any existing initialization
    _initializationTimer?.cancel();

    _initializationTimer = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted || !_isActive) return;

      try {
        // Initialize gesture service
        await _gestureService.initialize();

        if (!mounted || !_isActive) return;

        // Set up gesture callback
        _gestureService.setGestureCallback((HomeGestureType gesture) {
          if (mounted && _isActive) {
            _handleGesture(gesture);
          }
        });

        if (!mounted || !_isActive) return;

        setState(() {
          _isInitialized = true;
        });

        // Start announcements
        _startPageAnnouncements();

        // Welcome message
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted && _isActive) {
            _gestureService.speak('Welcome to the main page. ${_pageNames[_currentPage]}');
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted && _isActive) {
                _gestureService.speak(
                    'Gesture navigation enabled. Swipe left or right to navigate pages, '
                        'draw a line down to open profile, or swipe up to confirm selection.'
                );
              }
            });
          }
        });

        debugPrint('HomeScreen: System initialized successfully');
      } catch (e) {
        debugPrint('HomeScreen: Error initializing system: $e');
        // Retry initialization
        if (mounted && _isActive) {
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted && _isActive) _initializeSystem();
          });
        }
      }
    });
  }

  void _checkAndReinitialize() {
    debugPrint('HomeScreen: Checking and reinitializing...');
    if (!mounted) return;

    // Check if we're the current route
    if (ModalRoute.of(context)?.isCurrent == true) {
      _isActive = true;
      if (!_isInitialized ||
          _pageAnnouncementTimer == null ||
          !_pageAnnouncementTimer!.isActive) {
        debugPrint('HomeScreen: Reinitializing due to inactive state');
        _initializeSystem();
      }
    }
  }

  void _startPageAnnouncements() {
    if (!mounted || !_isActive) return;

    _pageAnnouncementTimer?.cancel();
    _pageAnnouncementTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted && _isInitialized && _isActive) {
        int pageIndex = _currentPage;
        if (_pageController.hasClients) {
          final double? page = _pageController.page;
          if (page != null) pageIndex = page.round();
        }
        _gestureService.speak('Current page: ${_pageNames[pageIndex]}');
      }
    });
    debugPrint('HomeScreen: One-shot page announcement scheduled');
  }

  void _pausePageAnnouncements() {
    _pageAnnouncementTimer?.cancel();
    _isActive = false;
    debugPrint('HomeScreen: Page announcements paused');
  }

  void _handleGesture(HomeGestureType gesture) {
    if (!_gestureEnabled || !_isInitialized || !_isActive) return;

    debugPrint('HomeScreen: Handling gesture: $gesture');

    switch (gesture) {
      case HomeGestureType.swipeLeft:
        _previousPage();
        break;
      case HomeGestureType.swipeRight:
        _nextPage();
        break;
      case HomeGestureType.swipeUp:
        _confirmPageSelection();
        break;
      case HomeGestureType.downwardLine:
        _openProfile();
        break;
      default:
        break;
    }
  }

  void _nextPage() {
    debugPrint('Current page is $_currentPage, total pages are $_totalPages');
    if (_currentPage < _totalPages - 1) {
      debugPrint('HomeScreen: swipeRight - _currentPage=$_currentPage, animating to ${_currentPage + 1}');
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
    debugPrint('Current page is $_currentPage, total pages are $_totalPages');
    if (_currentPage > 0) {
      debugPrint('HomeScreen: swipeLeft - _currentPage=$_currentPage, animating to ${_currentPage - 1}');
      _pageController.animateToPage(
        _currentPage - 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _gestureService.speak('Already at the first page');
    }
  }

  Future<void> _openProfile() async {
    // Check if user is authenticated
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      // Guest user - directly navigate to login page
      _gestureService.speak('Please log in to access your profile. Going to main page');
      _pausePageAnnouncements();
      await Future.delayed(const Duration(milliseconds: 4000));
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const AuthGate()),
            (route) => false,
      );
    } else {
      // Authenticated user - proceed normally
      _gestureService.speak('Opening user profile');
      _pausePageAnnouncements();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const UserProfileScreen(),
        ),
      ).then((_) {
        // Reinitialize when returning
        _initializeSystem();
      });
    }
  }


  Future<void> _confirmPageSelection() async {
    // Determine the most reliable, settled page index
    int pageIndex = await _getSettledPageIndex();
    // Keep state in sync if needed
    if (pageIndex != _currentPage) {
      setState(() {
        _currentPage = pageIndex;
      });
    }

    _gestureService.speak('Confirming selection for ${_pageNames[pageIndex]}');
    _pausePageAnnouncements();

    Widget targetPage;
    debugPrint('HomeScreen: Confirming selection for $pageIndex');
    switch (pageIndex) {
      case 0:
        targetPage = const ImageProcessingPage();
        break;
      case 1:
        targetPage = const CrowdsourcingPage();
        break;
      case 2:
        targetPage = const NavigationPage();
        break;
      default:
        return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => targetPage),
    ).then((_) {
      // Reinitialize when returning
      _initializeSystem();
    });
  }

  Future<int> _getSettledPageIndex({Duration timeout = const Duration(milliseconds: 800)}) async {
    if (!_pageController.hasClients) return _currentPage;
    final Stopwatch sw = Stopwatch()..start();
    while (true) {
      bool isScrolling = false;
      try {
        isScrolling = _pageController.position.isScrollingNotifier.value;
      } catch (_) {}
      if (!isScrolling) break;
      if (sw.elapsed >= timeout) break;
      await Future.delayed(const Duration(milliseconds: 50));
    }
    final double? page = _pageController.page;
    if (page == null) return _currentPage;
    return page.round();
  }

  @override
  Widget build(BuildContext context) {
    // Check if we're becoming active again
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        if (!_isActive) {
          debugPrint('HomeScreen: Detected return to home, reinitializing...');
          _initializeSystem();
        }
      }
    });

    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          onPanStart: (details) {
            if (_gestureEnabled && _isInitialized && _isActive) {
              _gestureService.startGesture(details.localPosition);
            }
          },
          onPanUpdate: (details) {
            if (_gestureEnabled && _isInitialized && _isActive) {
              _gestureService.updateGesture(details.localPosition);
            }
          },
          onPanEnd: (details) {
            if (_gestureEnabled && _isInitialized && _isActive) {
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
                    debugPrint('HomeScreen: onPageChanged -> $index');
                    setState(() {
                      _currentPage = index;
                    });

                    // Announce new page
                    if (_isInitialized) {
                      Future.delayed(const Duration(milliseconds: 300), () {
                        _gestureService.speak('Current page: ${_pageNames[_currentPage]}');
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
