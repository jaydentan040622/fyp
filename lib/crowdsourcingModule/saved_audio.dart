import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SavedAudioPage extends StatelessWidget {
  const SavedAudioPage({super.key});

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
              final data = docs[index].data() as Map<String, dynamic>;
              final fileName = data['file_name'] ?? data['file_path'] ?? 'Unknown';
              final transcript = data['transcript'] ?? '';
              final createdAt = (data['created_at'] as Timestamp?)?.toDate();
              return ExpansionTile(
                leading: const Icon(Icons.audiotrack, color: Color(0xFF2561FA)),
                title: Text(fileName),
                subtitle: createdAt != null
                    ? Text('Created: ${createdAt.toLocal()}')
                    : null,
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
                ],
              );
            },
          );
        },
      ),
    );
  }
}