import 'package:flutter/material.dart';

import '../../../shared/widgets/coming_soon.dart';

/// Remote sentry-mode control + event feed.
///
/// Will surface arm/disarm, ROI/schedule config, and the live motion-event
/// list, mirroring the web/local/surveillance.html page. Implemented later.
class SurveillancePage extends StatelessWidget {
  const SurveillancePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Surveillance')),
      body: const ComingSoonPage(
        title: 'Surveillance',
        icon: Icons.shield_outlined,
        step: 'Module: Surveillance',
      ),
    );
  }
}
