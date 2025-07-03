import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:just_audio/just_audio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SavedAudioPage extends StatelessWidget {
  const SavedAudioPage({super.key});

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
          return ListView.builder(
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
  late AudioPlayer _player;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _player.playerStateStream.listen((state) {
      setState(() {
        _isPlaying = state.playing;
      });
    });
    _player.processingStateStream.listen((processingState) {
      if (processingState == ProcessingState.completed) {
        setState(() {
          _isPlaying = false;
        });
        _player.seek(Duration.zero); // Reset to start
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    try {
      print('Audio URL: ${widget.audioUrl}');
      await _player.setUrl(widget.audioUrl);
      _player.play();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not play audio: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
          onPressed: () {
            if (_isPlaying) {
              _player.stop();
            } else {
              _play();
            }
          },
        ),
        Text(_isPlaying ? 'Playing...' : 'Play'),
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