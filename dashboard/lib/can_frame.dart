class CanFrame {
  final int canId;
  final bool isExtended;
  final int dlc;
  final List<int> data;
  final int frameInfo;

  const CanFrame({
    required this.canId,
    required this.isExtended,
    required this.dlc,
    required this.data,
    required this.frameInfo,
  });

  String get canIdHex {
    final width = isExtended ? 8 : 3;
    return '0x${canId.toRadixString(16).padLeft(width, '0').toUpperCase()}';
  }

  String get dataHex {
    return data
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
  }

  // -------------------------------------------------------------
  // Decode Date & Time from payload index (0 to 5)
  // -------------------------------------------------------------
// -------------------------------------------------------------
// Decode Date & Time from payload bytes
// -------------------------------------------------------------
DateTime? get timestamp {
  // Requires at least 6 bytes in payload
  if (data.length < 6) {
    return null;
  }

  // Allow 0x206, 0x0206, 0x0202, and 0x202
  final validTimeIds = {0x0202, 0x202, 0x0206, 0x206};    //valid canID
  if (!validTimeIds.contains(canId)) {
    return null;
  }

  try {
    int year, month, day, hour, minute, second;

    // Check if byte 0 is year (YY-MM-DD) or day (DD-MM-YY)
    if (data[0] <= 31 && data[2] >= 20) {
      // Layout: [Day, Month, Year, Hour, Min, Sec]
      day = data[0];
      month = data[1];
      year = data[2];
    } else {
      // Layout: [Year, Month, Day, Hour, Min, Sec]
      year = data[0];
      month = data[1];
      day = data[2];
    }

    hour = data[3];
    minute = data[4];
    second = data[5];

    // Adjust 2-digit year (e.g., 26 -> 2026)
    if (year < 100) {
      year += 2000;
    }

    // Clamp/Validate values to prevent DateTime crash
    if (month < 1 || month > 12 || day < 1 || day > 31) {
      return null;
    }

    return DateTime(
      year,
      month,
      day,
      hour.clamp(0, 23),
      minute.clamp(0, 59),
      second.clamp(0, 59),
    );
  } catch (_) {
    return null;
  }
}
  String get formattedDateTime {
    final dt = timestamp;
    if (dt == null) return 'N/A';

    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');

    return '$y-$m-$d $hh:$mm:$ss';
  }

  @override
  String toString() {
    return 'CAN ID=$canIdHex EXT=$isExtended DLC=$dlc TIME=$formattedDateTime DATA=[$dataHex]';
  }
}