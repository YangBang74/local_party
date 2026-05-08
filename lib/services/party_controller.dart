import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

import '../packet_codec.dart';
import 'audio_bridge.dart';
import 'clock_sync.dart';

const String kNearbyServiceId = 'com.localparty.app';
const int kPlaybackDelayMs = 250;

enum PartyUiPhase { lobby, room }

/// Orchestrates Nearby, clock sync, capture/playback, handover.
class PartyController extends ChangeNotifier {
  PartyController({
    AudioBridge? audioBridge,
    Nearby? nearby,
    GlobalKey<ScaffoldMessengerState>? scaffoldMessengerKey,
  })  : _audio = audioBridge ?? AudioBridge(),
        _nearby = nearby ?? Nearby(),
        _scaffoldMessengerKey = scaffoldMessengerKey;

  final AudioBridge _audio;
  final Nearby _nearby;
  final GlobalKey<ScaffoldMessengerState>? _scaffoldMessengerKey;
  final ClockSync clock = ClockSync();

  String nickname = 'Guest';
  PartyUiPhase phase = PartyUiPhase.lobby;

  bool advertising = false;
  bool discovering = false;

  /// User chose «Создать комнату» → becomes DJ when connected.
  bool _createdRoom = false;

  String? peerEndpointId;

  /// This device is the DJ (captures & sends).
  bool iAmDj = false;

  /// DJ capture pipeline running (projection granted & service up).
  bool capturing = false;

  double meterLevel = 0;

  final Map<String, String> discoveredEndpoints = {};

  StreamSubscription<Map<String, dynamic>>? _pcmSub;
  Timer? _pingTimer;

  /// Guest waiting for handover_ack after sending request.
  bool _awaitingHandoverAck = false;

  bool get awaitingHandoverAck => _awaitingHandoverAck;

  bool get isConnected => peerEndpointId != null;

  void setCreatedRoomIntent(bool created) {
    _createdRoom = created;
  }

  void _showSnack(String message) {
    final messenger = _scaffoldMessengerKey?.currentState;
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> ensurePermissions() async {
    final statuses = await <Permission>[
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.nearbyWifiDevices,
      Permission.locationWhenInUse,
      Permission.microphone,
      Permission.notification,
    ].request();

    final denied = statuses.entries.where((e) => !e.value.isGranted).toList();
    if (denied.isNotEmpty && kDebugMode) {
      debugPrint('Some permissions not granted: $denied');
    }
    return statuses[Permission.microphone]?.isGranted ?? false;
  }

  Future<void> createRoom() async {
    if (!await ensurePermissions()) return;
    discoveredEndpoints.clear();
    await _nearby.stopDiscovery();
    await _nearby.stopAdvertising();

    final ok = await _nearby.startAdvertising(
      nickname,
      Strategy.P2P_STAR,
      serviceId: kNearbyServiceId,
      onConnectionInitiated: (id, info) async {
        await _nearby.acceptConnection(
          id,
          onPayLoadRecieved: _onPayload,
        );
      },
      onConnectionResult: _onConnectionResult,
      onDisconnected: _onDisconnected,
    );
    advertising = ok;
    discovering = false;
    notifyListeners();
  }

  Future<void> startFindingRooms() async {
    if (!await ensurePermissions()) return;
    await _nearby.stopAdvertising();
    advertising = false;
    discoveredEndpoints.clear();

    final ok = await _nearby.startDiscovery(
      nickname,
      Strategy.P2P_STAR,
      serviceId: kNearbyServiceId,
      onEndpointFound: (id, name, serviceId) {
        discoveredEndpoints[id] = name;
        notifyListeners();
      },
      onEndpointLost: (id) {
        if (id != null) discoveredEndpoints.remove(id);
        notifyListeners();
      },
    );
    discovering = ok;
    notifyListeners();
  }

  Future<void> connectToEndpoint(String endpointId) async {
    await _nearby.requestConnection(
      nickname,
      endpointId,
      onConnectionInitiated: (id, info) async {
        await _nearby.acceptConnection(
          id,
          onPayLoadRecieved: _onPayload,
        );
      },
      onConnectionResult: _onConnectionResult,
      onDisconnected: _onDisconnected,
    );
  }

  void _onConnectionResult(String endpointId, Status status) {
    if (status == Status.CONNECTED) {
      peerEndpointId = endpointId;
      discovering = false;
      advertising = false;
      iAmDj = _createdRoom;
      phase = PartyUiPhase.room;
      unawaited(_nearby.stopDiscovery());
      unawaited(_nearby.stopAdvertising());
      unawaited(_afterConnected());
      notifyListeners();
    }
  }

  Future<void> _afterConnected() async {
    if (iAmDj) {
      await _audio.stopPlayback();
      capturing = false;
      _pingTimer?.cancel();
    } else {
      await _pcmSub?.cancel();
      _pcmSub = null;
      await _audio.stopCaptureService();
      capturing = false;
      await _audio.startPlayback();
      _startGuestPing();
    }
  }

  /// DJ taps «Начать захват» — системный диалог MediaProjection.
  Future<void> startDjCapture() async {
    if (!iAmDj || capturing || peerEndpointId == null) return;
    final okProj = await _audio.requestMediaProjection();
    if (!okProj) return;

    await _pcmSub?.cancel();
    await _audio.startCaptureService();

    capturing = true;
    notifyListeners();

    _pcmSub = _audio.pcmCaptureStream().listen((event) async {
      final peer = peerEndpointId;
      if (peer == null || !iAmDj || !capturing) return;
      final pcm = event['pcm'];
      final ms = event['captureUtcMs'];
      if (pcm is! Uint8List || ms is! int) return;
      final packet = encodeAudioPacket(ms, pcm);
      try {
        await _nearby.sendBytesPayload(peer, packet);
      } catch (_) {}
      meterLevel = await _audio.pcmLevel(pcm);
      notifyListeners();
    });
  }

  Future<void> stopDjCapture() async {
    if (!capturing) return;
    await _pcmSub?.cancel();
    _pcmSub = null;
    await _audio.stopCaptureService();
    capturing = false;
    meterLevel = 0;
    notifyListeners();
  }

  void _startGuestPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final peer = peerEndpointId;
      if (peer == null || iAmDj || capturing) return;
      final gs = DateTime.now().millisecondsSinceEpoch;
      final ping = encodeControlJson(<String, dynamic>{
        't': 'ping',
        'gs': gs,
      });
      try {
        await _nearby.sendBytesPayload(peer, ping);
      } catch (_) {}
    });
  }

  Future<void> _onPayload(String endpointId, Payload payload) async {
    final bytes = payload.bytes;
    if (bytes == null || bytes.isEmpty) return;

    final audio = decodeAudioPacketIfAny(bytes);
    if (audio != null) {
      final captureMs = audio.$1;
      final pcm = audio.$2;
      if (iAmDj) return;
      final deadline = clock.guestPlaybackDeadlineMs(
        captureHostUtcMs: captureMs,
        fixedDelayMs: kPlaybackDelayMs,
      );
      await _audio.feedPcm(playAtUtcMs: deadline, pcm: pcm);
      meterLevel = await _audio.pcmLevel(pcm);
      notifyListeners();
      return;
    }

    final ctrl = tryDecodeControlJson(bytes);
    if (ctrl == null) return;

    final type = ctrl['t'] as String?;

    if (type == 'ping' && iAmDj) {
      final gs = ctrl['gs'];
      final reply = encodeControlJson(<String, dynamic>{
        't': 'pong',
        'gs': gs,
        'hr': DateTime.now().millisecondsSinceEpoch,
      });
      try {
        await _nearby.sendBytesPayload(endpointId, reply);
      } catch (_) {}
    }

    if (type == 'pong' && !iAmDj) {
      final gs = (ctrl['gs'] as num?)?.toInt();
      final hr = (ctrl['hr'] as num?)?.toInt();
      if (gs != null && hr != null) {
        clock.recordRoundTrip(
          guestSendMs: gs,
          hostReplyMs: hr,
          guestRecvMs: DateTime.now().millisecondsSinceEpoch,
        );
      }
    }

    if (type == 'handover_request' && iAmDj) {
      await stopDjCapture();
      final ack = encodeControlJson(<String, dynamic>{'t': 'handover_ack'});
      try {
        await _nearby.sendBytesPayload(endpointId, ack);
      } catch (_) {}
      iAmDj = false;
      notifyListeners();
      await _audio.startPlayback();
      _startGuestPing();
    }

    if (type == 'handover_ack' && _awaitingHandoverAck) {
      _awaitingHandoverAck = false;
      iAmDj = true;
      notifyListeners();
      await _audio.stopPlayback();
      _pingTimer?.cancel();
      await startDjCapture();
    }
  }

  Future<void> requestBecomeDj() async {
    final peer = peerEndpointId;
    if (peer == null || iAmDj || _awaitingHandoverAck) return;
    _awaitingHandoverAck = true;
    notifyListeners();
    final req = encodeControlJson(<String, dynamic>{'t': 'handover_request'});
    try {
      await _nearby.sendBytesPayload(peer, req);
    } catch (_) {
      _awaitingHandoverAck = false;
      notifyListeners();
    }
  }

  Future<void> leaveRoom() async {
    _pingTimer?.cancel();
    _pingTimer = null;
    await _pcmSub?.cancel();
    _pcmSub = null;
    await stopDjCapture();
    await _audio.stopCaptureService();
    await _audio.stopPlayback();
    await _nearby.stopAllEndpoints();
    peerEndpointId = null;
    iAmDj = false;
    _createdRoom = false;
    capturing = false;
    _awaitingHandoverAck = false;
    phase = PartyUiPhase.lobby;
    meterLevel = 0;
    discoveredEndpoints.clear();
    notifyListeners();
  }

  void _onDisconnected(String endpointId) {
    _showSnack('Удалённое устройство отключилось');
    unawaited(leaveRoom());
  }

  @override
  void dispose() {
    unawaited(_pcmSub?.cancel());
    _pingTimer?.cancel();
    super.dispose();
  }
}
