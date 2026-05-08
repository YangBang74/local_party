import 'package:nearby_connections/nearby_connections.dart';

/// Shared constants for Google Nearby Connections (P2P_STAR).
const String kPartyNearbyServiceId = 'com.localparty.app';

Strategy get partyNearbyStrategy => Strategy.P2P_STAR;
