import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fyp/home.dart';
import 'package:just_audio/just_audio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:vibration/vibration.dart';

// Global audio player manager to ensure only one recording plays at a time
class AudioPlayerManager {
  static final AudioPlayerManager _instance = AudioPlayerManager._internal();
  factory AudioPlayerManager() => _instance;
  AudioPlayerManager._internal();

  final AudioPlayer _player = AudioPlayer();
  String? _currentPlayingId;

  // List to store all widget state setters
  final List<Function()> _stateSetters = [];

  AudioPlayer get player => _player;
  String? get currentPlayingId => _currentPlayingId;

  // Method to register a widget's setState function
  void _registerStateSetter(Function() setState) {
    _stateSetters.add(setState);
  }

  // Method to unregister a widget's setState function
  void _unregisterStateSetter(Function() setState) {
    _stateSetters.remove(setState);
  }

  // Method to notify all widgets to rebuild
  void _notifyStateChange() {
    for (final setState in _stateSetters) {
      setState();
    }
  }

  Future<void> playAudio(String audioUrl, String widgetId) async {
    // Stop current audio if playing
    if (_currentPlayingId != null && _currentPlayingId != widgetId) {
      await _player.stop();
    }

    try {
      await _player.setUrl(audioUrl);
      // Set loop mode to repeat the audio
      await _player.setLoopMode(LoopMode.one);
      await _player.play();
      _currentPlayingId = widgetId;
    } catch (e) {
      print('Error playing audio: $e');
      _currentPlayingId = null;
    }
  }

  void clearCurrentPlayingId() {
    _currentPlayingId = null;
  }

  Future<void> stopAudio() async {
    await _player.stop();
    _currentPlayingId = null;
    // Reset loop mode when stopping
    await _player.setLoopMode(LoopMode.off);
  }

  void dispose() {
    _player.dispose();
  }
}

class SavedAudioPage extends StatefulWidget {
  const SavedAudioPage({super.key});

  @override
  State<SavedAudioPage> createState() => _SavedAudioPageState();
}

class _SavedAudioPageState extends State<SavedAudioPage> {
  final FlutterTts flutterTts = FlutterTts();
  final SpeechToText _speechToText = SpeechToText();
  List<String> _fileNames = [];
  List<Map<String, dynamic>> _audioData = [];
  bool _speechEnabled = false;
  bool _isListening = false;
  String _debugMessage = '';
  bool _hasSpokenWelcome = false;
  Map<String, dynamic>? _lastPlayedAudioData; // Track last played audio

  @override
  void initState() {
    super.initState();
    _initializeTts();
    _initializeSpeech();
  }

  Future<void> _initializeTts() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.35);
    await flutterTts.setVolume(1.0);
    await flutterTts.setPitch(1.0);
  }

  @override
  void dispose() {
    flutterTts.stop();
    _speechToText.stop();
    super.dispose();
  }

  Future<void> _speakCompleteWelcome() async {
    if (!mounted) return;
    await flutterTts.stop();
    if (!mounted) return;

    // Build the complete welcome message as one string
    StringBuffer completeMessage = StringBuffer();
    completeMessage.write("Welcome to the saved audio page. ");

    if (_fileNames.isNotEmpty) {
      completeMessage.write("You have ");
      completeMessage.write(_fileNames.length);
      completeMessage.write(" saved audio files. ");
      // Add each file name with pauses
      for (int i = 0; i < _fileNames.length; i++) {
        completeMessage.write("File ");
        completeMessage.write(i + 1);
        completeMessage.write(": ");
        completeMessage.write(_fileNames[i]);
        completeMessage.write(". ");
      }
    } else {
      completeMessage.write("You have no saved audio files. ");
    }

    completeMessage.write(
        "To play an audio file and read its transcript, press and hold anywhere on the screen until you hear a prompt, then say the file name. Swipe left to go back. Swipe right to go to the main menu."
    );

    // Speak the complete message as one output
    if (!mounted) return;
    await flutterTts.speak(completeMessage.toString());
  }

  Future<void> _speakEmptyStateWelcome() async {
    if (!mounted) return;
    await flutterTts.stop();
    if (!mounted) return;

    await Future.delayed(const Duration(milliseconds: 300));
    await flutterTts.speak(
        "Welcome to the saved audio page. You have no saved audio files. To add audio files, go to the voice note page and record new audio. Swipe left to go back. Swipe right to go to the main menu."
    );
  }

  Future<void> _initializeSpeech() async {
    print('Initializing speech recognition...');
    setState(() {
      _debugMessage = 'Initializing speech recognition...';
    });

    try {
      _speechEnabled = await _speechToText.initialize();
      print('Speech recognition initialized: $_speechEnabled');
      setState(() {
        _debugMessage = 'Speech initialized: $_speechEnabled';
      });

      // Check if we can access the microphone
      if (_speechEnabled) {
        bool hasPermission = await _speechToText.hasPermission;
        print('Microphone permission: $hasPermission');
        setState(() {
          _debugMessage = 'Speech: $_speechEnabled, Permission: $hasPermission';
        });
      }
    } catch (e) {
      print('Error initializing speech: $e');
      setState(() {
        _debugMessage = 'Speech init error: $e';
      });
    }
  }

  Future<void> _handleVoiceCommand() async {
    if (!mounted) return;

    // Stop any ongoing TTS
    await flutterTts.stop();
    if (!mounted) return;

    // Clear any existing debug messages
    setState(() {
      _debugMessage = 'Voice command activated';
    });

    await flutterTts.speak("Say the name of the audio file you want to play and read transcript.");
    await Future.delayed(const Duration(seconds: 5));
    if (!mounted) return;
    await _startListening('combined');
  }

  Future<void> _startListening(String action) async {
    print('Starting speech recognition...');
    setState(() {
      _debugMessage = 'Starting speech recognition...';
    });

    if (!_speechEnabled) {
      print('Speech recognition not enabled');
      setState(() {
        _debugMessage = 'Speech recognition not enabled';
      });
      if (!mounted) return;
      await flutterTts.speak("Speech recognition is not available.");
      return;
    }

    if (!mounted) return;
    setState(() {
      _isListening = true;
      _debugMessage = 'Listening for voice command...';
    });

    // Audio feedback that listening has started
    if (!mounted) return;
    await flutterTts.speak("Listening...");

    try {
      print('Attempting to start speech recognition...');
      setState(() {
        _debugMessage = 'Starting speech recognition...';
      });

      await _speechToText.listen(
        onResult: (result) {
          print('Speech result received: ${result.recognizedWords}');
          print('Confidence: ${result.confidence}');
          print('Final result: ${result.finalResult}');
          setState(() {
            _debugMessage = 'Heard: "${result.recognizedWords}" (Confidence: ${result.confidence})';
          });
          if (result.finalResult) {
            _processVoiceCommand(result.recognizedWords, action);
          }
        },

        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        localeId: 'en_US',
        cancelOnError: false,
        listenMode: ListenMode.confirmation,
      );
      print('Speech recognition started successfully');
      setState(() {
        _debugMessage = 'Speech recognition started successfully';
      });
    } catch (e) {
      print('Error starting speech recognition: $e');
      if (!mounted) return;
      setState(() {
        _isListening = false;
        _debugMessage = 'Error: $e';
      });
      await flutterTts.speak("Error starting speech recognition.");
    }
  }

  Future<void> _processVoiceCommand(String command, String action) async {
    print('Processing voice command: "$command" for action: $action');
    if (!mounted) return;
    setState(() {
      _isListening = false;
      _debugMessage = 'Processing: "$command"';
    });

    // Stop listening
    await _speechToText.stop();

    if (command.isEmpty) {
      print('Empty command received');
      setState(() {
        _debugMessage = 'No command recognized';
      });
      if (!mounted) return;
      await flutterTts.speak("No command recognized. Please try again.");
      return;
    }

    // Handle replay command
    if (command.trim().toLowerCase() == 'replay') {
      if (_lastPlayedAudioData != null) {
        await speakAndWait("Replaying last audio and transcript.");
        await Future.delayed(const Duration(seconds: 1));
        await _playAudioAndReadTranscript(_lastPlayedAudioData!, skipIntro: false);
      } else {
        await speakAndWait("No audio has been played yet to replay.");
      }
      return;
    }

    // Find the best matching file name
    String? bestMatch = _findBestMatch(command.toLowerCase());
    print('Best match found: $bestMatch');

    if (bestMatch == null) {
      print('No matching file found for: $command');
      setState(() {
        _debugMessage = 'No matching file found for: $command';
      });
      if (!mounted) return;
      await flutterTts.speak("No matching audio file found. Please try again.");
      return;
    }

    // Find the corresponding audio data
    Map<String, dynamic>? audioData = _audioData.firstWhere(
          (data) => (data['file_name'] ?? data['file_path'] ?? '').toString() == bestMatch,
      orElse: () => {},
    );

    if (audioData.isEmpty) {
      print('Audio data not found for: $bestMatch');
      setState(() {
        _debugMessage = 'Audio data not found';
      });
      if (!mounted) return;
      await flutterTts.speak("Audio file data not found.");
      return;
    }

    // Save as last played
    _lastPlayedAudioData = audioData;

    print('Found audio data, processing action: $action');
    setState(() {
      _debugMessage = 'Found file: $bestMatch, processing...';
    });

    if (action == 'combined') {
      await speakAndWait("File found.");
      await speakAndWait("Playing audio and reading transcript for: ${audioData['file_name'] ?? audioData['file_path']}");
      await Future.delayed(const Duration(seconds: 2));
      await _playAudioAndReadTranscript(audioData, skipIntro: true);
    } else if (action == 'play') {
      await _playAudioFile(audioData);
    } else if (action == 'transcript') {
      await _readTranscript(audioData);
    }
  }

  String? _findBestMatch(String command) {
    if (_fileNames.isEmpty) return null;

    print('Looking for match for: "$command"');
    print('Available files: $_fileNames');

    // First try exact match
    for (String fileName in _fileNames) {
      if (fileName.toLowerCase() == command.toLowerCase()) {
        print('Exact match found: $fileName');
        return fileName;
      }
    }

    // Try partial match (more flexible)
    for (String fileName in _fileNames) {
      String lowerFileName = fileName.toLowerCase();
      String lowerCommand = command.toLowerCase();

      if (lowerFileName.contains(lowerCommand) || lowerCommand.contains(lowerFileName)) {
        print('Partial match found: $fileName');
        return fileName;
      }
    }

    // Try word-by-word matching (even more flexible)
    List<String> commandWords = command.toLowerCase().split(' ').where((word) => word.length > 2).toList();
    print('Command words: $commandWords');

    for (String fileName in _fileNames) {
      List<String> fileNameWords = fileName.toLowerCase().split(' ').where((word) => word.length > 2).toList();
      print('File words: $fileNameWords');

      int matchCount = 0;
      for (String word in commandWords) {
        for (String fileNameWord in fileNameWords) {
          if (fileNameWord.contains(word) || word.contains(fileNameWord)) {
            matchCount++;
            print('Word match: "$word" matches "$fileNameWord"');
          }
        }
      }

      double matchPercentage = commandWords.isEmpty ? 0 : matchCount / commandWords.length;
      print('Match percentage for $fileName: $matchPercentage');

      if (matchPercentage >= 0.3) { // Lowered threshold to 30%
        print('Word match found: $fileName');
        return fileName;
      }
    }

    print('No match found');
    return null;
  }

  Future<void> _playAudioFile(Map<String, dynamic> audioData) async {
    if (!mounted) return;
    await flutterTts.speak("Playing audio file: ${audioData['file_name'] ?? audioData['file_path']}");

    // Create a temporary AudioPlayerWidget to play the audio
    if (audioData['audio_url'] != null) {
      try {
        final player = AudioPlayer();
        await player.setUrl(audioData['audio_url']);
        await player.play();

        // Stop after the audio finishes
        player.playerStateStream.listen((state) {
          if (state.processingState == ProcessingState.completed) {
            player.dispose();
          }
        });
      } catch (e) {
        if (!mounted) return;
        await flutterTts.speak("Error playing audio file.");
      }
    } else {
      if (!mounted) return;
      await flutterTts.speak("No audio URL available for this file.");
    }
  }

  Future<void> _playAudioAndReadTranscript(Map<String, dynamic> audioData, {bool skipIntro = false}) async {
    if (!mounted) return;
    _lastPlayedAudioData = audioData;
    if (!skipIntro) {
      await speakAndWait("Playing audio and reading transcript for: "+
          "${audioData['file_name'] ?? audioData['file_path']}");
    }
    // Play the audio first
    if (audioData['audio_url'] != null) {
      try {
        final player = AudioPlayer();
        await player.setUrl(audioData['audio_url']);
        await player.play();
        // Wait for audio to finish
        await player.playerStateStream
            .firstWhere((state) => state.processingState == ProcessingState.completed);
        await player.dispose();

        // Read transcript after audio finishes
        if (!mounted) return;
        String transcript = audioData['transcript'] ?? '';
        if (transcript.isEmpty) {
          if (!mounted) return;
          await speakAndWait("Audio finished. No transcript available for this file.");
        } else {
          if (!mounted) return;
          await speakAndWait("Audio finished. Now reading transcript.");
          await Future.delayed(const Duration(seconds: 1));
          if (!mounted) return;
          await flutterTts.speak(transcript);
        }
      } catch (e) {
        if (!mounted) return;
        await speakAndWait("Error playing audio file.");
      }
    } else {
      if (!mounted) return;
      await speakAndWait("No audio URL available for this file.");
    }
  }

  Future<void> _readTranscript(Map<String, dynamic> audioData) async {
    String transcript = audioData['transcript'] ?? '';

    if (transcript.isEmpty) {
      if (!mounted) return;
      await flutterTts.speak("No transcript available for this audio file.");
      return;
    }

    if (!mounted) return;
    await flutterTts.speak("Reading transcript for: ${audioData['file_name'] ?? audioData['file_path']}");
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    await flutterTts.speak(transcript);
  }

  Future<void> _renameFile(BuildContext context, String docId, String currentName) async {
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Audio File'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Enter new file name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty && newName != currentName) {
      final success = await renameAudioFile(
        oldFileName: currentName,
        newFileName: newName,
        docId: docId,
      );
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File renamed.')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rename failed.')));
      }
    }
  }

  Future<void> _deleteFile(BuildContext context, String docId, String fileName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Audio File'),
        content: const Text('Are you sure you want to delete this audio entry?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final success = await deleteAudioFile(
        fileName: fileName,
        docId: docId,
      );
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File deleted.')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Delete failed.')));
      }
    }
  }

  // Place speakAndWait as a method of _SavedAudioPageState
  Future<void> speakAndWait(String text) async {
    final completer = Completer<void>();
    flutterTts.setCompletionHandler(() {
      if (!completer.isCompleted) completer.complete();
    });
    await flutterTts.speak(text);
    await completer.future;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF2561FA),
          foregroundColor: Colors.white,
          title: const Text('Saved Audio'),
        ),
        body: const Center(child: Text('User not logged in.')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF2561FA),
        foregroundColor: Colors.white,
        title: const Text('Saved Audio'),
        actions: [

        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (details) async {
          print('Horizontal drag detected with velocity: ${details.primaryVelocity}');
          if (details.primaryVelocity != null) {
            if (details.primaryVelocity! < 0) {
              // Swipe left (right-to-left): go back
              print('Swipe left detected - going back');
              await flutterTts.stop();
              await Future.delayed(const Duration(milliseconds: 200));
              await flutterTts.speak("Going back");
              await Future.delayed(const Duration(milliseconds: 1500));
              await Vibration.vibrate(duration: 100);
              Navigator.pop(context);
            } else if (details.primaryVelocity! > 0) {
              // Swipe right (left-to-right): go to main menu
              print('Swipe right detected - going to main menu');
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
        onLongPress: () async {
          print('Long press detected - handling voice command');
          await _handleVoiceCommand();
        },
        child: Stack(
          children: [
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('voice_notes')
                  .where('email', isEqualTo: user.email)
                  .orderBy('created_at', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  // Speak welcome message for empty state
                  if (!_hasSpokenWelcome) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _speakEmptyStateWelcome();
                      _hasSpokenWelcome = true;
                    });
                  }
                  return Container(
                    width: double.infinity,
                    height: double.infinity,
                    color: Colors.transparent,
                    child: const Center(child: Text('No saved audio found.')),
                  );
                }
                final docs = snapshot.data!.docs;
                _fileNames = docs.map<String>((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return data['file_name']?.toString() ?? data['file_path']?.toString() ??
                      'Unknown';
                }).toList();
                _audioData = docs.map<Map<String, dynamic>>((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return data;
                }).toList();
                // Speak welcome message only once after data is loaded
                if (!_hasSpokenWelcome) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _speakCompleteWelcome();
                    _hasSpokenWelcome = true;
                  });
                }
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final fileName = data['file_name'] ?? data['file_path'] ??
                        'Unknown';
                    final transcript = data['transcript'] ?? '';
                    final createdAt = (data['created_at'] as Timestamp?)?.toDate();
                    return ExpansionTile(
                      leading: const Icon(Icons.audiotrack, color: Color(0xFF2561FA)),
                      title: Text(fileName),
                      subtitle: createdAt != null
                          ? Text('Created: ${createdAt.toLocal()}')
                          : null,
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value == 'rename') {
                            await _renameFile(context, doc.id, fileName);
                          } else if (value == 'delete') {
                            await _deleteFile(context, doc.id, fileName);
                          }
                        },
                        itemBuilder: (context) =>
                        [
                          const PopupMenuItem(
                            value: 'rename',
                            child: Text('Rename'),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete'),
                          ),
                        ],
                      ),
                      children: [
                        if (transcript.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16.0, vertical: 8.0),
                            child: Text(
                              transcript,
                              style: const TextStyle(fontSize: 16, color: Colors
                                  .black87),
                            ),
                          ),
                        if (transcript.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 16.0, vertical: 8.0),
                            child: Text('No transcript available.'),
                          ),
                        if (data['audio_url'] != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16.0, vertical: 8.0),
                            child: AudioPlayerWidget(audioUrl: data['audio_url']),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
            // Remove the status bar and debug overlay
            // Only show the listening indicator at the bottom when listening
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
        ),
      ),
    );
  }
}

class AudioPlayerWidget extends StatefulWidget {
  final String audioUrl;
  const AudioPlayerWidget({super.key, required this.audioUrl});

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  final AudioPlayerManager _audioManager = AudioPlayerManager();
  late String _widgetId;

  @override
  void initState() {
    super.initState();
    _widgetId = DateTime.now().millisecondsSinceEpoch.toString();

    // Register this widget's setState function
    _audioManager._registerStateSetter(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    // Unregister this widget's setState function
    _audioManager._unregisterStateSetter(() {
      if (mounted) {
        setState(() {});
      }
    });
    super.dispose();
  }

  Future<void> _play() async {
    // Immediately update the manager's current playing ID for instant UI feedback
    _audioManager._currentPlayingId = _widgetId;

    // Force all widgets to rebuild by triggering a global rebuild
    _audioManager._notifyStateChange();

    try {
      print('Audio URL: ${widget.audioUrl}');
      await _audioManager.playAudio(widget.audioUrl, _widgetId);
    } catch (e) {
      // Reset if play fails
      _audioManager._currentPlayingId = null;
      _audioManager._notifyStateChange();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not play audio: $e')));
    }
  }

  Future<void> _stop() async {
    // Immediately clear the current playing ID for instant UI feedback
    _audioManager._currentPlayingId = null;

    // Force all widgets to rebuild
    _audioManager._notifyStateChange();

    await _audioManager.stopAudio();
  }

  @override
  Widget build(BuildContext context) {
    final isCurrentlyPlaying = _audioManager.currentPlayingId == _widgetId;

    return Row(
      children: [
        IconButton(
          icon: Icon(isCurrentlyPlaying ? Icons.stop : Icons.play_arrow),
          onPressed: () {
            if (isCurrentlyPlaying) {
              _stop();
            } else {
              _play();
            }
          },
        ),
        Text(isCurrentlyPlaying ? 'Playing...' : 'Play'),
      ],
    );
  }
}

Future<bool> renameAudioFile({
  required String oldFileName,
  required String newFileName,
  required String docId,
}) async {
  final supabase = Supabase.instance.client;
  final oldPath = 'recordings/$oldFileName.wav';
  final newPath = 'recordings/$newFileName.wav';
  try {
    final copyRes = await supabase.storage.from('voice-note').copy(oldPath, newPath);
    print('Supabase copy result: $copyRes');
    final removeRes = await supabase.storage.from('voice-note').remove([oldPath]);
    print('Supabase remove result: $removeRes');
    final newUrl = supabase.storage.from('voice-note').getPublicUrl(newPath);
    await FirebaseFirestore.instance.collection('voice_notes').doc(docId).update({
      'file_name': newFileName,
      'audio_url': newUrl,
    });
    print('Firestore update completed');
    return true;
  } catch (e, stack) {
    print('Rename error: $e');
    print(stack);
    return false;
  }
}

Future<bool> deleteAudioFile({
  required String fileName,
  required String docId,
}) async {
  final supabase = Supabase.instance.client;
  final filePath = 'recordings/$fileName.wav';
  try {
    final removeRes = await supabase.storage.from('voice-note').remove([filePath]);
    print('Supabase remove result: $removeRes');
    await FirebaseFirestore.instance.collection('voice_notes').doc(docId).delete();
    print('Firestore delete completed');
    return true;
  } catch (e, stack) {
    print('Delete error: $e');
    print(stack);
    return false;
  }
}