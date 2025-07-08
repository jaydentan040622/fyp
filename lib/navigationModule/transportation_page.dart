import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:fyp/accountModule/app.dart';

import 'navigation_page.dart';
import 'searchDestination.dart';
import 'transportSchedule.dart';

class TransportationPage extends StatefulWidget {
  const TransportationPage({super.key});

  @override
  State<TransportationPage> createState() => _TransportationPageState();
}

class _TransportationPageState extends State<TransportationPage> with RouteAware {
  final FlutterTts flutterTts = FlutterTts();
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();
    _initializeTts();
    WidgetsBinding.instance.addPostFrameCallback((_) => _speakGuide());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    flutterTts.stop();
    super.dispose();
  }

  @override
  void didPopNext() {
    // Called when coming back to this page
    _speakGuide();
  }

  Future<void> _initializeTts() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.35);
    await flutterTts.setVolume(1.0);
    await flutterTts.setPitch(1.0);
    flutterTts.setStartHandler(() {
      setState(() {
        _isSpeaking = true;
      });
    });
    flutterTts.setCompletionHandler(() {
      setState(() {
        _isSpeaking = false;
      });
    });
    flutterTts.setErrorHandler((msg) {
      setState(() {
        _isSpeaking = false;
      });
    });
  }

  Future<void> _speakGuide() async {
    await flutterTts.stop();
    await flutterTts.speak(
        "Welcome to the transportation page. Swipe up to search for a destination. Swipe down to check public transport availability. Swipe left to go back, swipe right to go to the main menu. You can also tap the top or bottom button."
    );
  }

  void _handleVerticalSwipe(DragEndDetails details) async {
    if (details.primaryVelocity != null) {
      if (details.primaryVelocity! < 0) {
        // Swipe from down to up
        await flutterTts.stop();
        Navigator.push(context, MaterialPageRoute(builder: (context) => SearchDestination()));
      } else if (details.primaryVelocity! > 0) {
        // Swipe from up to down
        await flutterTts.stop();
        Navigator.push(context, MaterialPageRoute(builder: (context) => TransportSchedule()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Blue header
          Container(
            width: double.infinity,
            height: 120,
            color: const Color(0xFF2561FA),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () async {
                        await flutterTts.stop();
                        Navigator.pop(context);
                      },
                    ),
                    const Expanded(
                      child: Text(
                        'Optichat',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _isSpeaking ? Icons.volume_off : Icons.volume_up,
                        color: Colors.white,
                      ),
                      onPressed: _isSpeaking ? null : _speakGuide,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Main content
          Expanded(
            child: Container(
              color: const Color(0xFFF0F4F8), // Light blue-grey background
              child: Center(
                child: Container(
                  width: 500,
                  padding: const EdgeInsets.all(16.0),
                  child: GestureDetector(
                    onVerticalDragEnd: _handleVerticalSwipe,
                    onHorizontalDragEnd: (details) async {
                      if (details.primaryVelocity != null) {
                        if (details.primaryVelocity! < 0) {
                          // Swipe left (right-to-left): go back
                          await flutterTts.stop();
                          Navigator.pop(context);
                        } else if (details.primaryVelocity! > 0) {
                          // Swipe right (left-to-right): go to main menu
                          await flutterTts.stop();
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(builder: (context) => NavigationPage()),
                                (route) => false,
                          );
                        }
                      }
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              await flutterTts.stop();
                              Navigator.push(context, MaterialPageRoute(builder: (context) => SearchDestination()));
                            },
                            child: SizedBox(
                              width: 280,
                              child: Card(
                                elevation: 4,
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color: Colors.blue.shade50,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.search,
                                        size: 80,
                                        color: Colors.blue.shade700,
                                      ),
                                      const SizedBox(height: 16),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                                        child: Text(
                                          'Search for Destination',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue.shade700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              await flutterTts.stop();
                              Navigator.push(context, MaterialPageRoute(builder: (context) => TransportSchedule()));
                            },
                            child: SizedBox(
                              width: 280,
                              child: Card(
                                elevation: 4,
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color: Colors.blue.shade50,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.directions_bus,
                                        size: 80,
                                        color: Colors.blue.shade700,
                                      ),
                                      const SizedBox(height: 16),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                                        child: Text(
                                          'Public Transport Schedule',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue.shade700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
