import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:local_party/main.dart';
import 'package:local_party/services/party_controller.dart';

void main() {
  testWidgets('Lobby loads', (WidgetTester tester) async {
    final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) =>
            PartyController(scaffoldMessengerKey: scaffoldMessengerKey),
        child: LocalPartyApp(scaffoldMessengerKey: scaffoldMessengerKey),
      ),
    );

    expect(find.textContaining('Local Party'), findsWidgets);
    expect(find.textContaining('Создать комнату'), findsOneWidget);
  });
}
