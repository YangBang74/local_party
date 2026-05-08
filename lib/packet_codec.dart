import 'dart:convert';
import 'dart:typed_data';

/// Magic header for LPCM packets over Nearby BYTES payloads.
const List<int> kLpcMagic = [0x4c, 0x50, 0x43, 0x31]; // "LPC1"

Uint8List encodeAudioPacket(int captureUtcMs, Uint8List pcm) {
  final header = ByteData(16);
  for (var i = 0; i < 4; i++) {
    header.setUint8(i, kLpcMagic[i]);
  }
  header.setInt64(4, captureUtcMs, Endian.big);
  header.setUint32(12, pcm.length, Endian.big);
  final out = BytesBuilder(copy: false);
  out.add(header.buffer.asUint8List());
  out.add(pcm);
  return out.toBytes();
}

/// Returns true if this was a full audio packet and [onAudio] was called.
bool tryDecodeAudioPacket(
  Uint8List data,
  void Function(int captureUtcMs, Uint8List pcm) onAudio,
) {
  final decoded = decodeAudioPacketIfAny(data);
  if (decoded == null) return false;
  onAudio(decoded.$1, decoded.$2);
  return true;
}

/// Returns `(captureUtcMs, pcm)` if [data] is a valid LPC1 packet.
(int, Uint8List)? decodeAudioPacketIfAny(Uint8List data) {
  if (data.length < 16) return null;
  for (var i = 0; i < 4; i++) {
    if (data[i] != kLpcMagic[i]) return null;
  }
  final bd = ByteData.sublistView(data);
  final captureMs = bd.getInt64(4, Endian.big);
  final len = bd.getUint32(12, Endian.big);
  if (len < 0 || 16 + len > data.length) return null;
  final pcm = Uint8List.sublistView(data, 16, 16 + len);
  return (captureMs, pcm);
}

Uint8List encodeControlJson(Map<String, dynamic> json) =>
    Uint8List.fromList(utf8.encode(jsonEncode(json)));

Map<String, dynamic>? tryDecodeControlJson(Uint8List data) {
  try {
    final s = utf8.decode(data);
    final m = jsonDecode(s);
    if (m is Map<String, dynamic>) return m;
    return Map<String, dynamic>.from(m as Map);
  } catch (_) {
    return null;
  }
}
