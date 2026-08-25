import 'dart:io';
import 'package:flutter/foundation.dart';

// 1. Import can_frame.dart instead of can_udp_frame.dart
import 'can_frame.dart'; 
import 'can_envelop_parser.dart';

class CanUdpReader {
  final int port;
  RawDatagramSocket? _socket;
  final CanEnvelopeParser _parser = CanEnvelopeParser();

  CanUdpReader({required this.port});

  // 2. Change CanUFrame to CanFrame here
  Future<void> start({
    required Function(CanFrame frame) onFrame,
    required Function(Object error) onError,
  }) async {
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
      
      debugPrint('UDP Listener active on port: $port');

      _socket!.listen(
        (RawSocketEvent event) {
          if (event == RawSocketEvent.read) {
            Datagram? datagram = _socket!.receive();
            if (datagram != null) {
              // 3. _parser.feed returns List<CanFrame>
              final List<CanFrame> parsedFrames = _parser.feed(datagram.data);

              for (final frame in parsedFrames) {
                onFrame(frame);
              }
            }
          }
        },
        onError: (error) {
          debugPrint('UDP Socket error: $error');
          onError(error);
        },
      );
    } catch (e) {
      debugPrint('Failed to bind UDP socket: $e');
      onError(e);
    }
  }

  void stop() {
    try {
      _socket?.close();
    } catch (e) {
      debugPrint('Error stopping UDP socket: $e');
    }
    _socket = null;
  }
}