import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_tts/flutter_tts.dart';
import '../home.dart';
import 'package:vibration/vibration.dart';

class TransportRoutes extends StatefulWidget {
  final LatLng destination;
  final String destinationName;
  final Position currentLocation;

  const TransportRoutes({
    Key? key,
    required this.destination,
    required this.destinationName,
    required this.currentLocation,
  }) : super(key: key);

  @override
  State<TransportRoutes> createState() => _TransportRoutesState();
}

class _TransportRoutesState extends State<TransportRoutes> {
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  List<Map<String, dynamic>> _routes = [];
  bool _isLoading = false;

  // Text-to-speech instance
  final FlutterTts flutterTts = FlutterTts();
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();
    _addMarkers();
    _initializeTts();
    _loadTransportRoutes();
  }

  Future<void> _initializeTts() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.4);
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

  void _addMarkers() {
    setState(() {
      _markers.add(
        Marker(
          markerId: const MarkerId('currentLocation'),
          position: LatLng(
            widget.currentLocation.latitude,
            widget.currentLocation.longitude,
          ),
          infoWindow: const InfoWindow(title: 'Current Location'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );

      _markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: widget.destination,
          infoWindow: InfoWindow(title: widget.destinationName),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
    });
  }

  Future<void> _loadTransportRoutes() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Get directions using Google Directions API
      final directions = await http.get(Uri.parse(
          'https://maps.googleapis.com/maps/api/directions/json'
              '?origin=${widget.currentLocation.latitude},${widget.currentLocation.longitude}'
              '&destination=${widget.destination.latitude},${widget.destination.longitude}'
              '&mode=transit'
              '&alternatives=true'
              '&transit_mode=bus|subway|train|tram|rail'
              '&transit_routing_preference=less_walking'
              '&language=en'
              '&region=my'
              '&key=AIzaSyCnLmkL79qMenl0Sn7N4KN38RSoayv-_Bs'
      ));

      if (directions.statusCode == 200) {
        final data = json.decode(directions.body);
        if (data['status'] == 'OK') {
          final routes = data['routes'] as List;
          _routes = routes.map((route) {
            final legs = route['legs'][0];
            final steps = legs['steps'] as List;
            final transitSteps = steps.where((step) => step['travel_mode'] == 'TRANSIT').toList();
            final walkingSteps = steps.where((step) => step['travel_mode'] == 'WALKING').toList();

            // If it's a walking-only route, create a single walking step
            if (transitSteps.isEmpty && walkingSteps.isNotEmpty) {
              return {
                'type': 'WALKING',
                'route': 'Walking Route',
                'duration': legs['duration']['text'],
                'stops': 1,
                'path': steps.map((step) => LatLng(step['start_location']['lat'], step['start_location']['lng'])).toList(),
                'transitSteps': [
                  {
                    'vehicle_type': 'WALKING',
                    'trip_time': legs['duration']['text'],
                    'walking_distance': legs['distance']['text'],
                    'departure_stop': 'Start',
                    'arrival_stop': 'Destination',
                  }
                ],
              };
            }

            // Get detailed transit information
            String transportType = 'WALKING';
            String lineName = '';
            String lineColor = '';
            String vehicleType = '';
            String vehicleName = '';

            // Create route name from transport types
            String routeName = transitSteps.map((step) {
              final details = step['transit_details'];
              final type = details['line']['vehicle']['type']?.toLowerCase() ?? '';
              final line = details['line']['name'] ?? '';

              if (type == 'subway') {
                return line.contains('LRT') ? 'LRT' : 'MRT';
              } else if (type == 'train') {
                return 'KTM';
              } else if (type == 'bus') {
                return 'Bus';
              } else if (type == 'tram') {
                return 'Tram';
              } else {
                return type.toUpperCase();
              }
            }).join(' → ');

            if (transitSteps.isNotEmpty) {
              final transitDetails = transitSteps[0]['transit_details'];
              vehicleType = transitDetails['line']['vehicle']['type'] ?? '';
              vehicleName = transitDetails['line']['vehicle']['name'] ?? '';
              lineName = transitDetails['line']['name'] ?? '';
              lineColor = transitDetails['line']['color'] ?? '';

              // Map vehicle types to our transport types
              switch (vehicleType.toLowerCase()) {
                case 'subway':
                  transportType = lineName.contains('LRT') ? 'LRT' : 'MRT';
                  break;
                case 'train':
                  transportType = 'KTM';
                  break;
                case 'bus':
                  transportType = 'BUS';
                  break;
                case 'tram':
                  transportType = 'TRAM';
                  break;
                default:
                  transportType = vehicleType.toUpperCase();
              }
            }

            return {
              'type': transportType,
              'route': routeName.isNotEmpty ? routeName : 'Route ${_routes.length + 1}',
              'duration': legs['duration']['text'],
              'stops': transitSteps.length,
              'path': steps.map((step) => LatLng(step['start_location']['lat'], step['start_location']['lng'])).toList(),
              'lineColor': lineColor,
              'vehicleName': vehicleName,
              'transitSteps': transitSteps.map((step) {
                final details = step['transit_details'];
                // Find walking steps before and after this transit step
                final stepIndex = steps.indexOf(step);
                final walkingBefore = stepIndex > 0 && steps[stepIndex - 1]['travel_mode'] == 'WALKING'
                    ? steps[stepIndex - 1]
                    : null;
                final walkingAfter = stepIndex < steps.length - 1 && steps[stepIndex + 1]['travel_mode'] == 'WALKING'
                    ? steps[stepIndex + 1]
                    : null;

                // Calculate number of stations to arrival
                final numStops = details['num_stops'] ?? 0;

                return {
                  'departure_stop': details['departure_stop']['name'],
                  'arrival_stop': details['arrival_stop']['name'],
                  'line_name': details['line']['name'],
                  'vehicle_type': details['line']['vehicle']['type'],
                  'trip_time': step['duration']['text'],
                  'stations_between': numStops,
                  'walking_time': walkingBefore != null
                      ? '${walkingBefore['duration']['text']}'
                      : walkingAfter != null
                      ? '${walkingAfter['duration']['text']}'
                      : null,
                  'walking_distance': walkingBefore != null
                      ? walkingBefore['distance']['text']
                      : walkingAfter != null
                      ? walkingAfter['distance']['text']
                      : null,
                  'walking_from': walkingBefore != null
                      ? walkingBefore['start_location']['name'] ?? 'Start'
                      : details['departure_stop']['name'],
                  'walking_to': walkingAfter != null
                      ? walkingAfter['end_location']['name'] ?? 'Destination'
                      : details['arrival_stop']['name'],
                };
              }).toList(),
            };
          }).toList();

          // Update map bounds to show all routes
          if (_routes.isNotEmpty) {
            final bounds = LatLngBounds(
              southwest: LatLng(
                min(widget.currentLocation.latitude, widget.destination.latitude),
                min(widget.currentLocation.longitude, widget.destination.longitude),
              ),
              northeast: LatLng(
                max(widget.currentLocation.latitude, widget.destination.latitude),
                max(widget.currentLocation.longitude, widget.destination.longitude),
              ),
            );
            _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
          }

          // Speak route summary after routes are loaded
          if (mounted) {
            _speakRouteSummary(_routes);
          }
        }
      }
    } catch (e) {
      print('Error loading routes: $e');
      // Fallback if API fails
      if (mounted) {
        _speakRouteSummary(_routes);
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }

    _drawRoutes();
  }

  Future<void> _speakRouteSummary(List<Map<String, dynamic>> routes) async {
    if (routes.isEmpty) {
      await flutterTts.speak("No routes found to your destination. Please try a different location or transportation mode.");
      return;
    }

    String speechText = "You are on the transport route page. Swipe left to go back, swipe right to go to the main menu. ";
    speechText += "I found ";
    speechText += "${routes.length} route options to ${widget.destinationName}. ";

    for (int i = 0; i < routes.length && i < 3; i++) {
      final route = routes[i];
      final routeNumber = i + 1;
      final duration = route['duration'] ?? 'unknown time';
      final routeName = route['route'] ?? 'Route $routeNumber';

      speechText += "Route $routeNumber: $routeName, takes about $duration. ";
    }

    if (routes.length > 10) {
      speechText += "There are ${routes.length - 10} more route options available. ";
    }

    speechText += "Please select your preferred route from the list below.";

    await flutterTts.speak(speechText);
  }

  Future<void> _speakDetailedRoute(int routeIndex) async {
    if (routeIndex >= _routes.length) return;

    final route = _routes[routeIndex];
    final routeNumber = routeIndex + 1;
    final duration = route['duration'] ?? 'unknown time';
    final routeName = route['route'] ?? 'Route $routeNumber';
    final transitSteps = route['transitSteps'] as List? ?? [];

    String speechText = "Route $routeNumber details: $routeName, total duration $duration. ";

    if (transitSteps.isEmpty) {
      speechText += "This is a walking route. ";
    } else {
      speechText += "This route includes: ";
      for (int i = 0; i < transitSteps.length; i++) {
        final step = transitSteps[i];
        final vehicleType = step['vehicle_type'] ?? 'transport';
        final tripTime = step['trip_time'] ?? 'unknown time';
        final departureStop = step['departure_stop'] ?? 'start';
        final arrivalStop = step['arrival_stop'] ?? 'destination';

        if (vehicleType == 'WALKING') {
          speechText += "Walking for $tripTime. ";
        } else {
          speechText += "Take $vehicleType from $departureStop to $arrivalStop, duration $tripTime. ";
        }
      }
    }

    await flutterTts.speak(speechText);
  }

  void _drawRoutes() {
    final List<Color> routeColors = [
      Colors.blue,
      Colors.green,
      Colors.purple,
    ];

    setState(() {
      _polylines.clear();
      for (int i = 0; i < _routes.length; i++) {
        _polylines.add(
          Polyline(
            polylineId: PolylineId('route_$i'),
            points: _routes[i]['path'],
            color: routeColors[i],
            width: 5,
          ),
        );
      }
    });
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    _fitBounds();
  }

  void _fitBounds() {
    if (_markers.isEmpty) return;

    double minLat = _markers.first.position.latitude;
    double maxLat = _markers.first.position.latitude;
    double minLng = _markers.first.position.longitude;
    double maxLng = _markers.first.position.longitude;

    for (Marker marker in _markers) {
      if (marker.position.latitude < minLat) minLat = marker.position.latitude;
      if (marker.position.latitude > maxLat) maxLat = marker.position.latitude;
      if (marker.position.longitude < minLng) minLng = marker.position.longitude;
      if (marker.position.longitude > maxLng) maxLng = marker.position.longitude;
    }

    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        50.0,
      ),
    );
  }

  IconData _getTransportIcon(String type) {
    switch (type.toUpperCase()) {
      case 'BUS':
        return Icons.directions_bus;
      case 'TRAIN':
        return Icons.train;
      case 'BUS + TRAIN':
        return Icons.transfer_within_a_station;
      case 'WALKING':
        return Icons.directions_walk;
      case 'TRAM':
        return Icons.tram;
      case 'SUBWAY':
        return Icons.subway;
      case 'TAXI':
        return Icons.local_taxi;
      default:
        return Icons.directions_transit;
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
                        await flutterTts.speak("Going back");
                        await Future.delayed(const Duration(milliseconds: 2000));
                        await Vibration.vibrate(duration: 100);
                        Navigator.pop(context);
                      },
                    ),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Text(
                            'Optichat',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            widget.destinationName,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Voice control button
                    IconButton(
                      icon: Icon(
                        _isSpeaking ? Icons.volume_off : Icons.volume_up,
                        color: Colors.white,
                      ),
                      onPressed: _isSpeaking ? null : () => _speakRouteSummary(_routes),
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
                  if (details.primaryVelocity! < 0) {
                    // Swipe left (right-to-left): go back
                    await flutterTts.stop();
                    await Future.delayed(const Duration(milliseconds: 200));
                    await flutterTts.speak("Going back");
                    await Future.delayed(const Duration(milliseconds: 2500));
                    await Vibration.vibrate(duration: 100);
                    Navigator.pop(context);
                  } else if (details.primaryVelocity! > 0) {
                    // Swipe right (left-to-right): go to main menu
                    await flutterTts.stop();
                    await Future.delayed(const Duration(milliseconds: 200));
                    await flutterTts.speak("Going to main menu");
                    await Future.delayed(const Duration(milliseconds: 2500));
                    await Vibration.vibrate(duration: 100);
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (context) => HomeScreen()),
                          (route) => false,
                    );
                  }
                }
              },
              child: Container(
                color: const Color(0xFFF0F4F8), // Light blue-grey background
                child: Column(
                  children: [
                    SizedBox(
                      height: MediaQuery.of(context).size.height / 3,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target: LatLng(
                              widget.currentLocation.latitude,
                              widget.currentLocation.longitude,
                            ),
                            zoom: 12,
                          ),
                          onMapCreated: _onMapCreated,
                          markers: _markers,
                          polylines: _polylines,
                          myLocationEnabled: true,
                          myLocationButtonEnabled: true,
                          zoomControlsEnabled: true,
                          mapToolbarEnabled: true,
                          compassEnabled: true,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : ListView.builder(
                        itemCount: _routes.length,
                        itemBuilder: (context, index) {
                          final route = _routes[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: InkWell(
                              onTap: () => _speakDetailedRoute(index),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          _getTransportIcon(route['type']),
                                          color: Colors.blue,
                                          size: 32,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                route['route'],
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Text(
                                                'Total: ${route['duration']}',
                                                style: const TextStyle(
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.shade50,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            '${route['stops']} trips',
                                            style: TextStyle(
                                              color: Colors.blue.shade700,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    if (route['transitSteps'] != null && route['transitSteps'].isNotEmpty)
                                      ...route['transitSteps'].map<Widget>((step) {
                                        // For walking trips, show simplified view
                                        if (step['vehicle_type'] == 'WALKING') {
                                          return Padding(
                                            padding: const EdgeInsets.only(bottom: 8),
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 24,
                                                  height: 24,
                                                  decoration: BoxDecoration(
                                                    color: Colors.blue.shade50,
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: const Icon(
                                                    Icons.directions_walk,
                                                    size: 16,
                                                    color: Colors.blue,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Expanded(
                                                            child: const Text(
                                                              'Walking',
                                                              style: TextStyle(
                                                                fontWeight: FontWeight.w500,
                                                              ),
                                                            ),
                                                          ),
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(
                                                              horizontal: 8,
                                                              vertical: 2,
                                                            ),
                                                            decoration: BoxDecoration(
                                                              color: Colors.grey.shade100,
                                                              borderRadius: BorderRadius.circular(8),
                                                            ),
                                                            child: Text(
                                                              step['trip_time'] ?? '15 mins',
                                                              style: TextStyle(
                                                                color: Colors.grey.shade700,
                                                                fontSize: 12,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      Text(
                                                        step['walking_distance'] ?? '500m',
                                                        style: const TextStyle(
                                                          color: Colors.grey,
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }

                                        return Padding(
                                          padding: const EdgeInsets.only(bottom: 8),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 24,
                                                height: 24,
                                                decoration: BoxDecoration(
                                                  color: Colors.blue.shade50,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(
                                                  _getTransportIcon(step['vehicle_type']),
                                                  size: 16,
                                                  color: Colors.blue.shade700,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            step['line_name'],
                                                            style: const TextStyle(
                                                              fontWeight: FontWeight.w500,
                                                            ),
                                                          ),
                                                        ),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                            vertical: 2,
                                                          ),
                                                          decoration: BoxDecoration(
                                                            color: Colors.grey.shade100,
                                                            borderRadius: BorderRadius.circular(8),
                                                          ),
                                                          child: Text(
                                                            step['trip_time'] ?? '15 mins',
                                                            style: TextStyle(
                                                              color: Colors.grey.shade700,
                                                              fontSize: 12,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    Text(
                                                      '${step['departure_stop']} → ${step['arrival_stop']}',
                                                      style: const TextStyle(
                                                        color: Colors.grey,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                    if (step['stations_between'] != null)
                                                      Padding(
                                                        padding: const EdgeInsets.only(top: 2),
                                                        child: Text(
                                                          '${step['stations_between']} stations to ${step['arrival_stop']}',
                                                          style: TextStyle(
                                                            color: Colors.grey.shade600,
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                      ),
                                                    if (step['walking_time'] != null)
                                                      Padding(
                                                        padding: const EdgeInsets.only(top: 4),
                                                        child: Row(
                                                          children: [
                                                            const Icon(
                                                              Icons.directions_walk,
                                                              size: 14,
                                                              color: Colors.grey,
                                                            ),
                                                            const SizedBox(width: 4),
                                                            Text(
                                                              step['walking_time'],
                                                              style: const TextStyle(
                                                                color: Colors.grey,
                                                                fontSize: 12,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    const SizedBox(height: 8),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    flutterTts.stop();
    _mapController?.dispose();
    super.dispose();
  }
}