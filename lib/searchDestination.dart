import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class SearchDestination extends StatefulWidget {
  const SearchDestination({super.key});

  @override
  State<SearchDestination> createState() => _SearchDestinationState();
}

class _SearchDestinationState extends State<SearchDestination> {
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Circle> _circles = {};
  Position? _currentPosition;
  final TextEditingController _searchController = TextEditingController();
  List<String> _recentSearches = [];
  List<Map<String, dynamic>> _suggestions = [];
  bool _isLoading = false;
  bool _isMapCreated = false;
  static const String _apiKey = 'AIzaSyCnLmkL79qMenl0Sn7N4KN38RSoayv-_Bs'; // Replace with your API key
  static const double _searchRadius = 5000; // 5km radius

  @override
  void initState() {
    super.initState();
    _loadRecentSearches();
    _initializeLocation();
  }

  Future<void> _loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _recentSearches = prefs.getStringList('recentSearches') ?? [];
    });
  }

  Future<void> _saveRecentSearch(String search) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> searches = prefs.getStringList('recentSearches') ?? [];
    if (!searches.contains(search)) {
      searches.insert(0, search);
      if (searches.length > 5) searches.removeLast();
      await prefs.setStringList('recentSearches', searches);
      setState(() {
        _recentSearches = searches;
      });
    }
  }

  Future<void> _initializeLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location services are disabled. Please enable location services.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Location permissions are denied. Please enable location permissions in settings.'),
                duration: Duration(seconds: 3),
              ),
            );
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permissions are permanently denied. Please enable location permissions in settings.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      setState(() => _isLoading = true);

      // Get last known position first
      Position? lastPosition = await Geolocator.getLastKnownPosition();
      if (lastPosition != null) {
        setState(() {
          _currentPosition = lastPosition;
        });
        if (_isMapCreated) {
          _updateCameraPosition(lastPosition);
          _addCurrentLocationMarker(lastPosition);
        }
      }

      // Then get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );

      if (mounted) {
        setState(() {
          _currentPosition = position;
          _isLoading = false;
        });
        if (_isMapCreated) {
          _updateCameraPosition(position);
          _addCurrentLocationMarker(position);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error getting location: ${e.toString()}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      print('Error getting location: $e');
    }
  }

  void _updateCameraPosition(Position position) {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(position.latitude, position.longitude),
          zoom: 12,
        ),
      ),
    );
  }

  void _addCurrentLocationMarker(Position position) {
    setState(() {
      _markers.add(
        Marker(
          markerId: const MarkerId('currentLocation'),
          position: LatLng(position.latitude, position.longitude),
          infoWindow: const InfoWindow(title: 'Current Location'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );

      // Add circle to show search radius
      _circles.add(
        Circle(
          circleId: const CircleId('searchRadius'),
          center: LatLng(position.latitude, position.longitude),
          radius: _searchRadius,
          fillColor: Colors.blue.withOpacity(0.1),
          strokeColor: Colors.blue.withOpacity(0.3),
          strokeWidth: 2,
        ),
      );
    });
  }

  Future<void> _searchPlaces(String query) async {
    if (query.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }

    try {
      String locationParam = '';
      if (_currentPosition != null) {
        locationParam = '&location=${_currentPosition!.latitude},${_currentPosition!.longitude}&radius=5000';
      }

      final response = await http.get(
        Uri.parse(
          'https://maps.googleapis.com/maps/api/place/autocomplete/json'
              '?input=$query'
              '&key=$_apiKey'
              '$locationParam',
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['predictions'] != null) {
          final predictions = data['predictions'] as List;
          setState(() {
            _suggestions = predictions.map((prediction) {
              return {
                'place_id': prediction['place_id'] ?? '',
                'structured_formatting': {
                  'main_text': prediction['structured_formatting']?['main_text'] ?? '',
                  'secondary_text': prediction['structured_formatting']?['secondary_text'] ?? '',
                },
              };
            }).toList();
          });
        } else {
          setState(() => _suggestions = []);
        }
      }
    } catch (e) {
      print('Error searching places: $e');
      setState(() => _suggestions = []);
    }
  }

  Future<void> _getPlaceDetails(String placeId) async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://maps.googleapis.com/maps/api/place/details/json'
              '?place_id=$placeId'
              '&key=$_apiKey'
              '&fields=geometry,formatted_address,name',
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final result = data['result'];
          final location = result['geometry']['location'];
          final latLng = LatLng(location['lat'], location['lng']);

          // Add marker for selected place
          setState(() {
            _markers.add(
              Marker(
                markerId: MarkerId(placeId),
                position: latLng,
                infoWindow: InfoWindow(
                  title: result['name'],
                  snippet: result['formatted_address'],
                ),
              ),
            );
          });

          // Move camera to selected place
          _mapController?.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: latLng,
                zoom: 15,
              ),
            ),
          );

          // Save to recent searches
          _saveRecentSearch(result['name']);
        }
      }
    } catch (e) {
      print('Error getting place details: $e');
    }
  }

  void _onSearchChanged(String value) {
    _searchPlaces(value);
  }

  void _onMapCreated(GoogleMapController controller) async {
    _mapController = controller;
    setState(() => _isMapCreated = true);

    // Set map style to show buildings and landmarks
    String mapStyle = '''
      [
        {
          "featureType": "all",
          "elementType": "geometry",
          "stylers": [
            {
              "visibility": "on"
            }
          ]
        },
        {
          "featureType": "landscape",
          "elementType": "geometry",
          "stylers": [
            {
              "visibility": "on"
            }
          ]
        },
        {
          "featureType": "poi",
          "elementType": "geometry",
          "stylers": [
            {
              "visibility": "on"
            }
          ]
        },
        {
          "featureType": "road",
          "elementType": "geometry",
          "stylers": [
            {
              "visibility": "on"
            }
          ]
        },
        {
          "featureType": "water",
          "elementType": "geometry",
          "stylers": [
            {
              "visibility": "on"
            }
          ]
        }
      ]
    ''';

    await controller.setMapStyle(mapStyle);

    if (_currentPosition != null) {
      _updateCameraPosition(_currentPosition!);
      _addCurrentLocationMarker(_currentPosition!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF235DFF),
        toolbarHeight: 60,
        leading: Padding(
          padding: const EdgeInsets.all(2.0),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        title: const Padding(
          padding: EdgeInsets.all(2.0),
          child: Text(
            'Search Destination',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search destination...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey[100],
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          if (_suggestions.isNotEmpty)
            Expanded(
              flex: 1,
              child: ListView.builder(
                itemCount: _suggestions.length,
                itemBuilder: (context, index) {
                  final suggestion = _suggestions[index];
                  final mainText = suggestion['structured_formatting']?['main_text'] ?? '';
                  final secondaryText = suggestion['structured_formatting']?['secondary_text'] ?? '';
                  return ListTile(
                    leading: const Icon(Icons.location_on),
                    title: Text(mainText),
                    subtitle: Text(secondaryText),
                    onTap: () {
                      _searchController.text = mainText;
                      if (suggestion['place_id'] != null) {
                        _getPlaceDetails(suggestion['place_id']);
                      }
                      setState(() => _suggestions = []);
                    },
                  );
                },
              ),
            ),
          if (_recentSearches.isNotEmpty && _suggestions.isEmpty)
            Expanded(
              flex: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text(
                      'Recent Searches',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _recentSearches.length,
                      itemBuilder: (context, index) {
                        return ListTile(
                          leading: const Icon(Icons.history),
                          title: Text(_recentSearches[index]),
                          onTap: () {
                            _searchController.text = _recentSearches[index];
                            setState(() => _suggestions = []);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            flex: 2,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _currentPosition == null
                ? const Center(child: Text('Unable to get current location'))
                : Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: LatLng(
                      _currentPosition!.latitude,
                      _currentPosition!.longitude,
                    ),
                    zoom: 15,
                    tilt: 45,
                  ),
                  onMapCreated: _onMapCreated,
                  markers: _markers,
                  circles: _circles,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  zoomControlsEnabled: true,
                  mapToolbarEnabled: true,
                  compassEnabled: true,
                  liteModeEnabled: false,
                  buildingsEnabled: true,
                  indoorViewEnabled: true,
                  trafficEnabled: true,
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
    _searchController.dispose();
    _mapController?.dispose();
    super.dispose();
  }
}
