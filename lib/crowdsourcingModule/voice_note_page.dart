import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:vibration/vibration.dart';

import '../home.dart';
import '../navigationModule/navigation_page.dart';
import '../gesture_recognition_service.dart';
import 'saved_audio.dart';

// Move VoiceNamingDialog and _VoiceNamingDialogState to the very top-level, before VoiceNotePage
class VoiceNamingDialog extends StatefulWidget {
  final FlutterTts flutterTts;
  final SpeechToText speechToText;
  const VoiceNamingDialog({required this.flutterTts, required this.speechToText, super.key});

  @override
  State<VoiceNamingDialog> createState() => _VoiceNamingDialogState();
}

class _VoiceNamingDialogState extends State<VoiceNamingDialog> {
  final TextEditingController controller = TextEditingController();
  bool isListening = false;
  String debugMessage = '';
  String heardWords = '';
  bool hasStarted = false;

  // Remove auto-start from initState
  // @override
  // void initState() {
  //   super.initState();
  //   _startVoiceInput();
  // }

  Future<void> _startVoiceInput() async {
    setState(() {
      isListening = true;
      debugMessage = '';
      heardWords = '';
    });
    await widget.speechToText.stop(); // Ensure previous session is stopped
    bool available = await widget.speechToText.initialize(
      onError: (error) {
        print('[VoiceNamingDialog] onError: $error');
        setState(() {
          isListening = false;
          debugMessage = 'Error: ${error.errorMsg}';
        });
      },
    );
    print('[VoiceNamingDialog] SpeechToText initialized: $available');
    if (!available) {
      setState(() {
        isListening = false;
        debugMessage = 'Speech recognition not available or permission denied.';
      });
      print('[VoiceNamingDialog] Initialization failed');
      return;
    }
    setState(() {
      isListening = true;
      debugMessage = 'Listening for file name...';
    });
    await widget.flutterTts.speak("Please say the file name you want to use.");
    print('[VoiceNamingDialog] TTS prompt spoken');
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) {
      print('[VoiceNamingDialog] Widget not mounted after TTS');
      return;
    }
    await widget.speechToText.stop(); // Stop again just before listening
    print('[VoiceNamingDialog] Stopped before listen');
    try {
      print('[VoiceNamingDialog] Attempting to start speech recognition...');
      await widget.speechToText.listen(
        onResult: (speechResult) async {
          print('[VoiceNamingDialog] onResult: ${speechResult.recognizedWords} (final: ${speechResult.finalResult})');
          setState(() {
            heardWords = speechResult.recognizedWords;
            debugMessage = 'Heard: ${speechResult.recognizedWords} (Confidence: ${speechResult.confidence})';
          });
          if (speechResult.finalResult && speechResult.recognizedWords.isNotEmpty) {
            controller.text = speechResult.recognizedWords;
            setState(() => isListening = false);
            await widget.speechToText.stop();
            if (mounted) Navigator.of(context).pop(controller.text.trim());
          }
        },
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        localeId: 'en_US',
        cancelOnError: false,
        listenMode: ListenMode.confirmation,
      );
      print('[VoiceNamingDialog] Speech recognition started successfully');
      setState(() {
        debugMessage = 'Speech recognition started successfully';
      });
    } catch (e) {
      print('[VoiceNamingDialog] Error starting speech recognition: $e');
      if (!mounted) return;
      setState(() {
        isListening = false;
        debugMessage = 'Error: $e';
      });
      await widget.flutterTts.speak("Error starting speech recognition.");
    }
    // Timeout fallback
    await Future.delayed(const Duration(seconds: 12));
    if (mounted && isListening) {
      setState(() {
        isListening = false;
        if (heardWords.isEmpty) {
          debugMessage = 'No speech recognized.';
        }
      });
      print('[VoiceNamingDialog] Timeout, stopping listen');
      await widget.speechToText.stop();
    }
    print('[VoiceNamingDialog] --- End of _startVoiceInput ---');
  }

  @override
  void dispose() {
    controller.dispose();
    widget.speechToText.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Name your audio file'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'Enter file name'),
            autofocus: false,
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: isListening ? null : _startVoiceInput,
            child: const Text('Start Listening'),
          ),
          const SizedBox(height: 12),
          if (isListening)
            Column(
              children: [
                const Text('Listening...', style: TextStyle(color: Colors.red)),
                if (heardWords.isNotEmpty)
                  Column(
                    children: [
                      const Text('Recognized Words:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          heardWords,
                          style: const TextStyle(fontSize: 20, color: Colors.blue, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          if (debugMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(debugMessage, style: const TextStyle(color: Colors.orange)),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop(controller.text.trim());
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class VoiceNotePage extends StatefulWidget {
  const VoiceNotePage({super.key});

  @override
  State<VoiceNotePage> createState() => _VoiceNotePageState();
}

class _VoiceNotePageState extends State<VoiceNotePage> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  final FlutterTts flutterTts = FlutterTts();
  final SpeechToText _speechToText = SpeechToText();
  final GestureRecognitionService _gestureService = GestureRecognitionService();
  bool _isRecording = false;
  String? _recordedFilePath;
  bool _isUploading = false;
  String? _pendingFileName;
  bool _isListening = false; // For listening indicator

  // TODO: Replace with your actual Google Cloud Speech-to-Text API key
  static const String googleApiKey = 'AIzaSyCnLmkL79qMenl0Sn7N4KN38RSoayv-_Bs';

  Future<String> transcribeAudio(File audioFile) async {
    final bytes = await audioFile.readAsBytes();
    final audioBase64 = base64Encode(bytes);
    final url = 'https://speech.googleapis.com/v1/speech:recognize?key=$googleApiKey';
    final body = jsonEncode({
      "config": {
        "encoding": "LINEAR16", // or "MP3", "OGG_OPUS", etc. depending on your file
        "sampleRateHertz": 44100,
        "languageCode": "en-US" // Change as needed
      },
      "audio": {
        "content": audioBase64
      }
    });
    final response = await http.post(
      Uri.parse(url),
      headers: {"Content-Type": "application/json"},
      body: body,
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final transcript = data['results']?[0]?['alternatives']?[0]?['transcript'] ?? '';
      return transcript;
    } else {
      throw Exception('Failed to transcribe audio: \\n${response.body}');
    }
  }

  Future<String?> uploadAudioToSupabase(File audioFile, String fileName) async {
    final supabase = Supabase.instance.client;
    try {
      final String filePath = 'recordings/$fileName.wav';
      final response = await supabase.storage
          .from('voice-note') // your bucket name
          .upload(filePath, audioFile);

      // If upload is successful, get the public URL
      final publicUrl = supabase.storage
          .from('voice-note')
          .getPublicUrl(filePath);
      return publicUrl;
    } catch (e) {
      print('Upload error: $e');
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _initializeTts();
    _initializeGestureService();
    WidgetsBinding.instance.addPostFrameCallback((_) => _speakGuide());
  }

  Future<void> _initializeTts() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.4);
    await flutterTts.setVolume(1.0);
    await flutterTts.setPitch(1.0);
  }

  Future<void> _initializeGestureService() async {
    try {
      await _gestureService.initialize();
    } catch (e) {
      debugPrint('Error initializing gesture service: $e');
    }
  }

  Future<void> _speakGuide() async {
    debugPrint('Voice Note: Starting speakGuide - allowing navigation announcement to complete first');

    debugPrint('Voice Note: Now stopping all existing announcements');

    // Stop all existing announcements from other pages first
    _gestureService.stopAllAnnouncements();
    await flutterTts.stop();

    // Specifically clear crowdsourcing page announcements since that's likely the source
    _gestureService.clearActiveAnnouncementSource('crowdsourcing_page');

    // Force stop any ongoing speech multiple times to ensure it's stopped
    await Future.delayed(const Duration(milliseconds: 200));
    await flutterTts.stop();
    await Future.delayed(const Duration(milliseconds: 200));
    await flutterTts.stop();

    // Create a temporary TTS instance to force stop any other TTS instances
    final tempTts = FlutterTts();
    await tempTts.stop();
    await tempTts.setLanguage("en-US");
    await tempTts.setSpeechRate(0.4);
    await tempTts.setVolume(1.0);
    await tempTts.setPitch(1.0);

    // One final stop to ensure silence
    await flutterTts.stop();
    await tempTts.stop();

    // Check if widget is still mounted before proceeding
    if (!mounted) {
      debugPrint('Voice Note: Widget no longer mounted, stopping speakGuide');
      return;
    }

    debugPrint('Voice Note: Starting welcome message');
    await flutterTts.speak(
        "Welcome to the voice note page. Swipe up to start recording. While recording, swipe up again to stop. Swipe down to go to the saved audio page. Swipe left to go back. Swipe right to go to the main menu. After recording, hold anywhere in screen to start voice input for naming audio or use manual input."
    );
  }

  Future<void> _startRecording({int maxSeconds = 59}) async {
    await flutterTts.stop();

    if (await _audioRecorder.hasPermission()) {
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/${const Uuid().v4()}.wav';

      await _audioRecorder.start(
        RecordConfig(
          encoder: AudioEncoder.wav,
          bitRate: 64000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: filePath,
      );

      setState(() {
        _isRecording = true;
        _recordedFilePath = filePath;
      });

      // 👇 Auto stop after maxSeconds
      Future.delayed(Duration(seconds: maxSeconds), () async {
        if (_isRecording) {
          await _stopRecording(); // let stopRecording handle prompt
        }
      });
    }
  }


  Future<void> _stopRecording() async {
    final path = await _audioRecorder.stop();
    setState(() {
      _isRecording = false;
      _recordedFilePath = path;
    });
    if (path != null) {
      await Future.delayed(const Duration(seconds: 1)); // Ensure mic is released
      await _promptAndTranscribe(File(path));
    }
  }

  Future<void> _promptAndTranscribe(File audioFile) async {
    String? fileName = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        String dialogHeardWords = '';
        String dialogDebug = '';
        bool dialogListening = false;
        final controller = TextEditingController();
        return StatefulBuilder(
          builder: (context, setStateDialog) => GestureDetector(
            behavior: HitTestBehavior.opaque, // Allow gesture on the whole dialog area
            onLongPress: dialogListening
                ? null
                : () async {
              await flutterTts.speak("Listening for file name.");
              setStateDialog(() {
                dialogListening = true;
                dialogHeardWords = '';
                dialogDebug = '';
              });
              await _speechToText.stop(); // Ensure previous session is stopped
              bool available = await _speechToText.initialize(
                onError: (error) {
                  setStateDialog(() {
                    dialogListening = false;
                    dialogDebug = 'Error: ${error.errorMsg}';
                  });
                },
              );
              if (!available) {
                setStateDialog(() {
                  dialogListening = false;
                  dialogDebug = 'Speech recognition not available or permission denied.';
                });
                return;
              }
              setStateDialog(() {
                dialogListening = true;
                dialogDebug = 'Listening for file name...';
              });
              await Future.delayed(const Duration(seconds: 1));
              if (!mounted) return;
              await _speechToText.stop(); // Stop again just before listening
              try {
                await _speechToText.listen(
                  onResult: (speechResult) async {
                    setStateDialog(() {
                      dialogHeardWords = speechResult.recognizedWords;
                      controller.text = speechResult.recognizedWords;
                      dialogDebug = 'Heard: ${speechResult.recognizedWords} (Confidence: ${speechResult.confidence})';
                    });
                    if (speechResult.finalResult && speechResult.recognizedWords.isNotEmpty) {
                      // Vibrate when speech is detected
                      Vibration.hasVibrator().then((hasVibrator) {
                        if (hasVibrator ?? false) {
                          Vibration.vibrate(duration: 100);
                        }
                      });
                      // Auto-save and close dialog with recognized name
                      Navigator.of(context).pop(speechResult.recognizedWords);
                    }
                  },
                  listenFor: const Duration(seconds: 10),
                  pauseFor: const Duration(seconds: 3),
                  partialResults: true,
                  localeId: 'en_US',
                  cancelOnError: false,
                  listenMode: ListenMode.confirmation,
                );
              } catch (e) {
                setStateDialog(() {
                  dialogListening = false;
                  dialogDebug = 'Error: $e';
                });
              }
              // Timeout fallback
              await Future.delayed(const Duration(seconds: 12));
              if (mounted && dialogListening) {
                setStateDialog(() {
                  dialogListening = false;
                  if (dialogHeardWords.isEmpty) {
                    dialogDebug = 'No speech recognized.';
                    // Speak "try again" when no speech is recognized
                    flutterTts.speak("Try again");
                  }
                });
                await _speechToText.stop();
              }
            },
            child: AlertDialog(
              title: const Text('Name your audio file'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(hintText: 'Enter file name'),
                    autofocus: false,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Hold anywhere on this screen to start naming your audio by voice.',
                    style: TextStyle(fontSize: 16, color: Colors.black54),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  if (dialogListening)
                    Column(
                      children: [
                        const Text('Listening...', style: TextStyle(color: Colors.red)),
                        if (dialogHeardWords.isNotEmpty)
                          Column(
                            children: [
                              const Text('Recognized Words:', style: TextStyle(fontWeight: FontWeight.bold)),
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8.0),
                                child: Text(
                                  dialogHeardWords,
                                  style: const TextStyle(fontSize: 20, color: Colors.blue, fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  if (dialogDebug.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(dialogDebug, style: const TextStyle(color: Colors.orange)),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop(controller.text.trim());
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (fileName != null && fileName.isNotEmpty) {
      await _transcribeAndSave(audioFile, fileName);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Audio not saved: file name required.')));
    }
  }

  Future<void> _transcribeAndSave(File audioFile, String fileName) async {
    setState(() {
      _isUploading = true;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User not logged in')));
        return;
      }
      final transcript = await transcribeAudio(audioFile);
      final audioUrl = await uploadAudioToSupabase(audioFile, fileName);
      if (audioUrl != null) {
        await FirebaseFirestore.instance.collection('voice_notes').add({
          'email': user.email,
          'file_name': fileName,
          'audio_url': audioUrl, // Save the URL
          'transcript': transcript,
          'created_at': FieldValue.serverTimestamp(),
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transcript and audio saved!')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Audio upload failed.')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }



  @override
  void dispose() {
    _audioRecorder.dispose();
    flutterTts.stop(); // Stop any ongoing TTS
    _gestureService.stopAllAnnouncements(); // Stop all announcements
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            backgroundColor: const Color(0xFF2561FA),
            foregroundColor: Colors.white,
            title: const Text('Voice Note'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () async {
                await flutterTts.stop();
                await Future.delayed(const Duration(milliseconds: 200));
                await flutterTts.speak("Going back");
                await Future.delayed(const Duration(milliseconds: 1500));
                await Vibration.vibrate(duration: 100);
                Navigator.pop(context);
              },
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.library_music),
                tooltip: 'Saved Audio',
                onPressed: () async {
                  await flutterTts.stop();
                  await Future.delayed(const Duration(milliseconds: 200));
                  await flutterTts.speak("Opening saved audio page");
                  await Future.delayed(const Duration(milliseconds: 2000));
                  await Vibration.vibrate(duration: 100);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SavedAudioPage()),
                  );
                },
              ),

            ],
          ),
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragEnd: (details) async {
              if (details.primaryVelocity != null) {
                if (details.primaryVelocity! < 0) {
                  // Swipe up
                  if (!_isRecording && !_isUploading) {
                    await _startRecording();
                  } else if (_isRecording && !_isUploading) {
                    await _stopRecording();
                  }
                  // If not recording and uploading, do nothing
                } else if (details.primaryVelocity! > 0) {
                  // Swipe down
                  if (!_isRecording) {
                    await flutterTts.stop();
                    await Future.delayed(const Duration(milliseconds: 200));
                    await flutterTts.speak("Opening saved audio page");
                    await Future.delayed(const Duration(milliseconds: 2000));
                    await Vibration.vibrate(duration: 100);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const SavedAudioPage()),
                    );
                  }
                  // If recording, do nothing (block)
                }
              }
            },
            onHorizontalDragEnd: (details) async {
              if (_isRecording) return; // Block all horizontal gestures while recording
              if (details.primaryVelocity != null) {
                if (details.primaryVelocity! < 0) {
                  // Swipe left (right-to-left): go back
                  await flutterTts.stop();
                  await Future.delayed(const Duration(milliseconds: 200));
                  await flutterTts.speak("Going back");
                  await Future.delayed(const Duration(milliseconds: 1500));
                  await Vibration.vibrate(duration: 100);
                  Navigator.pop(context);
                } else if (details.primaryVelocity! > 0) {
                  // Swipe right (left-to-right): go to main menu
                  await flutterTts.stop();
                  await Future.delayed(const Duration(milliseconds: 200));
                  await flutterTts.speak("Going to main menu");
                  await Future.delayed(const Duration(milliseconds: 2500));
                  await Vibration.vibrate(duration: 100);
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => HomeScreen()),
                        (route) => false,
                  );
                }
              }
            },
            // Block long press and other gestures while recording
            onLongPress: _isRecording ? null : null,
            child: Center(
              child: _isUploading
                  ? const CircularProgressIndicator()
                  : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isRecording ? Icons.mic : Icons.mic_none,
                    size: 80,
                    color: _isRecording ? Colors.red : Colors.grey,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _isRecording ? 'Recording...' : 'Swipe up to start recording',
                    style: const TextStyle(fontSize: 20),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Listening indicator overlay at the bottom
        if (_isListening)
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.9),
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.mic,
                        color: Colors.red,
                        size: 8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Listening... Speak now',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}