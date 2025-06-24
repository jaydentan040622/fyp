import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

class ChatbotPage extends StatefulWidget {
  const ChatbotPage({super.key});

  @override
  State<ChatbotPage> createState() => _ChatbotPageState();
}

class _ChatbotPageState extends State<ChatbotPage> {
  final TextEditingController _messageController = TextEditingController();
  final List<ChatMessage> _messages = [];
  bool _isTyping = false;
  bool _isListening = false;
  bool _isLoadingHistory = true;
  bool _isExporting = false;
  
//deepseek/deepseek-r1:free
  // final String _apiKey = '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';
  final String _apiKey = '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';

  final String _model = 'deepseek/deepseek-r1:free';

  // Accessibility features
  late FlutterTts _flutterTts;
  late stt.SpeechToText _speech;
  bool _speechEnabled = false;

  // Firebase
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late String _userId;
  final uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _initTts();
    _initFirestore();
  }
  
  // Initialize Firestore and load chat history
  void _initFirestore() async {
    User? currentUser = _auth.currentUser;
    
    if (currentUser != null) {
      _userId = currentUser.uid;
    } else {
      // For users who aren't logged in, use a device ID or anonymous ID
      _userId = 'anonymous-${uuid.v4()}';
    }
    
    // Load chat history
    await _loadChatHistory();
    
    // Add welcome message only if no history exists
    if (_messages.isEmpty) {
      _addAssistantMessage(
        "Hello! I'm your AI assistant. Tap the large microphone button to speak, or type your message below.",
        saveToFirestore: true
      );
    }
  }

  // Load chat history from Firestore
  Future<void> _loadChatHistory() async {
    try {
      setState(() {
        _isLoadingHistory = true;
      });
      
      final snapshot = await _firestore
          .collection('chat_history')
          .doc(_userId)
          .collection('messages')
          .orderBy('timestamp', descending: false)
          .get();
      
      final List<ChatMessage> loadedMessages = [];
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        loadedMessages.add(
          ChatMessage(
            text: data['text'],
            isUser: data['isUser'],
          ),
        );
      }
      
      setState(() {
        _messages.clear();
        _messages.addAll(loadedMessages);
        _isLoadingHistory = false;
      });
    } catch (e) {
      print('Error loading chat history: $e');
      setState(() {
        _isLoadingHistory = false;
      });
    }
  }

  // Save message to Firestore
  Future<void> _saveMessageToFirestore(String text, bool isUser) async {
    try {
      await _firestore
          .collection('chat_history')
          .doc(_userId)
          .collection('messages')
          .add({
        'text': text,
        'isUser': isUser,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error saving message to Firestore: $e');
    }
  }
  
  // Export chat history to a text file and share
  Future<void> _exportChatHistory() async {
    if (_messages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No messages to export')),
      );
      return;
    }
    
    setState(() {
      _isExporting = true;
    });
    
    try {
      final now = DateTime.now();
      final formatter = DateFormat('yyyy-MM-dd_HH-mm');
      final fileName = 'chat_history_${formatter.format(now)}.txt';
      
      // Prepare content
      final buffer = StringBuffer();
      buffer.writeln('Optichat AI Assistant - Chat History');
      buffer.writeln('Exported on: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(now)}');
      buffer.writeln('-------------------------------------------');
      buffer.writeln();
      
      for (var message in _messages) {
        final prefix = message.isUser ? 'You: ' : 'Assistant: ';
        buffer.writeln('$prefix${message.text}');
        buffer.writeln();
      }
      
      // Get temporary directory
      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/$fileName';
      
      // Write to file
      final file = File(filePath);
      await file.writeAsString(buffer.toString());
      
      // Share file
      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'My chat history with Optichat AI Assistant',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error exporting chat history: $e')),
      );
      print('Error exporting chat history: $e');
    } finally {
      setState(() {
        _isExporting = false;
      });
    }
  }

  // Initialize speech recognition
  void _initSpeech() async {
    _speech = stt.SpeechToText();
    _speechEnabled = await _speech.initialize(
      onStatus: (status) {
        print('Speech recognition status: $status');
        if (status == 'done' || status == 'notListening') {
          setState(() {
            _isListening = false;
          });
        }
      },
      onError: (error) {
        print('Speech recognition error: $error');
        setState(() {
          _isListening = false;
        });
      },
    );
    setState(() {});
  }

  // Initialize text-to-speech
  void _initTts() {
    _flutterTts = FlutterTts();
    _flutterTts.setLanguage('en-US');
    _flutterTts.setSpeechRate(0.5); // Slightly slower for better understanding
    _flutterTts.setVolume(1.0);
    _flutterTts.setPitch(1.0);
  }

  // Start listening for speech input
  void _startListening() async {
    if (_speechEnabled) {
      setState(() {
        _isListening = true;
      });
      
      await _speech.listen(
        onResult: _onSpeechResult,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        localeId: 'en_US',
      );
    } else {
      _initSpeech();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Speech recognition is not available. Please try again.')),
      );
    }
  }

  // Handle speech recognition result
  void _onSpeechResult(SpeechRecognitionResult result) {
    if (result.finalResult) {
      setState(() {
        _isListening = false;
        _messageController.text = result.recognizedWords;
      });
      
      // Send message automatically when speech is recognized
      if (_messageController.text.isNotEmpty) {
        _sendMessage();
      }
    }
  }

  // Speak text using TTS
  Future<void> _speak(String text) async {
    await _flutterTts.speak(text);
  }

  void _addAssistantMessage(String text, {bool saveToFirestore = false}) {
    setState(() {
      _messages.add(
        ChatMessage(
          text: text,
          isUser: false,
        ),
      );
    });
    
    // Save to Firestore if needed
    if (saveToFirestore) {
      _saveMessageToFirestore(text, false);
    }
    
    // Read out the assistant's response
    _speak(text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chatbot Assistant'),
        backgroundColor: const Color(0xFF2561FA),
        foregroundColor: Colors.white,
        actions: [
          // Export button
          IconButton(
            onPressed: _isExporting ? null : _exportChatHistory,
            tooltip: 'Export Chat History',
            icon: _isExporting 
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Icon(Icons.download),
          ),
          // Clear history button 
          IconButton(
            onPressed: _messages.isEmpty ? null : () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Clear Chat History?'),
                  content: const Text('This will delete all your chat messages from this device and cloud storage. This cannot be undone.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('CANCEL'),
                    ),
                    TextButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        await _clearChatHistory();
                      },
                      child: const Text('CLEAR'),
                    ),
                  ],
                ),
              );
            },
            tooltip: 'Clear Chat History',
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoadingHistory
              ? const Center(
                  child: CircularProgressIndicator(),
                )
              : _messages.isEmpty
                ? Center(
                    child: Text(
                      'No messages yet',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 16,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    reverse: false,
                    itemBuilder: (context, index) {
                      return _messages[index];
                    },
                  ),
          ),
          if (_isTyping)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text("Assistant is typing..."),
                ],
              ),
            ),
          // Large microphone button for blind users
          Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: GestureDetector(
              onTap: () {
                if (!_isListening) {
                  _startListening();
                }
              },
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isListening ? Colors.red : const Color(0xFF2561FA),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      spreadRadius: 2,
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(
                  _isListening ? Icons.mic : Icons.mic_none,
                  color: Colors.white,
                  size: 60,
                ),
              ),
            ),
          ),
          // Text input
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            color: Colors.grey.shade100,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: _isListening ? 'Listening...' : 'How can I help you today?',
                      fillColor: Colors.white,
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton(
                  onPressed: _sendMessage,
                  backgroundColor: const Color(0xFF2561FA),
                  elevation: 0,
                  child: const Icon(
                    Icons.send,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  // Clear chat history
  Future<void> _clearChatHistory() async {
    try {
      setState(() {
        _isLoadingHistory = true;
      });
      
      // Delete messages from Firestore
      final snapshot = await _firestore
          .collection('chat_history')
          .doc(_userId)
          .collection('messages')
          .get();
          
      for (var doc in snapshot.docs) {
        await doc.reference.delete();
      }
      
      // Clear local messages
      setState(() {
        _messages.clear();
        _isLoadingHistory = false;
      });
      
      // Add welcome message
      _addAssistantMessage(
        "Hello! I'm your AI assistant. Tap the large microphone button to speak, or type your message below.",
        saveToFirestore: true
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat history cleared')),
      );
    } catch (e) {
      print('Error clearing chat history: $e');
      setState(() {
        _isLoadingHistory = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error clearing chat history')),
      );
    }
  }

  void _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    // Add user message to chat
    final userMessage = _messageController.text.trim();
    setState(() {
      _messages.add(
        ChatMessage(
          text: userMessage,
          isUser: true,
        ),
      );
      _isTyping = true;
    });
    
    // Save user message to Firestore
    await _saveMessageToFirestore(userMessage, true);
    
    _messageController.clear();

    try {
      // API call for faster response
      final response = await _getAIResponse(userMessage);
      
      setState(() {
        _isTyping = false;
      });
      
      // Add and save AI response
      _addAssistantMessage(response, saveToFirestore: true);
    } catch (e) {
      setState(() {
        _isTyping = false;
      });
      
      final errorMessage = "Sorry, I couldn't process your request. Please try again later.";
      _addAssistantMessage(errorMessage, saveToFirestore: true);
      print("Error: $e");
    }
  }

  Future<String> _getAIResponse(String userMessage) async {
    final uri = Uri.parse('https://openrouter.ai/api/v1/chat/completions');
    
    try {
      // Enhanced API call for faster responses
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
          'HTTP-Referer': 'optichat-app.com',
          'X-Title': 'Optichat'
        },
        body: jsonEncode({
          'model': _model,
          'messages': [
            {'role': 'user', 'content': userMessage}
          ],
          'temperature': 0.7, // Lower for more focused responses
          'max_tokens': 150, // Limit response length for speed
          'stream': false // Non-streaming for simpler implementation
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'];
      } else {
        throw Exception('Failed to get response: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error communicating with AI service: $e');
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _flutterTts.stop();
    super.dispose();
  }
}

class ChatMessage extends StatelessWidget {
  final String text;
  final bool isUser;

  const ChatMessage({
    super.key,
    required this.text,
    required this.isUser,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) 
            CircleAvatar(
              backgroundColor: const Color(0xFF2561FA),
              child: const Icon(Icons.support_agent, color: Colors.white),
            ),
          if (!isUser) const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser 
                    ? const Color(0xFF2561FA)
                    : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                text,
                style: TextStyle(
                  color: isUser ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
          if (isUser)
            CircleAvatar(
              backgroundColor: Colors.blue.shade900,
              child: const Icon(Icons.person, color: Colors.white),
            ),
        ],
      ),
    );
  }
} 