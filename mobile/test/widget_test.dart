import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sorynth/features/welcome/welcome_screen.dart';
import 'package:sorynth/shared/widgets/sorynth_logo.dart';
import 'package:sorynth/shared/widgets/status_badge.dart';
import 'package:sorynth/core/constants/app_constants.dart';

void main() {
  testWidgets('SorynthLogo displays brand name and tagline',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SorynthLogo(size: 80, showText: true),
        ),
      ),
    );

    expect(find.text('SORYNTH'), findsOneWidget);
    expect(find.text('SIGNAL BEYOND BOUNDARIES'), findsOneWidget);
  });

  testWidgets('StatusBadge renders correct status and semantics',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusBadge(status: EmergencyStatus.relayed),
        ),
      ),
    );

    expect(find.text('Relay Received (Multi-Hop)'), findsOneWidget);
    expect(find.byIcon(Icons.hub_rounded), findsOneWidget);
  });

  testWidgets('WelcomeScreen displays Guest SOS and Sign In options',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: WelcomeScreen(),
        ),
      ),
    );

    expect(find.text('EMERGENCY SOS'), findsOneWidget);
    expect(find.text('Instant Rescue • No Login Required'), findsOneWidget);
    expect(find.text('Sign In to Account'), findsOneWidget);
  });
}
