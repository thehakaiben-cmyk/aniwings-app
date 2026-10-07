import 'package:intl/intl.dart';

/// HTTP dates come from the media origin. Check only large clock differences;
/// small offsets do not explain certificate validity errors.
String? playbackClockError(
  String? serverDate,
  DateTime deviceTime, {
  String? responseAge,
}) {
  if (serverDate == null) return null;
  try {
    final serverTime = DateFormat(
      'EEE, dd MMM yyyy HH:mm:ss',
      'en_US',
    ).parseUtc(serverDate.replaceFirst(RegExp(r'\s+GMT$'), ''));
    final age = int.tryParse(responseAge ?? '') ?? 0;
    final difference = serverTime
        .add(Duration(seconds: age))
        .difference(deviceTime.toUtc())
        .abs();
    if (difference <= const Duration(days: 1)) return null;
    return 'Your device date/time is incorrect. Correct it in system Date & time settings, then retry playback.';
  } catch (_) {
    return null;
  }
}
