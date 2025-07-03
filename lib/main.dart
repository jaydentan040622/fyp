import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'accountModule/app.dart';
import 'accountModule/firebase_options.dart';
import 'home.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await Supabase.initialize(
    url: 'https://vbxgegqkijalgwqkcckj.supabase.co', // TODO: Replace with your Supabase project URL
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZieGdlZ3FraWphbGd3cWtjY2tqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTEwMjA5ODUsImV4cCI6MjA2NjU5Njk4NX0.l926IxvjVSOqjQ84QGMwIuxqDNR8nexv0ckK8GrbJik', // TODO: Replace with your Supabase anon key
  );
  runApp(const MyApp());
  // if want to run home screen without login
  // runApp(const MaterialApp(home: HomeScreen()));
}
