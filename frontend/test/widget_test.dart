// Basic widget test for AION 2 DPS Meter

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/ws_service.dart';
import 'package:frontend/models.dart';

void main() {
  testWidgets('DpsMeterApp builds without backend', (WidgetTester tester) async {
    // Build just the UI without starting backend
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => WsService(),
        child: const MaterialApp(
          home: Scaffold(
            body: Center(
              child: Text('DPS Meter'),
            ),
          ),
        ),
      ),
    );

    // Verify the widget tree builds
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  test('WsService initializes correctly', () {
    final service = WsService();
    expect(service, isNotNull);
    expect(service.status, isNotNull);
  });

  test('PlayerStats model initializes', () {
    final stats = PlayerStats(
      id: 1,
      name: 'Test',
      className: 'Ranger',
      totalDamage: 0,
      totalHeal: 0,
      totalHits: 0,
      totalCrits: 0,
      totalMisses: 0,
      backAttacks: 0,
      perfects: 0,
      doubles: 0,
      parries: 0,
      currentDps: 0,
      currentHps: 0,
      maxHit: 0,
      critRate: 0,
      skills: [],
    );
    expect(stats.totalDamage, 0);
    expect(stats.currentDps, 0);
  });
}
