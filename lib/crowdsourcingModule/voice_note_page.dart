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

import 'saved_audio.dart';

class VoiceNotePage extends StatefulWidget {
  const VoiceNotePage({super.key});

  @override
  State<VoiceNotePage> createState() => _VoiceNotePageState();
}

class _VoiceNotePageState extends State<VoiceNotePage> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  String? _recordedFilePath;
  bool _isUploading = false;
  String? _pendingFileName;

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
  }

  Future<void> _startRecording() async {
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
      await _promptAndTranscribe(File(path));
    }
  }

  Future<void> _promptAndTranscribe(File audioFile) async {
    String? fileName = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Name your audio file'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'Enter file name'),
            autofocus: true,
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
        ],
      ),
      body: Center(
        child: _isUploading
            ? const CircularProgressIndicator()
            : Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isRecording ? Icons.mic : Icons.mic_none,
              size: 100,
              color: _isRecording ? Colors.red : Colors.blue,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isRecording ? _stopRecording : _startRecording,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isRecording ? Colors.red : const Color(0xFF2561FA),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(_isRecording ? 'Stop Recording' : 'Start Recording'),
            ),
          ],
        ),
      ),
    );
  }
}