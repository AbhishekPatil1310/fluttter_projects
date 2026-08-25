import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'can_envelop_parser.dart';
import 'can_frame.dart';

class CanSerialReader {
  final String device;
  final int baudRate;

  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _subscription;   //

  final CanEnvelopeParser _parser = CanEnvelopeParser(); //initialization for the fresh event for the frame coming from the serial port
  bool _running = false;

  CanSerialReader({
    required this.device,
    required this.baudRate,
  });

  void start({
    required void Function(CanFrame frame) onFrame,
    void Function(List<int> bytes)? onRawData,
    void Function(Object error)? onError,
  }) {
    if (_running) return;

    print('Opening serial port: $device');
    final port = SerialPort(device);    //here we are creating the serial port object for the given device
    _port = port; 

    if (!port.openRead()) {     //here it will try to read the port and if it fails it will throw an exception with the error message
      final error = SerialPort.lastError;
      port.dispose();   //clean up the memory and through an exeception to the main.dart, it cleans th enative C memory 
      _port = null;
      throw Exception('Could not open $device: $error');
    }

    try {
      final config = port.config;     //here we are getting the configuration of the serial port
      config.baudRate = baudRate;
      config.bits = 8;
      config.stopBits = 1;
      config.parity = SerialPortParity.none;
      // config.rts = 0;
      // config.cts = 0;
      // config.xonXoff = 0;
      port.config = config;
    } catch (e) {
      port.close();
      port.dispose();
      _port = null;
      rethrow;
    }

    final reader = SerialPortReader(port, timeout: 100);    //bytes comming from the physical port
    _reader = reader;
    _running = true;

    _subscription = reader.stream.listen(
      (Uint8List bytes) {
        if (!_running) return;

        onRawData?.call(bytes);

        final frames = _parser.feed(bytes);   //here we are calling the envelop file
        for (final frame in frames) {     //get the returned frame by the envelop file
          onFrame(frame);           //callback to the main file to display 
        }
      },
      onError: (Object error) {
        onError?.call(error);
      },
      onDone: () {
        _running = false;
      },
      cancelOnError: false,
    );
  }

  void stop() {         //this function will stop the serial port reading and close the port and clean up the memory
    if (!_running && _port == null) return;

    _running = false;
    _subscription?.cancel();
    _subscription = null;

    _reader?.close();
    _reader = null;

    final port = _port;
    if (port != null) {
      if (port.isOpen) {
        port.close();
      }
      port.dispose();
    }

    _port = null;
  }
}