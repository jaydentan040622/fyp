import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:csv/csv.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:typed_data';
import 'package:flutter_tts/flutter_tts.dart';

import 'navigation_page.dart';

class TransportSchedule extends StatefulWidget {
  const TransportSchedule({Key? key}) : super(key: key);

  @override
  _TransportScheduleState createState() => _TransportScheduleState();
}

class _TransportScheduleState extends State<TransportSchedule> {
  bool _isLoading = true;
  Position? _currentPosition;
  List<Map<String, dynamic>> _lines = [];
  String? _errorMessage;
  Map<String, Map<String, dynamic>> _transportLines = {};
  Map<String, String> _lineStatus = {};
  Map<String, String> _lineDisruptionMsg = {};

  // Text-to-speech instance
  final FlutterTts flutterTts = FlutterTts();
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();
    _initializeTts();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 100));
      await _speakLoadingGuide();
      setState(() { _isLoading = true; });
      _loadGTFSData();
    });
  }

  Future<void> _initializeTts() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.3); // Slower speech rate
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
      print("TTS Error: $msg");
    });
  }

  Future<void> _loadGTFSData() async {
    try {
      // Load and parse routes.txt
      final routesData = await rootBundle.loadString('assets/gtfs/routes.txt');
      final routesTable = const CsvToListConverter().convert(routesData);
      if (routesTable.isEmpty) {
        throw Exception('routes.txt is empty');
      }
      final routesHeaders = routesTable[0].cast<String>();

      // Load and parse stops.txt
      final stopsData = await rootBundle.loadString('assets/gtfs/stops.txt');
      final stopsTable = const CsvToListConverter().convert(stopsData);
      if (stopsTable.isEmpty) {
        throw Exception('stops.txt is empty');
      }
      final stopsHeaders = stopsTable[0].cast<String>();

      // Load and parse trips.txt for frequency information
      final tripsData = await rootBundle.loadString('assets/gtfs/trips.txt');
      final tripsTable = const CsvToListConverter().convert(tripsData);
      if (tripsTable.isEmpty) {
        throw Exception('trips.txt is empty');
      }
      final tripsHeaders = tripsTable[0].cast<String>();

      // Load and parse frequencies.txt if available
      Map<String, List<int>> tripFrequencies = {};
      try {
        final freqData = await rootBundle.loadString('assets/gtfs/frequencies.txt');
        final freqTable = const CsvToListConverter().convert(freqData);
        if (freqTable.isNotEmpty) {
          final freqHeaders = freqTable[0].cast<String>();
          final tripIdIdx = freqHeaders.indexOf('trip_id');
          final headwayIdx = freqHeaders.indexOf('headway_secs');
          for (var i = 1; i < freqTable.length; i++) {
            final row = freqTable[i];
            final tripId = row[tripIdIdx].toString();
            final headway = int.tryParse(row[headwayIdx].toString());
            if (headway != null) {
              tripFrequencies.putIfAbsent(tripId, () => []).add(headway);
            }
          }
        }
      } catch (e) {
        // frequencies.txt not found or error
      }

      // Create a map of route_id to route details
      final Map<String, Map<String, dynamic>> routes = {};
      for (var i = 1; i < routesTable.length; i++) {
        if (routesTable[i].length != routesHeaders.length) {
          print('Warning: Row $i in routes.txt has different length than headers. Skipping.');
          continue;
        }
        final route = Map.fromIterables(routesHeaders, routesTable[i].map((e) => e.toString()));
        if (route['route_id'] == null) {
          print('Warning: route_id is null for route: $route');
          continue;
        }

        // Get route color with fallback
        Color routeColor;
        try {
          routeColor = _getColorFromHex(route['route_color'] ?? '');
        } catch (e) {
          print('Error parsing route color for route ${route['route_id']}: $e');
          routeColor = Colors.blue;
        }

        // Find all trip_ids for this route
        List<String> tripIds = [];
        for (var j = 1; j < tripsTable.length; j++) {
          final trip = Map.fromIterables(tripsHeaders, tripsTable[j].map((e) => e.toString()));
          if (trip['route_id'] == route['route_id']) {
            tripIds.add(trip['trip_id']!);
          }
        }
        // Find all headways for these trip_ids
        List<int> headways = [];
        for (final tripId in tripIds) {
          if (tripFrequencies.containsKey(tripId)) {
            headways.addAll(tripFrequencies[tripId]!);
          }
        }
        String frequencyStr = '5-10 minutes';
        if ((route['route_long_name'] ?? '').toString().toUpperCase().contains('KTM')) {
          frequencyStr = 'Unknown';
        } else if (headways.isNotEmpty) {
          headways.sort();
          int minHeadway = headways.first;
          int maxHeadway = headways.last;
          if (minHeadway == maxHeadway) {
            frequencyStr = 'Every ${_formatHeadway(minHeadway)}';
          } else {
            frequencyStr = 'Every ${_formatHeadway(minHeadway)} to ${_formatHeadway(maxHeadway)}';
          }
        }

        routes[route['route_id']!] = {
          'name': route['route_long_name'] ?? route['route_short_name'] ?? 'Unknown Route',
          'short_name': route['route_short_name'] ?? '',
          'color': routeColor,
          'frequency': frequencyStr,
          'status': '', // Don't set default status
          'stations': [],
        };
      }

      // Create a map of stop_id to stop details
      final Map<String, Map<String, dynamic>> stops = {};
      try {
        for (var i = 1; i < stopsTable.length; i++) {
          if (stopsTable[i].length != stopsHeaders.length) {
            print('Warning: Row $i in stops.txt has different length than headers. Skipping.');
            continue;
          }
          final stop = Map.fromIterables(stopsHeaders, stopsTable[i].map((e) => e.toString()));

          // Debug print
          print('Processing stop: ${stop['stop_id']}');
          print('Headers: $stopsHeaders');
          print('Stop data: $stop');

          // Validate required fields
          if (!stop.containsKey('stop_id') ||
              !stop.containsKey('stop_name') ||
              !stop.containsKey('stop_lat') ||
              !stop.containsKey('stop_lon')) {
            print('Missing required fields for stop: $stop');
            continue;
          }

          // Try parsing coordinates
          double? lat;
          double? lng;
          try {
            lat = double.tryParse(stop['stop_lat']!);
            lng = double.tryParse(stop['stop_lon']!);
          } catch (e) {
            print('Error parsing coordinates for stop ${stop['stop_id']}: $e');
            continue;
          }

          if (lat == null || lng == null) {
            print('Invalid coordinates for stop ${stop['stop_id']}: lat=$lat, lng=$lng');
            continue;
          }

          if (stop['stop_id'] == null) {
            print('Warning: stop_id is null for stop: $stop');
            continue;
          }

          stops[stop['stop_id']!] = {
            'name': stop['stop_name'] ?? 'Unknown Stop',
            'lat': lat,
            'lng': lng,
          };
        }
      } catch (e) {
        print('Error processing stops: $e');
        print('Stops table length: ${stopsTable.length}');
        print('First row: ${stopsTable[0]}');
        if (stopsTable.length > 1) {
          print('Second row: ${stopsTable[1]}');
        }
        rethrow;
      }

      // Create a map of trip_id to route_id
      final Map<String, String> tripToRoute = {};
      for (var i = 1; i < tripsTable.length; i++) {
        if (tripsTable[i].length != tripsHeaders.length) {
          print('Warning: Row $i in trips.txt has different length than headers. Skipping.');
          continue;
        }
        final trip = Map.fromIterables(tripsHeaders, tripsTable[i].map((e) => e.toString()));
        if (trip['trip_id'] == null || trip['route_id'] == null) {
          print('Warning: trip_id or route_id is null for trip: $trip');
          continue;
        }
        tripToRoute[trip['trip_id']!] = trip['route_id']!;
      }

      // Load and parse stop_times.txt to associate stops with routes
      final stopTimesData = await rootBundle.loadString('assets/gtfs/stop_times.txt');
      final stopTimesTable = const CsvToListConverter().convert(stopTimesData);
      if (stopTimesTable.isEmpty) {
        throw Exception('stop_times.txt is empty');
      }
      final stopTimesHeaders = stopTimesTable[0].cast<String>();

      print('Stop Times Headers: $stopTimesHeaders');
      print('Number of columns in header: ${stopTimesHeaders.length}');

      // Associate stops with routes
      int skippedRows = 0;
      for (var i = 1; i < stopTimesTable.length; i++) {
        if (stopTimesTable[i].length != stopTimesHeaders.length) {
          skippedRows++;
          if (skippedRows <= 5) { // Only print first 5 errors to avoid flooding the console
            print('Warning: Row $i in stop_times.txt has different length than headers.');
            print('Expected ${stopTimesHeaders.length} columns, got ${stopTimesTable[i].length}');
            print('Headers: $stopTimesHeaders');
            print('Row data: ${stopTimesTable[i]}');
          }
          continue;
        }
        final stopTime = Map.fromIterables(stopTimesHeaders, stopTimesTable[i].map((e) => e.toString()));
        if (stopTime['trip_id'] == null || stopTime['stop_id'] == null) {
          print('Warning: trip_id or stop_id is null for stop_time: $stopTime');
          continue;
        }
        final routeId = tripToRoute[stopTime['trip_id']!];
        if (routeId != null && routes.containsKey(routeId)) {
          final stopId = stopTime['stop_id']!;
          if (stops.containsKey(stopId)) {
            final stop = stops[stopId]!;
            if (!routes[routeId]!['stations'].any((s) => s['name'] == stop['name'])) {
              routes[routeId]!['stations'].add(stop);
            }
          }
        }
      }

      if (skippedRows > 0) {
        print('Total skipped rows in stop_times.txt: $skippedRows');
      }

      // After loading routes, update status for each line
      // Map route_id to status
      _lineStatus.clear();
      _lineDisruptionMsg.clear();
      for (final entry in routes.entries) {
        final name = entry.value['name'] ?? '';
        if (name.toString().toUpperCase().contains('KTM')) {
          _lineStatus[entry.key] = 'Unknown';
        }
        // Don't set default "Normal" status - only show status when there's actual information
      }
      setState(() {
        _transportLines = routes;
        _isLoading = false;
      });

      // Fetch disruptions after transport lines are loaded
      print('=== Transport lines loaded ===');
      print('Total routes: ${routes.length}');
      for (final entry in routes.entries) {
        print('Route: ${entry.key} - "${entry.value['name']}"');
      }
      _fetchPrasaranaDisruptions();

      // Get location after loading GTFS data
      _getCurrentLocation();
    } catch (e) {
      print('Error in _loadGTFSData: $e');
      setState(() {
        _errorMessage = 'Error loading GTFS data: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchPrasaranaDisruptions() async {
    print('=== Starting Prasarana disruptions fetch ===');
    print('Transport lines available: ${_transportLines.length}');

    try {
      final url = 'https://api.data.gov.my/gtfs-realtime/alerts/prasarana';
      print('Fetching from URL: $url');
      final response = await http.get(Uri.parse(url));
      print('Response status: ${response.statusCode}');
      print('Response body length: ${response.bodyBytes.length}');

      if (response.statusCode == 200) {
        if (response.bodyBytes.isNotEmpty) {
          try {
            // Try to parse as JSON first (for no alerts case)
            final jsonData = json.decode(utf8.decode(response.bodyBytes));
            print('Successfully parsed JSON response');
            print('JSON data: $jsonData');

            // Check if this is a "no alerts" response
            if (jsonData is Map && (jsonData.isEmpty || jsonData.containsKey('message'))) {
              print('No alerts detected in JSON response');
              setState(() {
                int normalCount = 0;
                for (final entry in _transportLines.entries) {
                  final name = entry.value['name'] ?? '';
                  print('Checking line: ${entry.key} - "$name"');

                  if (name.toString().toUpperCase().contains('LRT') ||
                      name.toString().toUpperCase().contains('MRT') ||
                      name.toString().toUpperCase().contains('RAPIDKL') ||
                      name.toString().toUpperCase().contains('MONORAIL') ||
                      name.toString().toUpperCase().contains('BRT')) {
                    _lineStatus[entry.key] = 'Normal';
                    normalCount++;
                    print('✓ Set Normal status for: ${entry.key} - "$name"');
                  }
                }
                print('Total Normal status set: $normalCount');
              });
              return;
            } else {
              // This might be actual alert data in JSON format
              print('Potential alert data detected in JSON');
              _parseAlertData(jsonData);
              return;
            }
          } catch (e) {
            print('Error parsing JSON: $e');
            // If JSON parsing fails, it might be protobuf data
            print('Trying to parse as protobuf...');
            _parseProtobufData(response.bodyBytes);
            return;
          }
        } else {
          print('Empty response body, treating as no disruptions');
          setState(() {
            int normalCount = 0;
            for (final entry in _transportLines.entries) {
              final name = entry.value['name'] ?? '';
              if (name.toString().toUpperCase().contains('LRT') ||
                  name.toString().toUpperCase().contains('MRT') ||
                  name.toString().toUpperCase().contains('RAPIDKL') ||
                  name.toString().toUpperCase().contains('MONORAIL') ||
                  name.toString().toUpperCase().contains('BRT')) {
                _lineStatus[entry.key] = 'Normal';
                normalCount++;
                print('✓ Set Normal status for: ${entry.key} - "$name"');
              }
            }
            print('Total Normal status set: $normalCount');
          });
          return;
        }
      } else {
        print('HTTP error: ${response.statusCode}');
        // Even if API fails, treat as no disruptions (Normal status)
        setState(() {
          int normalCount = 0;
          for (final entry in _transportLines.entries) {
            final name = entry.value['name'] ?? '';
            if (name.toString().toUpperCase().contains('LRT') ||
                name.toString().toUpperCase().contains('MRT') ||
                name.toString().toUpperCase().contains('RAPIDKL') ||
                name.toString().toUpperCase().contains('MONORAIL') ||
                name.toString().toUpperCase().contains('BRT')) {
              _lineStatus[entry.key] = 'Normal';
              normalCount++;
              print('✓ Set Normal status for: ${entry.key} - "$name" (API failed but treating as Normal)');
            }
          }
          print('Total Normal status set: $normalCount');
        });
      }
    } catch (e) {
      print('Network or parsing error: $e');
      setState(() {
        int unknownCount = 0;
        for (final entry in _transportLines.entries) {
          final name = entry.value['name'] ?? '';
          if (name.toString().toUpperCase().contains('LRT') ||
              name.toString().toUpperCase().contains('MRT') ||
              name.toString().toUpperCase().contains('RAPIDKL') ||
              name.toString().toUpperCase().contains('MONORAIL') ||
              name.toString().toUpperCase().contains('BRT')) {
            _lineStatus[entry.key] = 'Unknown';
            unknownCount++;
            print('✗ Set Unknown status for: ${entry.key} - "$name"');
          }
        }
        print('Total Unknown status set: $unknownCount');
      });
    }
    print('=== Finished Prasarana disruptions fetch ===');
  }

  void _parseAlertData(Map<String, dynamic> jsonData) {
    print('Parsing alert data from JSON...');
    print('Alert data: $jsonData');

    // Reset all Prasarana lines to Normal first
    for (final entry in _transportLines.entries) {
      final name = entry.value['name'] ?? '';
      if (name.toString().toUpperCase().contains('LRT') ||
          name.toString().toUpperCase().contains('MRT') ||
          name.toString().toUpperCase().contains('RAPIDKL') ||
          name.toString().toUpperCase().contains('MONORAIL') ||
          name.toString().toUpperCase().contains('BRT')) {
        _lineStatus[entry.key] = 'Normal';
      }
    }

    // Parse alerts if they exist
    if (jsonData.containsKey('entity') && jsonData['entity'] is List) {
      final entities = jsonData['entity'] as List;
      print('Found ${entities.length} alert entities');

      for (final entity in entities) {
        if (entity is Map<String, dynamic> && entity.containsKey('alert')) {
          final alert = entity['alert'];
          if (alert is Map<String, dynamic>) {
            final headerText = alert['headerText']?['translation']?[0]?['text'] ?? '';
            final descriptionText = alert['descriptionText']?['translation']?[0]?['text'] ?? '';
            final effect = alert['effect'] ?? '';

            print('Alert: $headerText - $descriptionText - Effect: $effect');

            // Determine status based on effect
            String status = 'Normal';
            if (effect == 'DETOUR' || effect == 'SIGNIFICANT_DELAYS' ||
                effect == 'REDUCED_SERVICE' || effect == 'STOP_MOVED') {
              status = 'Delayed';
            } else if (effect == 'NO_SERVICE' || effect == 'ADDITIONAL_SERVICE') {
              status = 'Disrupted';
            }

            // Try to match alert to specific lines
            _matchAlertToLines(headerText, descriptionText, status);
          }
        }
      }
    }

    setState(() {});
  }

  void _parseProtobufData(Uint8List data) {
    print('Parsing protobuf data...');
    // Note: This would require protobuf generated classes
    // For now, we'll treat protobuf data as potential disruptions
    print('Protobuf data detected - treating as potential disruptions');

    setState(() {
      for (final entry in _transportLines.entries) {
        final name = entry.value['name'] ?? '';
        if (name.toString().toUpperCase().contains('LRT') ||
            name.toString().toUpperCase().contains('MRT') ||
            name.toString().toUpperCase().contains('RAPIDKL') ||
            name.toString().toUpperCase().contains('MONORAIL') ||
            name.toString().toUpperCase().contains('BRT')) {
          _lineStatus[entry.key] = 'Delayed'; // Assume delayed if protobuf data exists
          print('⚠ Set Delayed status for: ${entry.key} - "$name" (protobuf data detected)');
        }
      }
    });
  }

  void _matchAlertToLines(String headerText, String descriptionText, String status) {
    // Simple keyword matching to associate alerts with lines
    final text = '${headerText.toLowerCase()} ${descriptionText.toLowerCase()}';

    for (final entry in _transportLines.entries) {
      final name = entry.value['name'] ?? '';
      final routeId = entry.key;

      // Check if this line is mentioned in the alert
      bool isAffected = false;

      if (name.toString().toUpperCase().contains('LRT') &&
          (text.contains('lrt') || text.contains('light rail'))) {
        isAffected = true;
      } else if (name.toString().toUpperCase().contains('MRT') &&
          (text.contains('mrt') || text.contains('mass rapid'))) {
        isAffected = true;
      } else if (name.toString().toUpperCase().contains('MONORAIL') &&
          (text.contains('monorail'))) {
        isAffected = true;
      } else if (name.toString().toUpperCase().contains('BRT') &&
          (text.contains('brt') || text.contains('bus rapid'))) {
        isAffected = true;
      }

      if (isAffected) {
        _lineStatus[routeId] = status;
        _lineDisruptionMsg[routeId] = headerText;
        print('⚠ Set $status status for: $routeId - "$name"');
        print('  Alert: $headerText');
      }
    }
  }

  Color _getColorFromHex(String hexColor) {
    try {
      // Remove any '#' or '0x' prefix
      hexColor = hexColor.replaceAll('#', '').replaceAll('0x', '');
      // Pad with leading zeros if less than 6 characters
      if (hexColor.length < 6) {
        hexColor = hexColor.padLeft(6, '0');
      }
      // If the color is empty or invalid, return a default color
      if (hexColor.isEmpty || hexColor == 'route_color') {
        return Colors.blue;
      }
      // Ensure the hex color is 6 characters
      if (hexColor.length == 6) {
        hexColor = 'FF$hexColor';
      }
      // Parse the hex color
      return Color(int.parse(hexColor, radix: 16));
    } catch (e) {
      print('Error parsing color $hexColor: $e');
      return Colors.blue; // Return default color if parsing fails
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _errorMessage = 'Location services are disabled.';
          _isLoading = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _errorMessage = 'Location permissions are denied.';
            _isLoading = false;
          });
          return;
        }
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentPosition = position;
        _sortLinesByDistance();
        _isLoading = false;
      });

      // Auto-start speech after everything is loaded
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _speakAllTransportLines();
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error getting location: $e';
        _isLoading = false;
      });
    }
  }

  void _sortLinesByDistance() {
    if (_currentPosition == null) return;

    _lines = _transportLines.entries.map((entry) {
      // Find nearest station for this line
      double minDistance = double.infinity;
      String? nearestStationName;
      for (var station in entry.value['stations']) {
        double distance = Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          station['lat'],
          station['lng'],
        );
        if (distance < minDistance) {
          minDistance = distance;
          nearestStationName = station['name'];
        }
      }

      return {
        'route_id': entry.key,
        'short_name': entry.value['short_name'] ?? '',
        'long_name': entry.value['name'],
        'frequency': entry.value['frequency'],
        'status': entry.value['status'],
        'color': entry.value['color'],
        'distance': minDistance,
        'nearest_station': nearestStationName ?? '',
      };
    }).toList();

    // Sort by distance
    _lines.sort((a, b) => a['distance'].compareTo(b['distance']));
  }

  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)}m';
    } else {
      return '${(meters / 1000).toStringAsFixed(1)}km';
    }
  }

  String _formatHeadway(int secs) {
    if (secs < 60) return '$secs sec';
    if (secs % 60 == 0) return '${secs ~/ 60} min';
    return '${(secs / 60).toStringAsFixed(1)} min';
  }

  Future<void> _speakTransportLineInfo(Map<String, dynamic> line) async {
    final lineName = line['long_name'] ?? 'Unknown Line';
    final frequency = _formatFrequencyForSpeech(line['frequency'] ?? 'Unknown frequency');
    final status = _lineStatus[line['route_id']] ?? '';
    final nearestStation = line['nearest_station'] ?? 'Unknown station';
    final distance = _formatDistance(line['distance'] ?? 0);

    String speechText = "$lineName. ";
    speechText += "Frequency: $frequency. ";

    // Only mention status if it's available and not empty
    if (status != null && status.isNotEmpty && status != 'Unknown status') {
      speechText += "Status: $status. ";
    }

    speechText += "Nearest station: $nearestStation, $distance away. ";

    // Add disruption message if available
    final disruptionMsg = _lineDisruptionMsg[line['route_id']];
    if (disruptionMsg != null && disruptionMsg.isNotEmpty) {
      speechText += "Alert: $disruptionMsg. ";
    }

    await flutterTts.speak(speechText);
  }

  String _formatFrequencyForSpeech(String frequency) {
    // Replace dashes with "to" for better speech
    return frequency.replaceAll('-', ' to ');
  }

  Future<void> _speakAllTransportLines() async {
    await flutterTts.stop();
    await flutterTts.speak(
        "You are on the public transport lines page. Swipe left to go back, swipe right to go to the main navigation page. Here are the available public transport lines."
    );
    if (_lines.isEmpty) {
      await flutterTts.speak("No transport lines available.");
      return;
    }

    String speechText = "Found ${_lines.length} transport lines. ";

    for (int i = 0; i < _lines.length && i < 11; i++) {
      final line = _lines[i];
      final lineName = line['long_name'] ?? 'Unknown Line';
      final frequency = _formatFrequencyForSpeech(line['frequency'] ?? 'Unknown frequency');
      final status = _lineStatus[line['route_id']] ?? '';

      speechText += "Line ${i + 1}: ${lineName}. Frequency: ${frequency}. ";

      // Only mention status if it's available and not empty
      if (status.isNotEmpty && status != 'Unknown status') {
        speechText += "Status: ${status}. ";
      }
    }

    await flutterTts.speak(speechText);
  }

  Future<void> _speakLoadingGuide() async {
    await flutterTts.stop();
    await flutterTts.speak(
        "Looking for public transport lines, please wait for a while."
    );
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
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Expanded(
                      child: Text(
                        'Public Transport Lines',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        // Voice control button
                        IconButton(
                          icon: Icon(
                            _isSpeaking ? Icons.volume_off : Icons.volume_up,
                            color: Colors.white,
                          ),
                          onPressed: _isSpeaking ? null : _speakAllTransportLines,
                        ),
                        // IconButton(
                        //   icon: const Icon(Icons.refresh, color: Colors.white),
                        //   onPressed: () {
                        //     setState(() {
                        //       _isLoading = true;
                        //     });
                        //     _loadGTFSData();
                        //   },
                        // ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Main content
          Expanded(
            child: GestureDetector(
              onHorizontalDragEnd: (details) async {
                if (details.primaryVelocity != null) {
                  if (details.primaryVelocity! > 0) {
                    // Swipe left-to-right: go back
                    await flutterTts.stop();
                    Navigator.pop(context);
                  } else if (details.primaryVelocity! < 0) {
                    // Swipe right-to-left: go to NavigationPage
                    await flutterTts.stop();
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (context) => NavigationPage()),
                          (route) => false,
                    );
                  }
                }
              },
              child: Container(
                color: const Color(0xFFF0F4F8), // Light blue-grey background
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _errorMessage != null
                    ? Center(child: Text(_errorMessage!))
                    : RefreshIndicator(
                  onRefresh: _loadGTFSData,
                  child: ListView.builder(
                    padding: EdgeInsets.zero, // Remove default padding
                    itemCount: _lines.length,
                    itemBuilder: (context, index) {
                      final line = _lines[index];
                      final lineData = _transportLines[line['route_id']]!;
                      final status = _lineStatus[line['route_id']] ?? '';
                      final disruptionMsg = _lineDisruptionMsg[line['route_id']];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: ExpansionTile(
                          onExpansionChanged: (expanded) {
                            if (expanded) {
                              _speakTransportLineInfo(line);
                            }
                          },
                          leading: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: line['color'],
                              shape: BoxShape.circle,
                            ),
                          ),
                          title: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                line['short_name'] != '' ? line['short_name'] : line['route_id'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 17,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                              Text(
                                line['long_name'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.normal,
                                  fontSize: 13,
                                  color: Colors.grey,
                                ),
                                overflow: TextOverflow.visible,
                                softWrap: true,
                              ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Frequency: ${line['frequency']}'),
                              Text(
                                'Nearest station: ${line['nearest_station']} (${_formatDistance(line['distance'])} away)',
                                style: const TextStyle(
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (status.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: status == 'Normal'
                                        ? Colors.green
                                        : status == 'Unknown'
                                        ? Colors.grey
                                        : status == 'Delayed'
                                        ? Colors.orange
                                        : status == 'Disrupted'
                                        ? Colors.red
                                        : Colors.orange,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    status,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_drop_down),
                            ],
                          ),
                          children: [
                            if (disruptionMsg != null)
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  disruptionMsg,
                                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                                ),
                              ),
                            Container(
                              padding: const EdgeInsets.all(16),
                              color: Colors.grey[50],
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Stations:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ...lineData['stations'].map<Widget>((station) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.circle,
                                            size: 8,
                                            color: Colors.grey,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              station['name'],
                                              style: const TextStyle(fontSize: 14),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
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