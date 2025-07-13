import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:just_audio/just_audio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import '../../navigationModule/navigation_page.dart';

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
  List<String> _fileNames = [];

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
    String guide = "Welcome to the saved audio page. ";
    if (_fileNames.isNotEmpty) {
      guide += "You have the following saved audio files: ";
      for (final name in _fileNames) {
        guide += "$name. ";
      }
    } else {
      guide += "You have no saved audio files. ";
    }
    guide += "Swipe left to go back. Swipe right to go to the main menu. Swipe up to play an audio file by voice command. Swipe down to read a transcript by voice command.";
    await flutterTts.speak(guide);
  }

  Future<void> _handleVoicePlay() async {
    await flutterTts.speak("Say the name of the audio file you want to play.");
    // Integrate your voice command logic here
  }

  Future<void> _handleVoiceTranscript() async {
    await flutterTts.speak("Say the name of the audio file to read its transcript.");
    // Integrate your voice command logic here
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
      ),
      body: StreamBuilder<QuerySnapshot>(
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
            return const Center(child: Text('No saved audio found.'));
          }
          final docs = snapshot.data!.docs;
          _fileNames = docs.map<String>((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['file_name']?.toString() ?? data['file_path']?.toString() ?? 'Unknown';
          }).toList();
          // Re-speak guide with updated file names
          WidgetsBinding.instance.addPostFrameCallback((_) => _speakGuide());
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragEnd: (details) async {
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
            onVerticalDragEnd: (details) async {
              if (details.primaryVelocity != null) {
                if (details.primaryVelocity! < 0) {
                  // Swipe up: play audio by voice command
                  await _handleVoicePlay();
                } else if (details.primaryVelocity! > 0) {
                  // Swipe down: read transcript by voice command
                  await _handleVoiceTranscript();
                }
              }
            },
            child: ListView.builder(
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data() as Map<String, dynamic>;
                final fileName = data['file_name'] ?? data['file_path'] ?? 'Unknown';
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
                    itemBuilder: (context) => [
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
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: Text(
                          transcript,
                          style: const TextStyle(fontSize: 16, color: Colors.black87),
                        ),
                      ),
                    if (transcript.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: Text('No transcript available.'),
                      ),
                    if (data['audio_url'] != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: AudioPlayerWidget(audioUrl: data['audio_url']),
                      ),
                  ],
                );
              },
            ),
          );
        },
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