import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vibration/vibration.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:typed_data';
import '../gesture_recognition_service.dart';
import '../home.dart';

class LiveDetectionPage extends StatefulWidget {
  const LiveDetectionPage({super.key});

  @override
  State<LiveDetectionPage> createState() => _LiveDetectionPageState();
}

class _LiveDetectionPageState extends State<LiveDetectionPage> {
  // Camera variables
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isDetecting = false;

  // Speech and audio variables
  bool _isSpeaking = false;
  String _detectionResult = "Starting detection...";
  FlutterTts flutterTts = FlutterTts();

  // Audio players for different sounds
  final AudioPlayer _obstaclePlayer = AudioPlayer();
  final AudioPlayer _personPlayer = AudioPlayer();
  final AudioPlayer _textPlayer = AudioPlayer();

  // Detection settings
  bool _continuousMode = true;
  bool _audioFeedbackEnabled = true;
  bool _hapticFeedbackEnabled = true;

  // Object detection data
  Map<String, dynamic> _lastDetectedObjects = {};

  // Gemini API key
  final String _apiKey = "AIzaSyC_F8UWnADTh8B15lYRcJ5GUJp61p-aBJ"; //w
  late GenerativeModel _model;

  Timer? _captureTimer;
  Timer? _orientationCheckTimer;

  // Gesture detection variables
  Offset? _panStartPosition;
  static const double minSwipeDistance = 100.0;
  static const double maxVerticalDeviation = 50.0;

  @override
  void initState() {
    super.initState();
    _initGemini();
    _initTts();
    _initAudioFeedback();
    _requestPermissions();
    _startOrientationTracking();
  }

  void _initGemini() {
    _model = GenerativeModel(
      model: "gemini-2.5-flash-lite", //switch to 1.5 flash is the most stable
      apiKey: _apiKey,
    );
  }

  void _initTts() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setPitch(1.0);
    await flutterTts.setSpeechRate(0.5);

    flutterTts.setCompletionHandler(() {
      setState(() {
        _isSpeaking = false;
      });
    });
  }

  void _initAudioFeedback() async {
    // Load audio files for different feedback types
    try {
      // These would typically be asset paths, but for now let's just use stub methods
      // await _obstaclePlayer.setAsset('assets/sounds/obstacle_alert.mp3');
      // await _personPlayer.setAsset('assets/sounds/person_alert.mp3');
      // await _textPlayer.setAsset('assets/sounds/text_alert.mp3');
    } catch (e) {
      debugPrint("Error loading audio feedback sounds: $e");
    }
  }

  Future<void> _requestPermissions() async {
    final cameraStatus = await Permission.camera.request();

    if (cameraStatus.isGranted) {
      _initializeCamera();
    } else {
      setState(() {
        _detectionResult = "Camera permission denied";
      });
      _speak("Camera permission is required for this feature to work.");
    }
  }

  void _startOrientationTracking() {
    // Start a timer to check device orientation and process sensor data
    _orientationCheckTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _processOrientationData();
    });

    // Subscribe to accelerometer events
    accelerometerEvents.listen((AccelerometerEvent event) {
      // Process accelerometer data for device movement and orientation
    });
  }

  Future<void> _processOrientationData() async {
    // This would use sensor data to help with navigation
    // For now, just a placeholder
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() {
          _detectionResult = "No camera found";
        });
        return;
      }

      // Use the first back camera
      CameraDescription? backCamera;
      for (var camera in _cameras!) {
        if (camera.lensDirection == CameraLensDirection.back) {
          backCamera = camera;
          break;
        }
      }

      if (backCamera == null) {
        backCamera = _cameras!.first;
      }

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();

      if (!mounted) return;

      setState(() {
        _isCameraInitialized = true;
      });

      // Start the detection loop
      _startDetection();

      // Wait for navigation announcement to complete before starting welcome message
      await Future.delayed(const Duration(seconds: 3));

      // Welcome message
      _speak("Live detection started.");
    } catch (e) {
      setState(() {
        _detectionResult = "Error initializing camera: $e";
      });
      debugPrint("Camera initialization error: $e");
    }
  }

  void _pauseDetection() {
    _captureTimer?.cancel();
    setState(() {
      _detectionResult = "Detection paused.";
    });
  }

  void _resumeDetection() {
    _startDetection();
  }

  void _toggleContinuousMode() {
    setState(() {
      _continuousMode = !_continuousMode;
    });

    if (_continuousMode) {
      _startDetection();
      _speak("Continuous mode enabled");
    } else {
      _captureTimer?.cancel();
      _speak("Continuous mode disabled");
    }
  }

  void _startDetection() {
    if (!_continuousMode) return;

    // Cancel existing timer if any
    _captureTimer?.cancel();

    // Take a frame every 3 seconds (changed from 5 seconds)
    _captureTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_isDetecting && _cameraController != null && _cameraController!.value.isInitialized) {
        _captureAndAnalyzeFrame();
      }
    });

    // Start with first analysis immediately
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      _captureAndAnalyzeFrame();
    }
  }

  Future<void> _captureAndAnalyzeFrame() async {
    if (_isDetecting) return;

    setState(() {
      _isDetecting = true;
    });

    try {
      final XFile imageFile = await _cameraController!.takePicture();

      // Analyze the image using Gemini
      final result = await _analyzeImageWithGemini(imageFile.path);

      setState(() {
        _detectionResult = result;
        _isDetecting = false;
      });

      // Process the result for proximity and direction
      _processDetectionResult(result);

      // Speak the result
      _speak(result);

    } catch (e) {
      setState(() {
        _detectionResult = "Error capturing image: $e";
        _isDetecting = false;
      });
    }
  }

  Future<String> _analyzeImageWithGemini(String imagePath) async {
    try {
      // Read the image file
      final imageBytes = File(imagePath).readAsBytesSync();

      // Create a detailed prompt for image analysis with shortened output request
      final prompt = """
Analyze this image briefly and concisely. 
Include only:
- Key objects and people
- Any text visible in the image
- Important hazards or obstacles

Use short, direct sentences. Limit to 2-3 sentences maximum.
Prioritize safety information for visually impaired users.
      """;

      // Create multi-part content with text and image
      final content = [
        Content.multi([
          TextPart(prompt),
          DataPart('image/jpeg', imageBytes),
        ])
      ];

      // Set generation config for more controlled output with reduced token length
      final generationConfig = GenerationConfig(
        temperature: 0.4,
        topK: 32,
        topP: 1,
        maxOutputTokens: 100, // Reduced from 200 to get shorter responses
      );

      // Generate content with the model
      final response = await _model.generateContent(
        content,
        generationConfig: generationConfig,
      );

      // Process the response
      final candidates = response.candidates;
      if (candidates == null || candidates.isEmpty) {
        debugPrint("No response candidates from Gemini");
        return "Unable to analyze the image. No response from AI model.";
      }

      // Get the text from the response
      final responseText = candidates.first.content?.parts
          ?.whereType<TextPart>()
          .map((part) => part.text)
          .join('\n');

      if (responseText == null || responseText.isEmpty) {
        debugPrint("Empty text response from Gemini");
        return "Unable to analyze the image content.";
      }

      return responseText;

    } catch (e) {
      debugPrint("Gemini API error: $e");
      String errorMessage = e.toString();
      if (errorMessage.contains("RESOURCE_EXHAUSTED")) {
        return "API quota exceeded. Please try again later.";
      } else if (errorMessage.contains("INVALID_ARGUMENT")) {
        return "Invalid image format. Please try another image.";
      } else if (errorMessage.contains("PERMISSION_DENIED")) {
        return "API key validation error. Please check your API key.";
      }
      return "Error analyzing image: $e";
    }
  }

  void _processDetectionResult(String result) {
    // Parse the detection result to extract relevant information

    // Parse for obstacles
    if (result.toLowerCase().contains("obstacle") ||
        result.toLowerCase().contains("hazard") ||
        result.toLowerCase().contains("danger")) {
      _playObstacleAlert();
    }

    // Parse for people
    if (result.toLowerCase().contains("person") ||
        result.toLowerCase().contains("people")) {
      _playPersonAlert();
    }

    // Check for signs or text
    if (result.toLowerCase().contains("sign") ||
        result.toLowerCase().contains("text") ||
        result.toLowerCase().contains("label")) {
      _playTextAlert();
    }
  }

  void _playObstacleAlert() {
    if (!_audioFeedbackEnabled) return;

    // In a real app, you would play the pre-loaded sound
    // Here we'll just use a placeholder
    debugPrint("Playing obstacle alert sound");
    // _obstaclePlayer.play();

    // Provide haptic feedback for obstacle
    if (_hapticFeedbackEnabled) {
      // Fixed vibration pattern - the first value is the delay before starting,
      // then alternating between vibration duration and pause duration in milliseconds
      Vibration.vibrate(pattern: [0, 300, 200, 300, 200, 300]);
    }
  }

  void _playPersonAlert() {
    if (!_audioFeedbackEnabled) return;
    debugPrint("Playing person alert sound");
    // _personPlayer.play();
  }

  void _playTextAlert() {
    if (!_audioFeedbackEnabled) return;
    debugPrint("Playing text alert sound");
    // _textPlayer.play();
  }

  // Gesture detection methods
  void _onPanStart(DragStartDetails details) {
    _panStartPosition = details.localPosition;
  }

  void _onPanEnd(DragEndDetails details) {
    if (_panStartPosition == null) return;

    final Offset panEndPosition = details.localPosition;
    final double deltaX = panEndPosition.dx - _panStartPosition!.dx;
    final double deltaY = panEndPosition.dy - _panStartPosition!.dy;

    // Check if it's a horizontal swipe
    if (deltaX.abs() >= minSwipeDistance && deltaY.abs() <= maxVerticalDeviation) {
      if (deltaX > 0) {
        // Swipe Right - Go to main page
        _handleSwipeRight();
      } else {
        // Swipe Left - Return to previous page immediately
        _handleSwipeLeft();
      }
    }

    _panStartPosition = null;
  }

  void _handleSwipeLeft() {
    // Provide haptic feedback
    if (_hapticFeedbackEnabled) {
      Vibration.vibrate(duration: 100);
    }
    
    // Navigate back to previous page immediately
    Navigator.of(context).pop();
  }

  void _handleSwipeRight() {
    // Provide haptic feedback
    if (_hapticFeedbackEnabled) {
      Vibration.vibrate(duration: 100);
    }
    
    // Navigate to main page
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const HomeScreen()),
          (route) => false,
    );
  }

  Future<void> _speak(String text) async {
    if (text.isNotEmpty && !_isSpeaking) {
      setState(() {
        _isSpeaking = true;
      });
      await flutterTts.speak(text);
    }
  }

  @override
  void dispose() {
    _captureTimer?.cancel();
    _orientationCheckTimer?.cancel();
    _cameraController?.dispose();
    flutterTts.stop();
    _obstaclePlayer.dispose();
    _personPlayer.dispose();
    _textPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final bool isSmallScreen = screenSize.width < 400;
    final double horizontalPadding = isSmallScreen ? 12.0 : 20.0;
    final double cardElevation = isSmallScreen ? 3.0 : 5.0;
    
    return GestureDetector(
      onPanStart: _onPanStart,
      onPanEnd: _onPanEnd,
      behavior: HitTestBehavior.translucent, // This ensures gestures are detected across the entire screen
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF2561FA).withOpacity(0.9),
                const Color(0xFF2561FA).withOpacity(0.9),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(isSmallScreen ? 3 : 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.camera_enhance,
                color: Colors.white,
                size: isSmallScreen ? 18 : 20,
              ),
            ),
            SizedBox(width: isSmallScreen ? 8 : 10),
            Text(
              'Live Detection',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: isSmallScreen ? 20 : 22,
                color : Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _continuousMode ? Icons.loop : Icons.sync_disabled,
              color: Colors.white,
              size: isSmallScreen ? 22 : 24,
            ),
            onPressed: _toggleContinuousMode,
            tooltip: _continuousMode ? 'Continuous Mode On' : 'Continuous Mode Off',
          ),
        ],
      ),
      body: Column(
          children: [
            Expanded(
              flex: 3,
              child: Stack(
                children: [
                  // Camera Preview with rounded corners
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: const Color(0xFF2561FA).withOpacity(0.3),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2561FA).withOpacity(0.2),
                          blurRadius: 15,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    margin: EdgeInsets.fromLTRB(12, MediaQuery.of(context).padding.top + 60, 12, 12),
                    child: _isCameraInitialized
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: CameraPreview(_cameraController!),
                          )
                        : const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFF3366FF),
                              strokeWidth: 3,
                            ),
                          ),
                  ),
                  // Status indicator overlay
                  Positioned(
                    top: 90,
                    right: 24,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _isDetecting
                            ? Colors.orange.withOpacity(0.85)
                            : const Color(0xFF4CAF50).withOpacity(0.85),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isDetecting ? Icons.radar : Icons.visibility,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _isDetecting ? 'Analyzing' : 'Ready',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                   gradient: LinearGradient(
                     begin: Alignment.topCenter,
                     end: Alignment.bottomCenter,
                     colors: [
                       const Color(0xFF1A1A1A),
                       const Color(0xFF0D0D0D),
                     ],
                   ),
                   borderRadius: const BorderRadius.only(
                     topLeft: Radius.circular(24),
                     topRight: Radius.circular(24),
                   ),
                   boxShadow: [
                     BoxShadow(
                       color: Colors.black.withOpacity(0.3),
                       spreadRadius: 1,
                       blurRadius: 10,
                       offset: const Offset(0, -3),
                     ),
                   ],
                 ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Analysis Result Section
                        Container(
                          padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFF2561FA).withOpacity(0.3),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: cardElevation + 3,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.analytics_outlined,
                                    color: Color(0xFF3366FF),
                                    size: 22,
                                  ),
                                  const SizedBox(width: 10),
                                  const Text(
                                    'Analysis Result',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                      color: Colors.white,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(
                                color: Color(0xFF444444),
                                thickness: 1,
                                height: 24,
                              ),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _detectionResult,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Colors.white,
                                    height: 1.5,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 20),
                        
                        // Action Buttons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _isDetecting ? null : _captureAndAnalyzeFrame,
                                icon: Icon(
                                  _isDetecting ? Icons.hourglass_top : Icons.camera_alt,
                                  size: isSmallScreen ? 20 : 22,
                                ),
                                label: Text(
                                  _isDetecting ? 'Analyzing...' : 'Analyze Now',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: isSmallScreen ? 14 : 16,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF3366FF),
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: Colors.grey.shade600,
                                  disabledForegroundColor: Colors.white70,
                                  padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 12 : 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: cardElevation,
                                  shadowColor: const Color(0xFF3366FF).withOpacity(0.6),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _isSpeaking ? null : () => _speak(_detectionResult),
                                icon: Icon(
                                  _isSpeaking ? Icons.volume_up : Icons.record_voice_over,
                                  size: isSmallScreen ? 20 : 22,
                                ),
                                label: Text(
                                  _isSpeaking ? 'Speaking...' : 'Read Aloud',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: isSmallScreen ? 14 : 16,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF3366FF),
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: Colors.grey.shade600,
                                  disabledForegroundColor: Colors.white70,
                                  padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 12 : 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: cardElevation,
                                  shadowColor: const Color(0xFF3366FF).withOpacity(0.6),
                                ),
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 20),
                        
                        // Settings Toggles
                        Container(
                          padding: EdgeInsets.all(isSmallScreen ? 14 : 16),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.grey.withOpacity(0.3),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: cardElevation + 3,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.settings,
                                    color: Color(0xFF3366FF),
                                    size: 22,
                                  ),
                                  const SizedBox(width: 10),
                                  const Text(
                                    'Feedback Settings',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Colors.white,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(
                                color: Color(0xFF444444),
                                thickness: 1,
                                height: 24,
                              ),
                              // Audio Feedback Toggle
                              SwitchListTile(
                                title: const Text(
                                  'Audio Cues',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                subtitle: Text(
                                  _audioFeedbackEnabled ? 'Enabled' : 'Disabled',
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 12,
                                  ),
                                ),
                                value: _audioFeedbackEnabled,
                                onChanged: (value) {
                                  setState(() {
                                    _audioFeedbackEnabled = value;
                                  });
                                  _speak(_audioFeedbackEnabled
                                      ? "Audio feedback enabled"
                                      : "Audio feedback disabled");
                                },
                                activeColor: const Color(0xFF3366FF),
                                contentPadding: EdgeInsets.zero,
                              ),
                              // Haptic Feedback Toggle
                              SwitchListTile(
                                title: const Text(
                                  'Haptic Feedback',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                subtitle: Text(
                                  _hapticFeedbackEnabled ? 'Enabled' : 'Disabled',
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 12,
                                  ),
                                ),
                                value: _hapticFeedbackEnabled,
                                onChanged: (value) {
                                  setState(() {
                                    _hapticFeedbackEnabled = value;
                                  });
                                  _speak(_hapticFeedbackEnabled
                                      ? "Haptic feedback enabled"
                                      : "Haptic feedback disabled");
                                  if (_hapticFeedbackEnabled) {
                                    Vibration.vibrate(duration: 300);
                                  }
                                },
                                activeColor: const Color(0xFF3366FF),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Swipe instruction
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(
                                  Icons.swipe,
                                  color: Colors.white70,
                                  size: 16,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Swipe left/right to navigate',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}