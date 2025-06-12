import 'package:flutter/material.dart';
import 'package:fyp/navigationModule/transportRoute.dart';
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
      // Get current position for location bias
      final position = await _getCurrentPosition();
      String locationBias = '';

      if (position != null) {
        locationBias = '&location=${position.latitude},${position.longitude}&radius=50000';
      }

      // Determine if the query looks like an address
      bool isAddressQuery = query.contains(',') ||
          query.contains('street') ||
          query.contains('road') ||
          query.contains('jalan') ||
          query.contains('jln') ||
          query.contains('taman') ||
          query.contains('kampung');

      // Use geocode for address-like queries, otherwise use establishment
      String types = isAddressQuery ? 'geocode' : 'establishment';

      final url = 'https://maps.googleapis.com/maps/api/place/autocomplete/json'
          '?input=$query'
          '&types=$types'
          '&language=en'
          '&components=country:my'  // Restrict to Malaysia
          '$locationBias'
          '&key=AIzaSyCnLmkL79qMenl0Sn7N4KN38RSoayv-_Bs';

      print('Searching with URL: $url'); // Debug log

      final response = await http.get(Uri.parse(url));

      print('Response status: ${response.statusCode}'); // Debug log
      print('Response body: ${response.body}'); // Debug log

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('Decoded data: $data'); // Debug log

        if (data['status'] == 'OK' && data['predictions'] != null) {
          setState(() {
            _suggestions = (data['predictions'] as List).map((prediction) {
              // Get the full description as it might contain more details
              final description = prediction['description'] as String? ?? '';

              // Split the description into name and address
              final parts = description.split(',');
              final name = parts.isNotEmpty ? parts[0].trim() : '';
              final address = parts.length > 1
                  ? parts.sublist(1).join(',').trim()
                  : '';

              return {
                'place_id': prediction['place_id'] ?? '',
                'name': name,
                'address': address,
                'full_description': description,
                'types': (prediction['types'] as List?)?.cast<String>() ?? [],
              };
            }).toList();
          });
          print('Suggestions count: ${_suggestions.length}'); // Debug log
        } else {
          print('No results or error: ${data['status']}'); // Debug log
          setState(() => _suggestions = []);
        }
      } else {
        print('Error response: ${response.statusCode}'); // Debug log
        setState(() => _suggestions = []);
      }
    } catch (e) {
      print('Error searching places: $e');
      setState(() => _suggestions = []);
    }
  }

  Future<void> _getPlaceDetails(String placeId) async {
    try {
      final response = await http.get(Uri.parse(
          'https://maps.googleapis.com/maps/api/place/details/json'
              '?place_id=$placeId'
              '&fields=name,formatted_address,geometry,types,address_components'
              '&language=en'
              '&key=AIzaSyCnLmkL79qMenl0Sn7N4KN38RSoayv-_Bs'
      ));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final result = data['result'];
          final name = result['name'];
          final address = result['formatted_address'];
          final lat = result['geometry']['location']['lat'];
          final lng = result['geometry']['location']['lng'];
          final types = (result['types'] as List?)?.cast<String>() ?? [];

          // Save to recent searches
          await _saveToRecentSearches(name, address, lat, lng);

          // Get current position
          final position = await _getCurrentPosition();
          if (position != null && mounted) {
            // Navigate to transport routes
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => TransportRoutes(
                  destination: LatLng(lat, lng),
                  destinationName: name,
                  currentLocation: position,
                ),
              ),
            );
          }
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
                        'Optichat',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
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
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search for a place or address',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                      ),
                      onTap: () {
                        setState(() => _suggestions = []);
                      },
                      onChanged: (value) {
                        print('Searching for: $value');
                        _searchPlaces(value);
                      },
                    ),
                  ),
                  Expanded(
                    child: _suggestions.isNotEmpty
                        ? ListView.builder(
                      itemCount: _suggestions.length,
                      itemBuilder: (context, index) {
                        final suggestion = _suggestions[index];
                        return ListTile(
                          leading: const Icon(Icons.location_on),
                          title: Text(suggestion['name']),
                          subtitle: Text(suggestion['address']),
                          onTap: () => _getPlaceDetails(suggestion['place_id']),
                        );
                      },
                    )
                        : FutureBuilder<List<Map<String, dynamic>>>(
                      future: _getRecentSearches(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        if (!snapshot.hasData || snapshot.data!.isEmpty) {
                          return const Center(
                            child: Text(
                              'No recent searches',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
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
                                padding: EdgeInsets.zero,
                                itemCount: snapshot.data!.length,
                                itemBuilder: (context, index) {
                                  final search = snapshot.data![index];
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                    leading: const Icon(Icons.history),
                                    title: Text(search['name']),
                                    subtitle: Text(search['address']),
                                    onTap: () async {
                                      final position = await _getCurrentPosition();
                                      if (position != null && mounted) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => TransportRoutes(
                                              destination: LatLng(
                                                search['latitude'],
                                                search['longitude'],
                                              ),
                                              destinationName: search['name'],
                                              currentLocation: position,
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
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

  IconData _getPlaceIcon(String type) {
    switch (type.toLowerCase()) {
      case 'restaurant':
        return Icons.restaurant;
      case 'shopping':
        return Icons.shopping_bag;
      case 'entertainment':
        return Icons.movie;
      case 'transportation':
        return Icons.directions_transit;
      case 'education':
        return Icons.school;
      case 'health':
        return Icons.local_hospital;
      default:
        return Icons.place;
    }
  }

  Future<List<Map<String, dynamic>>> _getPopularLocations() async {
    try {
      final position = await _getCurrentPosition();
      if (position == null) return [];

      final response = await http.get(Uri.parse(
          'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
              '?location=${position.latitude},${position.longitude}'
              '&radius=2000'
              '&type=point_of_interest'
              '&key=AIzaSyCnLmkL79qMenl0Sn7N4KN38RSoayv-_Bs'
      ));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          return (data['results'] as List).map((place) {
            return {
              'name': place['name'],
              'address': place['vicinity'],
              'latitude': place['geometry']['location']['lat'],
              'longitude': place['geometry']['location']['lng'],
              'type': place['types']?.first ?? 'point_of_interest',
            };
          }).toList();
        }
      }
      return [];
    } catch (e) {
      print('Error getting popular locations: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _getRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    final searches = prefs.getStringList('recent_searches') ?? [];
    return searches.map((search) {
      final parts = search.split('|');
      return {
        'name': parts[0],
        'address': parts[1],
        'latitude': double.parse(parts[2]),
        'longitude': double.parse(parts[3]),
      };
    }).toList();
  }

  Future<void> _saveToRecentSearches(String name, String address, double lat, double lng) async {
    final prefs = await SharedPreferences.getInstance();
    final searches = prefs.getStringList('recent_searches') ?? [];

    // Create the search entry
    final search = '$name|$address|$lat|$lng';

    // Remove if already exists
    searches.removeWhere((s) => s.startsWith('$name|'));

    // Add to the beginning of the list
    searches.insert(0, search);

    // Keep only the last 10 searches
    if (searches.length > 10) {
      searches.removeLast();
    }

    await prefs.setStringList('recent_searches', searches);
  }

  Future<Position?> _getCurrentPosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled
      return null;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Permissions are denied
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Permissions are permanently denied
      return null;
    }

    // When we reach here, permissions are granted and we can
    // continue accessing the position of the device.
    return await Geolocator.getCurrentPosition();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _mapController?.dispose();
    super.dispose();
  }
}
