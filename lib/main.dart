import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'accountModule/app.dart';
import 'accountModule/firebase_options.dart';
import 'home.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
  // if want to run home screen without login 
  // runApp(const MaterialApp(home: HomeScreen()));
}
