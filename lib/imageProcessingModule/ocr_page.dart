import 'package:flutter/material.dart';

class OCRPage extends StatelessWidget {
  const OCRPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF2561FA),
        foregroundColor: Colors.white,
        title: const Text('OCR'),
      ),
      body: const Center(
        child: Text('OCR Feature Coming Soon'),
      ),
    );
  }
} 