// // Inside can_frame.dart
// //  this is not required anymore since we are using CanFrame from can_frame.dart instead of CanUFrame from can_udp_frame.dart
// import 'dart:typed_data';

// class CanUFrame {
//   final int id;
//   final bool isExtended;
//   final int dlc;
//   final Uint8List data;
//   final DateTime? timestamp;

//   CanUFrame({
//     required this.id,
//     required this.isExtended,
//     required this.dlc,
//     required this.data,
//     this.timestamp,
//   });

//   /// Decodes raw UDP packet bytes into a CanUFrame
//   factory CanUFrame.fromBytes(Uint8List bytes) {
//     if (bytes.length < 5) {
//       throw FormatException('UDP packet too short to be a valid CAN frame');
//     }

//     // Read 32-bit CAN ID (Big Endian)
//     final ByteData byteData = ByteData.sublistView(bytes);
//     final rawId = byteData.getUint32(0, Endian.big);

//     // Standard SocketCAN flags:
//     // Bit 31: EFF flag (1 = Extended frame, 0 = Standard frame)
//     final isExtended = (rawId & 0x80000000) != 0;
//     final canId = isExtended ? (rawId & 0x1FFFFFFF) : (rawId & 0x7FF);

//     final dlc = bytes[4];
    
//     // Extract payload data
//     final dataBytes = (bytes.length >= 5 + dlc)
//         ? bytes.sublist(5, 5 + dlc)
//         : bytes.sublist(5);

//     return CanUFrame(
//       id: canId,
//       isExtended: isExtended,
//       dlc: dlc,
//       data: Uint8List.fromList(dataBytes),
//       timestamp: DateTime.now(), // optional: attach arrival time
//     );
//   }

//   // Your existing getters (canIdHex, dataHex, formattedDateTime, etc.)
//   String get canIdHex => '0x${id.toRadixString(16).padLeft(isExtended ? 8 : 3, '0').toUpperCase()}';
//   String get dataHex => data.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
//   String get formattedDateTime => timestamp != null ? timestamp.toString() : '';
// }