import 'dart:async';
import 'dart:io';
import 'dart:typed_data';     //for the Uint8List for row buffer to store the raw binary data like MAVLink packets

import 'package:flutter/foundation.dart';     //for flutter debug utilities
import 'package:intl/intl.dart';
import 'package:mavlink_dart/mavlink.dart';
import 'package:mavlink_dart/dialects/ugvcustom.dart';      //for the custo messages

enum SyncStatus { disconnected, syncing, synced }     //for the time syncing
enum SocketStatus { closed, binding, ready, error }   //for the socket connections

//--------------------------------------------------------------------------------------
// for the data transfer objects 

class TimeSyncSnapshot {
  final String currentGcsTimeDisplay;
  final String offsetDisplay;
  final double offsetMs;
  final double offsetUs;
  final String vehicleTimeDisplay;
  final int? vehicleTimeUs;
  final String correctedGcsTimeDisplay;
  final String rttDisplay;
  final double rttMs;
  final SyncStatus syncStatus;
  final SocketStatus socketStatus;
  final String? errorMessage;
  final int sentPackets;
  final int receivedPackets;
  final int syncSamples;

  const TimeSyncSnapshot({
    required this.currentGcsTimeDisplay,
    required this.offsetDisplay,
    required this.offsetMs,
    required this.offsetUs,
    required this.vehicleTimeDisplay,
    required this.vehicleTimeUs,
    required this.correctedGcsTimeDisplay,
    required this.rttDisplay,
    required this.rttMs,
    required this.syncStatus,
    required this.socketStatus,
    required this.errorMessage,
    required this.sentPackets,
    required this.receivedPackets,
    required this.syncSamples,
  });
}

//-------------------------------------------------------------------------------------
// class variables and configuration Parameters for the mavlink---------------------------
class MavlinkTimeSyncService {
  final String targetIp;
  final int sendPort;
  final int listenPort;
  final int systemId;
  final int componentId;
  final int targetSystemId;
  final int targetComponentId;
  final int mavlinkLinkId;
  final Duration syncInterval;
  final Duration watchdogTimeout;

  RawDatagramSocket? _socket;
  Timer? _syncTimer;
  Timer? _watchdogTimer;
//---------------------------------------------------------------------------------------
  // Secret key matching mock_vehicle_server.dart for the frame authentication
  static final Uint8List _mavlinkSecretKey = Uint8List.fromList([
    0x5f, 0xb2, 0x1c, 0x3a, 0x9e, 0xd4, 0x6f, 0x0b,
    0x2c, 0x7e, 0xa1, 0x4d, 0x83, 0x5b, 0xc9, 0x3f,
    0x0e, 0x6d, 0xb8, 0x94, 0x2a, 0xf1, 0xc5, 0x76,
    0x40, 0xed, 0x99, 0x13, 0xab, 0x5c, 0xe2, 0x04,
  ]);

  late final MavlinkSignatureManager _signatureManager;
  late final MavlinkDialectUgvcustom _dialect;
  late final MavlinkParser _parser;
  final StreamController<TimeSyncSnapshot> _controller = StreamController.broadcast();

  final DateFormat _fullDateFormat = DateFormat('yyyy-MM-dd HH:mm:ss.SSS');
  final DateFormat _timeOnlyFormat = DateFormat('HH:mm:ss.SSS');

  bool _started = false;
  SocketStatus _socketStatus = SocketStatus.closed;
  SyncStatus _syncStatus = SyncStatus.disconnected;
  String? _errorMessage;
  int _sequenceNumber = 0;
  int _sentPackets = 0;
  int _receivedPackets = 0;
  int _syncSamples = 0;
  int _startTimeUs = 0;
  int _lastValidResponseUs = 0;
  int _lastVehicleTimeUs = 0;
  double _filteredOffsetUs = 0.0;
  double _filteredRttUs = 0.0;

  Stream<TimeSyncSnapshot> get dataStream => _controller.stream;    // exposes the underlying _controller`s streame so it can be ready pubilcally 

//-----------------------------------------------------------------------------------
//sets the default parameaters for the mavlink

  MavlinkTimeSyncService({
    this.targetIp = '127.0.0.1',
    this.sendPort = 7000,      // ServerConfig.vehicleUdpPort
    this.listenPort = 7500,    // ServerConfig.gcsPort
    this.systemId = 255,        // ServerConfig.gcsSysId
    this.componentId = 190,     // ServerConfig.gcsCompId
    this.targetSystemId = 1,    // ServerConfig.vehicleSysId
    this.targetComponentId = 1, // ServerConfig.vehicleCompId
    this.mavlinkLinkId = 1,     // ServerConfig.mavlinkLinkId
    this.syncInterval = const Duration(milliseconds: 250),
    this.watchdogTimeout = const Duration(seconds: 3),      //defaulte timout to keep check on the services is dead or alive
  }) {
    _signatureManager = MavlinkSignatureManager(            //sign initialization
      MavlinkSignatureConfig(
        secretKey: _mavlinkSecretKey,
        linkId: mavlinkLinkId,
        acceptPolicy: SignatureAcceptPolicy.acceptAll,
      ),
    );
    _dialect = MavlinkDialectUgvcustom();           //for the custom message parsing
    _parser = MavlinkParser(
      _dialect,                                     //parser initialization here parser that turns raw UDP byte streams into structured MAVLink frame objects
      signatureManager: _signatureManager,
    );
  }

  int _toInt(dynamic val) {                         //for converting the incoming parsed binary packets parsed by the mavlink_dart libraries to the standerd dart data types
    if (val is int) return val;
    if (val is BigInt) return val.toInt();
    if (val is num) return val.toInt();
    return 0;
  }

  double _normalizeToMicroseconds(double val) {
    if (val <= 0) return 0.0;
    // Nanoseconds (Unix Epoch > 1e16 or standard MAVLink ts1/tc1 ns)
    if (val > 1e16) {
      return val / 1000.0;
    }
    // Milliseconds (Unix Epoch between 1e11 and 1e14)
    if (val > 1e11 && val <= 1e14) {
      return val * 1000.0;
    }
    // Seconds (Unix Epoch between 1e8 and 1e11)
    if (val > 1e8 && val <= 1e11) {
      return val * 1000000.0;
    }
    // Already in Microseconds (1e14 to 1e16 or standard microseconds)
    return val;
  }

// socket binding 

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _startTimeUs = DateTime.now().toUtc().microsecondsSinceEpoch;
    _lastValidResponseUs = 0;
    _syncSamples = 0;
    _socketStatus = SocketStatus.binding;
    _syncStatus = SyncStatus.syncing;
    _emitSnapshot();                      //pushes an update down sstream to notify the UI that binding has started

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        listenPort,
        reuseAddress: true,               //Allows the socket to bind even if the port is in a TIME_WAIT state from a previous connection.
        reusePort: true,
      );
      _socket!.listen(_handleSocketEvent);
      _socketStatus = SocketStatus.ready;
      _syncStatus = SyncStatus.syncing;
      _errorMessage = null;
      _emitSnapshot();            

      _syncTimer = Timer.periodic(syncInterval, (_) {
        _sendTimeSyncRequest();
      });

      _watchdogTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        _refreshSyncStatus();
      });

      _sendTimeSyncRequest();
    } catch (e) {
      _socketStatus = SocketStatus.error;
      _syncStatus = SyncStatus.disconnected;
      _errorMessage = 'UDP bind error on port $listenPort: $e';
      _started = false;
      _emitSnapshot();
    }
  }

  void _sendTimeSyncRequest() {
    final socket = _socket;
    if (socket == null || _socketStatus != SocketStatus.ready) return;

    final int nowUs = DateTime.now().toUtc().microsecondsSinceEpoch;
    final int requestTs1Ns = nowUs * 1000;        //it sent to the UGV so when the UGV sends the timesync packet the gcs vill get to know when this rewuest is sent

    final message = Timesync(
      tc1: 0,
      ts1: requestTs1Ns,
      targetSystem: targetSystemId,
      targetComponent: targetComponentId,
    );

    final frame = MavlinkFrame.v2(
      _sequenceNumber,
      systemId,
      componentId,
      message,
      signatureManager: _signatureManager,
    );

    try {
      socket.send(frame.serialize(), InternetAddress(targetIp), sendPort);
      _sequenceNumber = (_sequenceNumber + 1) % 256;
      _sentPackets++;
    } catch (e) {
      _socketStatus = SocketStatus.error;
      _errorMessage = 'UDP transmission error: $e';
    }
  }

  void _handleSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final socket = _socket;
    if (socket == null) return;

    Datagram? datagram;
    while ((datagram = socket.receive()) != null) {
      _receivedPackets++;

      try {
        final bytes = Uint8List.fromList(datagram!.data);
        final frames = _parser.parseBlob(bytes);        //takes a raw, unformatted stream of binary bytes received from the UDP socket and transforms them into structured, readable Dart MAVLink frame objects.

        for (final frame in frames) {
          if (targetSystemId != 0 && frame.systemId != targetSystemId) {
            continue;
          }

          if (frame.message is Timesync) {
            _handleTimesyncFrame(frame.message as Timesync);
          } else if (frame.message is SystemTime) {
            _handleSystemTimeFrame(frame.message as SystemTime);
          }
        }
      } catch (e) {
        // Safe catch prevents parser errors from breaking event loop
      }
    }
  }

  void _handleTimesyncFrame(Timesync message) {
    final int tc1Raw = _toInt(message.tc1);
    final int ts1Raw = _toInt(message.ts1);

    if (tc1Raw == 0) return;

    final int nowUs = DateTime.now().toUtc().microsecondsSinceEpoch;

    final double vehicleTimeUs = _normalizeToMicroseconds(tc1Raw.toDouble());
    final double ts1Us = _normalizeToMicroseconds(ts1Raw.toDouble());

    double rttUs = (ts1Us > 0) ? (nowUs - ts1Us) : 0.0;     //round tripe time

    if (rttUs <= 0 || rttUs > watchdogTimeout.inMicroseconds) {
      rttUs = 5000.0;
    }

    final double vehicleTimeAtRxUs = vehicleTimeUs + (rttUs / 2.0);   //for one way delay check
    final double rawOffsetUs = vehicleTimeAtRxUs - nowUs;             //raw difference between the vehicle time and the gcs time

    const double alpha = 0.2;
    _lastValidResponseUs = nowUs;

    if (_syncSamples == 0) {
      _filteredRttUs = rttUs;
      _filteredOffsetUs = rawOffsetUs;
    } else {
      _filteredRttUs = (_filteredRttUs * (1 - alpha)) + (rttUs * alpha);
      _filteredOffsetUs = (_filteredOffsetUs * (1 - alpha)) + (rawOffsetUs * alpha);
    }

    _syncSamples++;
    _refreshSyncStatus();
  }

  void _handleSystemTimeFrame(SystemTime message) {
    final int nowUs = DateTime.now().toUtc().microsecondsSinceEpoch;
    final int vehicleUnixUs = _toInt(message.timeUnixUsec);

    if (vehicleUnixUs > 0) {
      _lastValidResponseUs = nowUs;
      _lastVehicleTimeUs = vehicleUnixUs;
      final double normalizedVehicleUs = _normalizeToMicroseconds(vehicleUnixUs.toDouble());
      final double rawOffsetUs = normalizedVehicleUs - nowUs;

      const double alpha = 0.2;
      if (_syncSamples == 0) {
        _filteredOffsetUs = rawOffsetUs;
      } else {
        _filteredOffsetUs = (_filteredOffsetUs * (1 - alpha)) + (rawOffsetUs * alpha);
      }
      _syncSamples++;
      _refreshSyncStatus();
    }
  }

  void _refreshSyncStatus() {
    if (_socketStatus != SocketStatus.ready) {
      _syncStatus = SyncStatus.disconnected;
      _emitSnapshot();
      return;
    }

    final int nowUs = DateTime.now().toUtc().microsecondsSinceEpoch;

    if (_lastValidResponseUs > 0) {
      final bool isAlive = (nowUs - _lastValidResponseUs) <= watchdogTimeout.inMicroseconds;
      _syncStatus = isAlive ? SyncStatus.synced : SyncStatus.disconnected;
    } else {
      final bool initialTimeout = (nowUs - _startTimeUs) > watchdogTimeout.inMicroseconds;
      _syncStatus = initialTimeout ? SyncStatus.disconnected : SyncStatus.syncing;
    }

    _emitSnapshot();
  }

  void _emitSnapshot() {
    if (_controller.isClosed) return;

    final DateTime now = DateTime.now().toUtc();
    final int nowUs = now.microsecondsSinceEpoch;

    final int estimatedVehicleTimeUs = (nowUs + _filteredOffsetUs).round();

    final DateTime corrected = now.add(
      Duration(microseconds: _filteredOffsetUs.round()),
    );

    final double offsetMs = _filteredOffsetUs / 1000.0;
    final double rttMs = _filteredRttUs / 1000.0;
    print('filteredOffsetUs: $_filteredOffsetUs, filteredRttUs: $_filteredRttUs, offsetMs: $offsetMs, rttMs: $rttMs');

    _controller.add(
      TimeSyncSnapshot(
        currentGcsTimeDisplay: _fullDateFormat.format(now.toLocal()),
        offsetDisplay: '${offsetMs.toStringAsFixed(3)} ms / ${_filteredOffsetUs.round()} µs',
        offsetMs: offsetMs,
        offsetUs: _filteredOffsetUs,
        vehicleTimeDisplay: _formatVehicleTime(
          _syncStatus == SyncStatus.synced ? estimatedVehicleTimeUs : 0,
        ),
        vehicleTimeUs: _syncStatus == SyncStatus.synced ? estimatedVehicleTimeUs : null,
        correctedGcsTimeDisplay: _fullDateFormat.format(corrected.toLocal()),
        rttDisplay: '${rttMs.toStringAsFixed(2)} ms',
        rttMs: rttMs,
        syncStatus: _syncStatus,
        socketStatus: _socketStatus,
        errorMessage: _errorMessage,
        sentPackets: _sentPackets,
        receivedPackets: _receivedPackets,
        syncSamples: _syncSamples,
      ),
    );
  }

  String _formatVehicleTime(int vehicleTimeUs) {
    if (vehicleTimeUs <= 0) return 'N/A';
    if (vehicleTimeUs > 100000000000000) {
      final dt = DateTime.fromMicrosecondsSinceEpoch(vehicleTimeUs, isUtc: true);
      return _timeOnlyFormat.format(dt.toLocal());
    }
    return 'Boot ${(vehicleTimeUs / 1000000.0).toStringAsFixed(3)} s';
  }

  void dispose() {
    _syncTimer?.cancel();
    _watchdogTimer?.cancel();
    _socket?.close();
    _started = false;
    _socketStatus = SocketStatus.closed;
    _syncStatus = SyncStatus.disconnected;
    _controller.close();
  }
}