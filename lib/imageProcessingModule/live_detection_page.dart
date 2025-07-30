import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:vibration/vibration.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:typed_data';
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
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  bool _isListening = false;

  // Audio players for different sounds
  final AudioPlayer _obstaclePlayer = AudioPlayer();
  final AudioPlayer _personPlayer = AudioPlayer();
  final AudioPlayer _textPlayer = AudioPlayer();

  // Detection settings
  bool _continuousMode = true;
  bool _voiceCommandsEnabled = true;
  bool _audioFeedbackEnabled = true;
  bool _hapticFeedbackEnabled = true;

  // Object detection data
  Map<String, dynamic> _lastDetectedObjects = {};

  // Gemini API key
  final String _apiKey = "AIzaSyA-aoTz99SRfSdyy0Q2Slb8JsgUZ2oXwm8";
  late GenerativeModel _model;

  Timer? _captureTimer;
  Timer? _voiceCommandsTimer;
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
    _initSpeechRecognition();
    _initAudioFeedback();
    _requestPermissions();
    _startOrientationTracking();
  }

  void _initGemini() {
    _model = GenerativeModel(
      model: "gemini-1.5-flash",
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

      // If in continuous mode and not currently speaking or detecting,
      // start listening for voice commands
      if (_voiceCommandsEnabled && !_isListening && !_isDetecting) {
        _startListening();
      }
    });
  }

  Future<void> _initSpeechRecognition() async {
    bool available = await _speechToText.initialize(
      onStatus: (status) {
        debugPrint('Speech recognition status: $status');
        if (status == 'done' || status == 'notListening') {
          setState(() {
            _isListening = false;
          });
        }
      },
      onError: (error) => debugPrint('Speech recognition error: $error'),
    );

    if (available && _voiceCommandsEnabled) {
      _startVoiceCommandListener();
    } else {
      debugPrint("Speech recognition not available");
    }
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
    final micStatus = await Permission.microphone.request();
    final cameraStatus = await Permission.camera.request();

    if (cameraStatus.isGranted) {
      _initializeCamera();
    } else {
      setState(() {
        _detectionResult = "Camera permission denied";
      });
      _speak("Camera permission is required for this feature to work.");
    }

    if (!micStatus.isGranted) {
      setState(() {
        _voiceCommandsEnabled = false;
      });
      _speak("Microphone permission denied. Voice commands will be disabled.");
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

      // If voice commands are enabled, start listening
      if (_voiceCommandsEnabled) {
        _startVoiceCommandListener();
      }

      // Wait for navigation announcement to complete before starting welcome message
      await Future.delayed(const Duration(seconds: 3));

      // Welcome message
      _speak("Live detection started. Say 'help' for available voice commands.");
    } catch (e) {
      setState(() {
        _detectionResult = "Error initializing camera: $e";
      });
      debugPrint("Camera initialization error: $e");
    }
  }

  void _startVoiceCommandListener() {
    // Start periodic listening for voice commands
    _voiceCommandsTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_isSpeaking && !_isListening && _voiceCommandsEnabled) {
        _startListening();
      }
    });

    // Start listening immediately
    if (_voiceCommandsEnabled && !_isSpeaking && !_isListening) {
      _startListening();
    }
  }

  void _startListening() {
    if (!_speechToText.isAvailable || _isSpeaking) return;

    _speechToText.listen(
      onResult: (result) {
        if (result.finalResult) {
          String command = result.recognizedWords.toLowerCase();
          _processVoiceCommand(command);
        }
      },
      listenFor: const Duration(seconds: 5),
      pauseFor: const Duration(seconds: 3),
      listenMode: stt.ListenMode.confirmation,
    );

    setState(() {
      _isListening = true;
    });
  }

  void _processVoiceCommand(String command) {
    debugPrint("Voice command detected: $command");

    if (command.contains('start') || command.contains('detect') || command.contains('analyze')) {
      _captureAndAnalyzeFrame();
      _speak("Starting detection");
    }
    else if (command.contains('stop') || command.contains('pause')) {
      _pauseDetection();
      _speak("Detection paused");
    }
    else if (command.contains('resume')) {
      _resumeDetection();
      _speak("Resuming detection");
    }
    else if (command.contains('continuous')) {
      _toggleContinuousMode();
    }
    else if (command.contains('where am i') || command.contains('location')) {
      _announceCurrentLocation();
    }
    else if (command.contains('help')) {
      _provideHelpInformation();
    }
  }

  void _pauseDetection() {
    _captureTimer?.cancel();
    setState(() {
      _detectionResult = "Detection paused. Say 'resume' to continue.";
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

  void _announceCurrentLocation() {
    // This would use geolocation and previous detections to describe surroundings
    _speak("Based on recent detections, ${_detectionResult}");
  }

  void _provideHelpInformation() {
    const helpMessage = "Available commands: Start detection, Stop, Resume, Continuous mode, Where am I, and Help.";
    _speak(helpMessage);
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
      Vibration.vibrate(pattern: [0, 100, 100, 100, 100, 100]);
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
        // Swipe Right - Go to Image Processing page
        _handleSwipeRight();
      } else {
        // Swipe Left - Return to main page
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

    // Navigate to main page
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const HomeScreen()),
          (route) => false,
    );
  }

  void _handleSwipeRight() {
    // Provide haptic feedback
    if (_hapticFeedbackEnabled) {
      Vibration.vibrate(duration: 100);
    }

    // Navigate back to Image Processing page
    Navigator.of(context).pop();
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
    _voiceCommandsTimer?.cancel();
    _orientationCheckTimer?.cancel();
    _cameraController?.dispose();
    flutterTts.stop();
    _speechToText.cancel();
    _obstaclePlayer.dispose();
    _personPlayer.dispose();
    _textPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF2561FA),
        foregroundColor: Colors.white,
        title: const Text('Live Detection'),
      ),
      body: GestureDetector(
        onPanStart: _onPanStart,
        onPanEnd: _onPanEnd,
        child: Column(
          children: [
            Expanded(
              flex: 3,
              child: Stack(
                children: [
                  // Camera Preview
                  _isCameraInitialized
                      ? CameraPreview(_cameraController!)
                      : const Center(child: CircularProgressIndicator()),

                  // Voice command indicator
                  if (_isListening)
                    Positioned(
                      top: 20,
                      right: 20,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.mic, color: Colors.white),
                            SizedBox(width: 8),
                            Text('Listening...', style: TextStyle(color: Colors.white)),
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
                padding: const EdgeInsets.all(16.0),
                width: double.infinity,
                color: Colors.black87,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Analysis Result:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Colors.white,
                            ),
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(
                                  _continuousMode ? Icons.loop : Icons.sync_disabled,
                                  color: Colors.white,
                                ),
                                onPressed: _toggleContinuousMode,
                                tooltip: _continuousMode ? 'Continuous Mode On' : 'Continuous Mode Off',
                              ),
                              IconButton(
                                icon: Icon(
                                  _voiceCommandsEnabled ? Icons.mic : Icons.mic_off,
                                  color: Colors.white,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _voiceCommandsEnabled = !_voiceCommandsEnabled;
                                    if (_voiceCommandsEnabled) {
                                      _startVoiceCommandListener();
                                      _speak("Voice commands enabled");
                                    } else {
                                      _voiceCommandsTimer?.cancel();
                                      _speechToText.cancel();
                                      _speak("Voice commands disabled");
                                    }
                                  });
                                },
                                tooltip: _voiceCommandsEnabled ? 'Voice Commands On' : 'Voice Commands Off',
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _detectionResult,
                        style: const TextStyle(fontSize: 16, color: Colors.white),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton(
                            onPressed: _isDetecting ? null : _captureAndAnalyzeFrame,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2561FA),
                              foregroundColor: Colors.white,
                            ),
                            child: Text(_isDetecting ? 'Analyzing...' : 'Analyze Now'),
                          ),
                          ElevatedButton(
                            onPressed: _isSpeaking ? null : () => _speak(_detectionResult),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2561FA),
                              foregroundColor: Colors.white,
                            ),
                            child: Text(_isSpeaking ? 'Speaking...' : 'Read Aloud'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _audioFeedbackEnabled = !_audioFeedbackEnabled;
                              });
                              _speak(_audioFeedbackEnabled
                                  ? "Audio feedback enabled"
                                  : "Audio feedback disabled");
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _audioFeedbackEnabled
                                  ? const Color(0xFF2561FA)
                                  : Colors.grey,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Audio Cues'),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _hapticFeedbackEnabled = !_hapticFeedbackEnabled;
                              });

                              _speak(_hapticFeedbackEnabled
                                  ? "Haptic feedback enabled"
                                  : "Haptic feedback disabled");

                              // Provide a test vibration
                              if (_hapticFeedbackEnabled) {
                                Vibration.vibrate(duration: 300);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _hapticFeedbackEnabled
                                  ? const Color(0xFF2561FA)
                                  : Colors.grey,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Haptic Feedback'),
                          ),
                        ],
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
}