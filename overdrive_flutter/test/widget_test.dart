// This is a basic unit-test placeholder. The default Flutter template
// creates a smoke test against the demo counter widget, which we replaced.
// Real feature tests live alongside each feature module once implemented.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('MaterialApp smoke test renders a Directionality', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('OverDrive'))),
    );
    expect(find.byType(Directionality), findsOneWidget);
    expect(find.text('OverDrive'), findsOneWidget);
  });
}
