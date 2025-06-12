import 'dart:math';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

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

  @override
  void initState() {
    super.initState();
    _addMarkers();
    _loadTransportRoutes();
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
              '&transit_mode=bus|subway|train|tram|rail'  // Specify all transit modes
              '&transit_routing_preference=less_walking'  // Prefer routes with less walking
              '&language=en'
              '&region=my'  // Set region to Malaysia
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

            // Get detailed transit information
            String transportType = 'WALKING';
            String lineName = '';
            String lineColor = '';
            String vehicleType = '';
            String vehicleName = '';

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
              'route': lineName.isNotEmpty ? lineName : 'Route ${_routes.length + 1}',
              'duration': legs['duration']['text'],
              'stops': transitSteps.length,
              'price': 'Free', // You might want to get this from a different API
              'schedule': 'Every 15 mins', // You might want to get this from a different API
              'path': steps.map((step) => LatLng(step['start_location']['lat'], step['start_location']['lng'])).toList(),
              'lineColor': lineColor,
              'vehicleName': vehicleName,
              'transitSteps': transitSteps.map((step) {
                final details = step['transit_details'];
                return {
                  'departure_stop': details['departure_stop']['name'],
                  'arrival_stop': details['arrival_stop']['name'],
                  'line_name': details['line']['name'],
                  'vehicle_type': details['line']['vehicle']['type'],
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
        }
      }
    } catch (e) {
      print('Error loading routes: $e');
      // Fallback to mock data if API fails
      _routes = [
        {
          'type': 'BUS',
          'route': 'Route 1',
          'duration': '25 mins',
          'stops': 5,
          'price': '\$2.50',
          'schedule': 'Every 15 mins',
          'path': [
            LatLng(
              widget.currentLocation.latitude,
              widget.currentLocation.longitude,
            ),
            LatLng(
              (widget.currentLocation.latitude + widget.destination.latitude) / 2,
              (widget.currentLocation.longitude + widget.destination.longitude) / 2,
            ),
            widget.destination,
          ],
        },
        {
          'type': 'TRAIN',
          'route': 'Route 2',
          'duration': '15 mins',
          'stops': 2,
          'price': '\$3.50',
          'schedule': 'Every 10 mins',
          'path': [
            LatLng(
              widget.currentLocation.latitude,
              widget.currentLocation.longitude,
            ),
            LatLng(
              widget.currentLocation.latitude + 0.01,
              widget.currentLocation.longitude + 0.01,
            ),
            widget.destination,
          ],
        },
        {
          'type': 'BUS + TRAIN',
          'route': 'Route 3',
          'duration': '20 mins',
          'stops': 3,
          'price': '\$4.00',
          'schedule': 'Every 20 mins',
          'path': [
            LatLng(
              widget.currentLocation.latitude,
              widget.currentLocation.longitude,
            ),
            LatLng(
              widget.destination.latitude - 0.01,
              widget.destination.longitude - 0.01,
            ),
            widget.destination,
          ],
        },
      ];
    } finally {
      setState(() {
        _isLoading = false;
      });
    }

    _drawRoutes();
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
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Text(
                            'Transportation Route',
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
                    const SizedBox(width: 48), // For balance
                  ],
                ),
              ),
            ),
          ),
          // Main content
          Expanded(
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
                          child: ListTile(
                            leading: Icon(
                              _getTransportIcon(route['type']),
                              color: Colors.blue,
                              size: 32,
                            ),
                            title: Text(route['route']),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Duration: ${route['duration']}'),
                                Text('Stops: ${route['stops']}'),
                                Text('Price: ${route['price']}'),
                                Text('Schedule: ${route['schedule']}'),
                              ],
                            ),
                            isThreeLine: true,
                            onTap: () {
                              // TODO: Show detailed route view
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}