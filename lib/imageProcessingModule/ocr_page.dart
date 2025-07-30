import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../gesture_recognition_service.dart';
import '../home.dart';
import 'package:vibration/vibration.dart';

class OCRPage extends StatefulWidget {
  const OCRPage({super.key});

  @override
  State<OCRPage> createState() => _OCRPageState();
}

class _OCRPageState extends State<OCRPage> {
  final ImagePicker _picker = ImagePicker();
  final FlutterTts _flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _initializeTts();
    WidgetsBinding.instance.addPostFrameCallback((_) => _speakGuide());
  }

  Future<void> _initializeTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.4);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  // Utility to aggressively stop all previous announcements
  Future<void> _aggressiveStopAnnouncements() async {
    final gestureService = GestureRecognitionService();
    await gestureService.initialize();
    gestureService.stopAllAnnouncements();
    gestureService.clearActiveAnnouncementSource('image_processing_page');
    gestureService.clearActiveAnnouncementSource('crowdsourcing_page');
    gestureService.clearActiveAnnouncementSource('voice_note_page');
    await _flutterTts.stop();
    await Future.delayed(const Duration(milliseconds: 200));
    await _flutterTts.stop();
  }

  Future<void> _speakGuide() async {
    await _aggressiveStopAnnouncements();
    await Future.delayed(const Duration(milliseconds: 500)); // Wait for previous speech to stop
    await _flutterTts.speak(
        "Welcome to the OCR Text Recognition page. Swipe up to add photo from gallery. Swipe down to take photo using camera. Swipe left to go back. Swipe right to go to the main menu. You can also tap the buttons to select images."
    );
  }

  Future<void> _pickFromGallery() async {
    await _aggressiveStopAnnouncements();
    await _flutterTts.speak("Opening gallery to select image");
    await Future.delayed(const Duration(milliseconds: 2000));
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      await _aggressiveStopAnnouncements();
      await _flutterTts.speak("Image selected, processing text");
      await Future.delayed(const Duration(milliseconds: 2000));
      // Wait for TTS to finish before processing
      await _processAndNavigate(File(image.path));
    } else {
      await _aggressiveStopAnnouncements();
      await _flutterTts.speak("No image selected");
    }
  }

  Future<void> _takePhoto() async {
    await _aggressiveStopAnnouncements();
    await _flutterTts.speak("Opening camera to take photo");
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      await _aggressiveStopAnnouncements();
      await _flutterTts.speak("Photo taken, processing text");
      // Wait for TTS to finish before processing
      await _processAndNavigate(File(image.path));
    } else {
      await _aggressiveStopAnnouncements();
      await _flutterTts.speak("No photo taken");
    }
  }

  Future<void> _processAndNavigate(File imageFile) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    String extractedText = '';
    final inputImage = InputImage.fromFile(imageFile);
    final textRecognizer = GoogleMlKit.vision.textRecognizer();
    try {
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      // Arrange output paragraph by paragraph (block by block)
      final List<TextBlock> blocks = List<TextBlock>.from(recognizedText.blocks);
      // Sort blocks by top (y)
      blocks.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
      final buffer = StringBuffer();
      for (final block in blocks) {
        // Sort lines in block by top (y), then left (x)
        final lines = List<TextLine>.from(block.lines);
        lines.sort((a, b) {
          final ay = a.boundingBox.top;
          final by = b.boundingBox.top;
          if ((ay - by).abs() < 10) {
            return a.boundingBox.left.compareTo(b.boundingBox.left);
          }
          return ay.compareTo(by);
        });
        for (final line in lines) {
          final elements = List<TextElement>.from(line.elements);
          elements.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
          for (final element in elements) {
            buffer.write(element.text);
            buffer.write(' ');
          }
          buffer.write('\n');
        }
        buffer.write('\n'); // Double newline between paragraphs
      }
      extractedText = buffer.toString().trim();
    } catch (e) {
      extractedText = 'Error recognizing text:  {e.toString()}';
    } finally {
      Navigator.of(context).pop(); // Remove loading dialog
      await Future.delayed(const Duration(milliseconds: 100)); // Let the pop finish
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => OCRResultPage(
              imageFile: imageFile,
              extractedText: extractedText,
            ),
          ),
        );
      }
    }
    if (extractedText.isNotEmpty) {
      await _flutterTts.speak("Text extracted successfully");
    } else {
      await _flutterTts.speak("No text found in image");
    }
  }

  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragEnd: (details) async {
          if (details.primaryVelocity != null) {
            if (details.primaryVelocity! < 0) {
              // Swipe up - add photo from gallery
              await _flutterTts.stop();
              await Future.delayed(const Duration(milliseconds: 200));
              await _pickFromGallery();
            } else if (details.primaryVelocity! > 0) {
              // Swipe down - take photo using camera
              await _flutterTts.stop();
              await Future.delayed(const Duration(milliseconds: 200));
              await _takePhoto();
            }
          }
        },
        onHorizontalDragEnd: (details) async {
          if (details.primaryVelocity != null) {
            if (details.primaryVelocity! < 0) {
              // Swipe left (right-to-left): go back
              await _flutterTts.stop();
              await Future.delayed(const Duration(milliseconds: 200));
              await _flutterTts.speak("Going back");
              await Future.delayed(const Duration(milliseconds: 1500));
              await Vibration.vibrate(duration: 100);
              Navigator.pop(context);
            } else if (details.primaryVelocity! > 0) {
              // Swipe right (left-to-right): go to main menu
              await _flutterTts.stop();
              await Future.delayed(const Duration(milliseconds: 200));
              await _flutterTts.speak("Going to main menu");
              await Future.delayed(const Duration(milliseconds: 1500));
              await Vibration.vibrate(duration: 100);
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => HomeScreen()),
                    (route) => false,
              );
            }
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
                        onPressed: () async {
                          await _flutterTts.speak("Going back");
                          await Future.delayed(const Duration(milliseconds: 1500));
                          await Vibration.vibrate(duration: 100);
                          Navigator.pop(context);
                        },
                      ),
                      const Expanded(
                        child: Text(
                          'OCR',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 48), // For balance
                    ],
                  ),
                ),
              ),
            ),
            // Main content
            Expanded(
              child: Container(
                color: const Color(0xFFF0F4F8), // Light blue-grey background
                child: Center(
                  child: Container(
                    width: 500,
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              await _flutterTts.speak("Gallery button tapped");
                              _pickFromGallery();
                            },
                            child: SizedBox(
                              width: 280,
                              child: Card(
                                elevation: 4,
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color: Colors.blue.shade50,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.photo_library,
                                        size: 80,
                                        color: Colors.blue.shade700,
                                      ),
                                      const SizedBox(height: 16),
                                      const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 20.0),
                                        child: Text(
                                          'Add From Phone Gallery',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF2561FA),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              await _flutterTts.speak("Camera button tapped");
                              _takePhoto();
                            },
                            child: SizedBox(
                              width: 280,
                              child: Card(
                                elevation: 4,
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color: Colors.blue.shade50,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.camera_alt,
                                        size: 80,
                                        color: Colors.blue.shade700,
                                      ),
                                      const SizedBox(height: 16),
                                      const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 20.0),
                                        child: Text(
                                          'Take Photo with Camera',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF2561FA),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
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

class OCRResultPage extends StatefulWidget {
  final File imageFile;
  final String extractedText;

  const OCRResultPage({
    super.key,
    required this.imageFile,
    required this.extractedText,
  });

  @override
  State<OCRResultPage> createState() => _OCRResultPageState();
}

class _OCRResultPageState extends State<OCRResultPage> {
  final FlutterTts _flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _initializeResultPage();
  }

  // OCR Result Page: aggressive stop in init and gesture handlers
  Future<void> _initializeResultPage() async {
    await _aggressiveStopAnnouncements();
    await Future.delayed(const Duration(milliseconds: 500));

    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.4);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    if (widget.extractedText.isNotEmpty) {
      // 1. Speak the success message and wait for it to finish
      await _aggressiveStopAnnouncements();
      await _flutterTts.speak("Text extracted successfully. Reading the recognized text.");
      await Future.delayed(const Duration(milliseconds: 5000));

      // 2. Now read the extracted text
      await _aggressiveStopAnnouncements();
      await _readExtractedText();
    } else {
      await _aggressiveStopAnnouncements();
      await _flutterTts.speak("No text found in the image.");
    }
  }

  Future<void> _readExtractedText() async {
    await _flutterTts.stop();
    await Future.delayed(const Duration(milliseconds: 200));

    // Limit the text to first 1000 characters to avoid very long speech
    String textToRead = widget.extractedText;
    if (textToRead.length > 1000) {
      textToRead = textToRead.substring(0, 1000) + '... Text truncated for speech.';
    }

    // Clean up the text for better speech
    textToRead = _cleanTextForSpeech(textToRead);

    await _flutterTts.speak(textToRead);
  }

  String _cleanTextForSpeech(String text) {
    // Remove excessive whitespace and newlines
    text = text.replaceAll(RegExp(r'\n+'), '. ');
    text = text.replaceAll(RegExp(r'\s+'), ' ');
    text = text.trim();

    // Add pauses for better readability
    text = text.replaceAll('.', '. ');
    text = text.replaceAll('!', '! ');
    text = text.replaceAll('?', '? ');

    return text;
  }

  Future<void> _aggressiveStopAnnouncements() async {
    final gestureService = GestureRecognitionService();
    await gestureService.initialize();
    gestureService.stopAllAnnouncements();
    gestureService.clearActiveAnnouncementSource('image_processing_page');
    gestureService.clearActiveAnnouncementSource('crowdsourcing_page');
    gestureService.clearActiveAnnouncementSource('voice_note_page');
    await _flutterTts.stop();
    await Future.delayed(const Duration(milliseconds: 200));
    await _flutterTts.stop();
  }

  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () async {
          // Long press - read extracted text
          if (widget.extractedText.isNotEmpty) {
            await _aggressiveStopAnnouncements();
            await _flutterTts.speak("Reading extracted text again");
            await _readExtractedText();
          } else {
            await _aggressiveStopAnnouncements();
            await _flutterTts.speak("No text to read");
          }
        },
        onHorizontalDragEnd: (details) async {
          if (details.primaryVelocity != null) {
            if (details.primaryVelocity! < 0) {
              // Swipe left (right-to-left): go back
              await _aggressiveStopAnnouncements();
              await _flutterTts.speak("Going back to OCR page");
              await Future.delayed(const Duration(milliseconds: 2500));
              await Vibration.vibrate(duration: 100);
              Navigator.pop(context);
            } else if (details.primaryVelocity! > 0) {
              // Swipe right (left-to-right): go to main page
              await _aggressiveStopAnnouncements();
              await _flutterTts.speak("Going back to main page");
              await Future.delayed(const Duration(milliseconds: 2500));
              await Vibration.vibrate(duration: 100);
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const HomeScreen()),
                    (route) => false,
              );
            }
          }
        },
        child: Scaffold(
          appBar: AppBar(
            backgroundColor: const Color(0xFF2561FA),
            foregroundColor: Colors.white,
            title: const Text('OCR Result'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () async {
                await _flutterTts.speak("Going back");
                await Future.delayed(const Duration(milliseconds: 1500));
                Navigator.pop(context);
              },
            ),
          ),
          body: SingleChildScrollView(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        widget.imageFile,
                        height: 300,
                        width: null,
                        fit: BoxFit.fitHeight,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      width: 350,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Extracted Text:',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2561FA),
                                ),
                              ),
                              if (widget.extractedText.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.volume_up, color: Color(0xFF2561FA)),
                                  onPressed: _readExtractedText,
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.extractedText.isEmpty ? 'No text detected in the image' : widget.extractedText,
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
} 
