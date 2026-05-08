import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/lobby_screen.dart';
import 'screens/room_screen.dart';
import 'services/party_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  runApp(
    ChangeNotifierProvider(
      create: (_) =>
          PartyController(scaffoldMessengerKey: scaffoldMessengerKey),
      child: LocalPartyApp(scaffoldMessengerKey: scaffoldMessengerKey),
    ),
  );
}

class LocalPartyApp extends StatelessWidget {
  const LocalPartyApp({super.key, required this.scaffoldMessengerKey});

  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      title: 'Local Party',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const PartyNavigator(),
    );
  }
}

class PartyNavigator extends StatelessWidget {
  const PartyNavigator({super.key});

  @override
  Widget build(BuildContext context) {
    final party = context.watch<PartyController>();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: party.phase == PartyUiPhase.room
          ? const RoomScreen(key: ValueKey('room'))
          : const LobbyScreen(key: ValueKey('lobby')),
    );
  }
}
