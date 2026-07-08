import 'package:flutter/material.dart';

import '../../../shared/widgets/coming_soon.dart';

/// Trips browser and Driving DNA scores.
///
/// Will replace web/local/trips.html: trip list, detail view, consumption
/// charts, terrain-aware scoring. Backed by the drift database. Implemented
/// in a later module.
class TripsPage extends StatelessWidget {
  const TripsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trips')),
      body: const ComingSoonPage(
        title: 'Trips',
        icon: Icons.route_outlined,
        step: 'Module: Trips + Driving DNA',
      ),
    );
  }
}
