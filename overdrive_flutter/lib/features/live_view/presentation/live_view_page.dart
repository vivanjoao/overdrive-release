import 'package:flutter/material.dart';

import '../../../shared/widgets/coming_soon.dart';

/// Live multi-camera viewer.
///
/// Will render the panoramic / per-camera feeds streamed over WebSocket /
/// WebCodecs from the head unit. Replaces the existing web/local/live-view
/// HTML page. Implemented in a later module.
class LiveViewPage extends StatelessWidget {
  const LiveViewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live View')),
      body: const ComingSoonPage(
        title: 'Live View',
        icon: Icons.videocam_outlined,
        step: 'Module: Streaming + Live View',
      ),
    );
  }
}
