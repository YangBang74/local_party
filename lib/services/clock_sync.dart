/// Estimates host-clock minus guest-clock in milliseconds using ping/pong pairs.
/// Larger negative values mean guest clock is ahead of host (guestMs > hostMs gap).
class ClockSync {
  ClockSync();

  /// Rough estimate: [estimatedHostMs] ≈ [guestLocalMs] + offsetHostMinusGuestMs.
  double offsetHostMinusGuestMs = 0;

  /// Rolling samples for smoothing.
  final List<double> _samples = [];
  static const int _maxSamples = 8;

  /// Guest sends [guestSendMs]; host echoed [hostReplyMs]; guest received at [guestRecvMs].
  void recordRoundTrip({
    required int guestSendMs,
    required int hostReplyMs,
    required int guestRecvMs,
  }) {
    final rtt = (guestRecvMs - guestSendMs).clamp(1, 60000);
    // Approximate simultaneous estimate at midpoint of guest timeline:
    final guestMid = guestSendMs + rtt / 2;
    final sample = hostReplyMs - guestMid;
    _samples.add(sample.toDouble());
    if (_samples.length > _maxSamples) {
      _samples.removeAt(0);
    }
    offsetHostMinusGuestMs =
        _samples.reduce((a, b) => a + b) / _samples.length;
  }

  /// Playback deadline on guest device wall clock (ms since epoch).
  int guestPlaybackDeadlineMs({
    required int captureHostUtcMs,
    required int fixedDelayMs,
  }) {
    final captureOnGuestScale =
        captureHostUtcMs - offsetHostMinusGuestMs.round();
    return captureOnGuestScale + fixedDelayMs;
  }
}
