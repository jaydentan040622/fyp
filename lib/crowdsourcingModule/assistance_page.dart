import 'package:flutter/material.dart';

class AssistancePage extends StatelessWidget {
  const AssistancePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF2561FA),
        foregroundColor: Colors.white,
        title: const Text('Assistance'),
      ),
      body: const Center(
        child: Text('Assistance Feature Coming Soon'),
      ),
    );
  }
} 