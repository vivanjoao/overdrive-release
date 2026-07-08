import 'package:flutter/material.dart';

import '../../../shared/widgets/coming_soon.dart';

/// Vehicle control page.
///
/// Will host the 3D BYD model with remote controls (lock/unlock, climate,
/// windows, charge limit, etc.) via BYD Cloud + local HAL. Mirrors
/// web/local/vehicle-control.html. Implemented in a later module.
class VehiclePage extends StatelessWidget {
  const VehiclePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vehicle')),
      body: const ComingSoonPage(
        title: 'Vehicle Control',
        icon: Icons.directions_car_outlined,
        step: 'Module: Vehicle Control + BYD Cloud',
      ),
    );
  }
}
