import 'package:flutter/material.dart';

class VoiceNotePage extends StatelessWidget {
  const VoiceNotePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF2561FA),
        foregroundColor: Colors.white,
        title: const Text('Voice Note'),
      ),
      body: const Center(
        child: Text('Voice Note Feature Coming Soon'),
      ),
    );
  }
} 