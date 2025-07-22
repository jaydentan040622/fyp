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

import '../navigationModule/navigation_page.dart';
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
  bool _isRecording = false;
  String? _recordedFilePath;
  bool _isUploading = false;
  String? _pendingFileName;
  bool _isListening = false; // For listening indicator
  String _testHeardWords = '';
  String _testDebug = '';

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _speakGuide());
  }

  Future<void> _initializeTts() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.4);
    await flutterTts.setVolume(1.0);
    await flutterTts.setPitch(1.0);
  }

  Future<void> _speakGuide() async {
    await flutterTts.stop();
    await flutterTts.speak(
        "Welcome to the voice note page. Swipe up to start recording. While recording, swipe up again to stop. Swipe down to go to the saved audio page. Swipe left to go back. Swipe right to go to the main menu. After recording, hold anywhere in screen to start voice input for naming audio or use manual input."
    );
  }

  Future<void> _startRecording() async {
    await flutterTts.stop(); // Stop any ongoing TTS speech
    if (await _audioRecorder.hasPermission()) {
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/${const Uuid().v4()}.wav';
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1, // Ensure mono audio
        ),
        path: filePath,
      );
      setState(() {
        _isRecording = true;
        _recordedFilePath = filePath;
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
              await flutterTts.speak("Listening for file name. Please say the name after the beep.");
              setStateDialog(() {
                dialogListening = true;
                dialogHeardWords = '';
                dialogDebug = '';
              });
              await _testSpeechToText(
                onHeard: (words) async {
                  setStateDialog(() {
                    dialogHeardWords = words;
                    controller.text = words;
                  });
                  // Vibrate when speech is detected
                  if (words.isNotEmpty) {
                    Vibration.hasVibrator().then((hasVibrator) {
                      if (hasVibrator ?? false) {
                        Vibration.vibrate(duration: 100);
                      }
                    });
                    // Auto-save and close dialog with recognized name
                    Navigator.of(context).pop(words);
                  }
                },
                onDebug: (msg) => setStateDialog(() => dialogDebug = msg),
                onListening: (listening) => setStateDialog(() => dialogListening = listening),
              );
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

  Future<String?> _getFileNameByVoice() async {
    bool available = await _speechToText.initialize();
    if (!available) return null;
    await flutterTts.speak("Please say the file name you want to use.");
    await Future.delayed(const Duration(seconds: 1));
    String? result;
    await _speechToText.listen(
      onResult: (speechResult) {
        if (speechResult.finalResult && speechResult.recognizedWords.isNotEmpty) {
          result = speechResult.recognizedWords;
        }
      },
      listenFor: const Duration(seconds: 5),
      pauseFor: const Duration(seconds: 2),
      partialResults: false,
      localeId: 'en_US',
      cancelOnError: true,
      listenMode: ListenMode.confirmation,
    );
    // Wait for speech or timeout
    await Future.delayed(const Duration(seconds: 6));
    await _speechToText.stop();
    return result;
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

  // Add a test function for speech-to-text
  Future<void> _testSpeechToText({
    void Function(String)? onHeard,
    void Function(String)? onDebug,
    void Function(bool)? onListening,
  }) async {
    print('[Test] --- Starting testSpeechToText ---');
    onListening?.call(true);
    onHeard?.call('');
    onDebug?.call('');
    await _speechToText.stop(); // Ensure previous session is stopped
    print('[Test] Stopped any previous session');
    bool available = await _speechToText.initialize(
      onError: (error) {
        print('[Test] onError: $error');
        onListening?.call(false);
        onDebug?.call('Error: ${error.errorMsg}');
      },
    );
    print('[Test] SpeechToText initialized: $available');
    if (!available) {
      onListening?.call(false);
      onDebug?.call('Speech recognition not available or permission denied.');
      print('[Test] Initialization failed');
      return;
    }
    // Simulate the same flow as saved_audio.dart
    onListening?.call(true);
    onDebug?.call('Listening for voice command...');
    print('[Test] Set _isListening true, debug updated');
    await flutterTts.speak("Name your audio file");
    print('[Test] TTS prompt spoken');
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) {
      print('[Test] Widget not mounted after TTS');
      return;
    }
    await _speechToText.stop(); // Stop again just before listening
    print('[Test] Stopped before listen');
    try {
      print('[Test] Attempting to start speech recognition...');
      await _speechToText.listen(
        onResult: (speechResult) async {
          print('[Test] onResult: ${speechResult.recognizedWords} (final: ${speechResult.finalResult})');
          onHeard?.call(speechResult.recognizedWords);
          onDebug?.call('Heard: ${speechResult.recognizedWords} (Confidence: ${speechResult.confidence})');
          if (speechResult.finalResult) {
            onListening?.call(false);
            onDebug?.call('Final result.');
            await _speechToText.stop();
            print('[Test] Final result, stopped listening');
          }
        },
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        localeId: 'en_US',
        cancelOnError: false,
        listenMode: ListenMode.confirmation,
      );
      print('[Test] Speech recognition started successfully');
      onDebug?.call('Speech recognition started successfully');
    } catch (e) {
      print('[Test] Error starting speech recognition: $e');
      if (!mounted) return;
      onListening?.call(false);
      onDebug?.call('Error: $e');
      await flutterTts.speak("Error starting speech recognition.");
    }
    // Timeout fallback
    await Future.delayed(const Duration(seconds: 12));
    onListening?.call(false);
    if (onHeard != null && onDebug != null) {
      if (_testHeardWords.isEmpty) {
        onDebug('No speech recognized.');
      }
    }
    print('[Test] Timeout, stopping listen');
    await _speechToText.stop();
    print('[Test] --- End of testSpeechToText ---');
  }

  @override
  void dispose() {
    _audioRecorder.dispose();
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
            actions: [
              IconButton(
                icon: const Icon(Icons.library_music),
                tooltip: 'Saved Audio',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SavedAudioPage()),
                  );
                },
              ),
              // Add a temporary test button
              IconButton(
                icon: const Icon(Icons.mic),
                tooltip: 'Test Speech-to-Text',
                onPressed: () async {
                  await showDialog(
                    context: context,
                    builder: (context) {
                      String dialogHeardWords = '';
                      String dialogDebug = '';
                      bool dialogListening = false;
                      return StatefulBuilder(
                        builder: (context, setStateDialog) => AlertDialog(
                          title: const Text('Test Speech-to-Text'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ElevatedButton(
                                onPressed: () async {
                                  setStateDialog(() {
                                    dialogListening = true;
                                    dialogHeardWords = '';
                                    dialogDebug = '';
                                  });
                                  await _testSpeechToText(
                                    onHeard: (words) => setStateDialog(() => dialogHeardWords = words),
                                    onDebug: (msg) => setStateDialog(() => dialogDebug = msg),
                                    onListening: (listening) => setStateDialog(() => dialogListening = listening),
                                  );
                                },
                                child: const Text('Start Listening'),
                              ),
                              const SizedBox(height: 12),
                              if (dialogListening)
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
                              if (dialogDebug.isNotEmpty)
                                Text(dialogDebug, style: const TextStyle(color: Colors.orange)),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                  setState(() {
                    _isListening = false;
                    _testHeardWords = '';
                    _testDebug = '';
                  });
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
                  Navigator.pop(context);
                } else if (details.primaryVelocity! > 0) {
                  // Swipe right (left-to-right): go to main menu
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => NavigationPage()),
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