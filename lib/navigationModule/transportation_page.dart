// import 'package:flutter/material.dart';
//
// class TransportationPage extends StatelessWidget {
//   const TransportationPage({super.key});
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         backgroundColor: const Color(0xFF2561FA),
//         foregroundColor: Colors.white,
//         title: const Text('Transportation'),
//       ),
//       body: const Center(
//         child: Text('Transportation Feature Coming Soon'),
//       ),
//     );
//   }
// }

import 'package:flutter/material.dart';
import 'package:fyp/searchDestination.dart';

class TransportationPage extends StatelessWidget {
  const TransportationPage({super.key});

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
            'OptiChat',
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    // TODO: Navigate to destination search
                    Navigator.push(context, MaterialPageRoute(builder: (context) => SearchDestination()));
                  },
                  child: SizedBox(
                    width: 300,
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
                  onTap: () {
                    // TODO: Navigate to transport schedule
                  },
                  child: SizedBox(
                    width: 300,
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
    );
  }
}
