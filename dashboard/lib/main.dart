import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';// for the serial port communication(to find the usb ports and to read the data from the usb port)

import 'can_frame.dart';
import 'can_serial_reader.dart';
import 'can_udp_reader.dart';

void main() {
  runApp(const MyApp());
}

enum ConnectionMode { usb, udp }

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CAN Bus Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 2, 248, 248),
          brightness: Brightness.light
        ),
        useMaterial3: true,
      ),
      home: const CanReaderScreen(),
    );
  }
}

class CanReaderScreen extends StatefulWidget {
  const CanReaderScreen({super.key});     //this screen is static and its configaretion wont change on the run time, so we can use const constructor

  @override
  State<CanReaderScreen> createState() => _CanReaderScreenState();    //it is to handel the states in this class
}

class _CanReaderScreenState extends State<CanReaderScreen> {    //extends is for granting the built-in powers, lifecycle tools, and abilities that Flutter's State class has.
  // Connection Mode State
  ConnectionMode _connectionMode = ConnectionMode.usb;
///holds all the instance for the usb and the udp reader and their states, so that we can manage them easily

  // USB Readers & States
  CanSerialReader? _serialReader;
  List<String> _availablePorts = [];    //here <> is to tell that this list only should contains canFrame objects
  String? _selectedPort;
  static const int serialBaudRate = 2000000;

  // UDP Reader & Controllers
  CanUdpReader? _udpReader;
  final TextEditingController _udpPortController = TextEditingController(text: '5000');   //editable text field for UDP port

  // Unified Frame List for Display
  final List<CanFrame> _frames = []; //for listing the frames and used it for displaying teh list of the frames
  CanFrame? _lastTimeFrame;   //?is for when the app first loaded or if the date frame is not being sent or recived by the _lastTimeFrame it can stay as null

  bool _isListening = false;
  String _status = 'Disconnected';
  String? _errorMessage;
//-------------------------------------------------------------------------------------------------------------------------
  @override//flutter lifcycle method, called when the widget is inserted into the widget tree. It is used to initialize state and perform setup tasks.
  void initState() {
    super.initState();
    _refreshPorts();
  }
//-------------------------------------------------------------------------------------------------------------------------
//scans os for usb serial ports and updates the state of the app accordingly. It uses flutter_libserialport package to get the list of available serial ports.
  void _refreshPorts() {
    try {
      final ports = SerialPort.availablePorts;
      setState(() {
        _availablePorts = ports;
        _selectedPort = ports.isNotEmpty ? ports.first : null;
        _errorMessage = null;
        if (_connectionMode == ConnectionMode.usb) {
          _status = ports.isEmpty ? 'No serial ports found' : '${ports.length} serial port(s) found';
        }
      });
    } catch (e) {
      setState(() {
        _availablePorts = [];
        _selectedPort = null;
        if (_connectionMode == ConnectionMode.usb) {
          _status = 'Failed to detect serial ports';
        }
        _errorMessage = e.toString();
      });
    }
  }
//-------------------------------------------------------------------------------------------------------------------------
  void _toggleConnection() {    //if the app is currently listening for data, it stops the listening process. If not, it starts the appropriate reader based on the selected connection mode (USB or UDP).
    if (_isListening) {
      _stopListening();
    } else {
      if (_connectionMode == ConnectionMode.usb) {
        _startSerialReader();
      } else {
        _startUdpReader();
      }
    }
  }
//-------------------------------------------------------------------------------------------------------------------------
  void _stopListening() {     // this is for stopping the listening process for both USB and UDP readers. It stops the readers, resets their states, and updates the UI accordingly.
    // Stop USB Reader
    try {
      _serialReader?.stop();
    } catch (e) {
      debugPrint('Error stopping serial reader: $e');
    }
    _serialReader = null;

    // Stop UDP Reader
    try {
      _udpReader?.stop();
    } catch (e) {
      debugPrint('Error stopping UDP reader: $e');
    }
    _udpReader = null;

    if (mounted) {
      setState(() {
        _isListening = false;
        _status = 'Disconnected';
      });
    }
  }
//-------------------------------------------------------------------------------------------------------------------------
  // --- START USB SERIAL ---
  void _startSerialReader() {
    if (_selectedPort == null) return;
    _stopListening();

    final port = _selectedPort!;
    try {
      final reader = CanSerialReader(device: port, baudRate: serialBaudRate);
      print('this is the reader in start serialreader: $reader');
      _serialReader = reader;  //stores the hardware configaration came from the can_serial_reader.dart

      _serialReader!.start(     //bellow the CanFrame is acting as the type anotation which tels that the recived frame should said that the frame is  the instance of the canFrame
        onFrame: (CanFrame serialFrame) {   //this serializeFrame it is a argument sent to the can_frame_dat.dart file so it can bring the parsed data fom there here the onFrame is the callback function
          _handleIncomingFrame(serialFrame);
        },
        onError: (error) {
          if (mounted) {
            setState(() {
              _isListening = false;
              _errorMessage = error.toString();
            });
          }
        },
      );

      setState(() {
        _isListening = true;
        _status = 'Connected to USB ($port)';
        _errorMessage = null;
      });
    } catch (e) {
      setState(() {
        _isListening = false;
        _status = 'USB Connection failed';
        _errorMessage = e.toString();
      });
      _serialReader = null;
    }
  }
//-------------------------------------------------------------------------------------------------------------------------
  // --- START UDP LISTENER ---
  void _startUdpReader() {
    _stopListening();

    final int? port = int.tryParse(_udpPortController.text); // parser string to int, if it fails it returns null
    if (port == null) {
      setState(() => _errorMessage = 'Invalid UDP port number');
      return;
    }

    try {
      final reader = CanUdpReader(port: port);
      _udpReader = reader;

      _udpReader!.start(
        onFrame: (CanFrame frame) {
          _handleIncomingFrame(frame);
        },
        onError: (error) {
          if (mounted) {
            setState(() {
              _isListening = false;
              _errorMessage = error.toString();
            });
          }
        },
      );

      setState(() {
        _isListening = true;
        _status = 'Listening on UDP Port $port';
        _errorMessage = null;
      });
    } catch (e) {
      setState(() {
        _isListening = false;
        _status = 'UDP bind failed';
        _errorMessage = e.toString();
      });
      _udpReader = null;
    }
  }
//-------------------------------------------------------------------------------------------------------------------------
  void _handleIncomingFrame(CanFrame frame) {
    if (mounted) {
      setState(() {
        _frames.insert(0, frame);
        if (frame.timestamp != null) {
          _lastTimeFrame = frame;
        }
      });
    }
  }

  void _clearFrames() {
    setState(() {
      _frames.clear();
      _lastTimeFrame = null;
    });
  }

  @override
  void dispose() {
    _stopListening();
    _udpPortController.dispose();
    super.dispose();
  }

  // --- UI BUILDING ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CAN Bus Monitor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh serial ports',
            onPressed: (_isListening || _connectionMode == ConnectionMode.udp) ? null : _refreshPorts,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear Log',
            onPressed: _clearFrames,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildControlsHeader(),
          _buildConnectionStatus(),
          _buildTimeInfoCard(),
          _buildFrameHeader(),
          Expanded(child: _buildFrameList()),
        ],
      ),
    );
  }

  Widget _buildControlsHeader() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // Segmented Toggle Switch
          SegmentedButton<ConnectionMode>(
            segments: const [
              ButtonSegment(
                value: ConnectionMode.usb,
                label: Text('USB-CAN'),
                icon: Icon(Icons.usb),
              ),
              ButtonSegment(
                value: ConnectionMode.udp,
                label: Text('UDP Port'),
                icon: Icon(Icons.wifi),
              ),
            ],
            selected: {_connectionMode},
            onSelectionChanged: _isListening
                ? null
                : (newSelection) {
                    setState(() {
                      _connectionMode = newSelection.first;
                      _errorMessage = null;
                      if (_connectionMode == ConnectionMode.usb) {
                        _refreshPorts();
                      } else {
                        _status = 'Ready to listen on UDP';
                      }
                    });
                  },
          ),
          const SizedBox(width: 16),

          // Dynamic Config Input Field
          Expanded(
            child: _connectionMode == ConnectionMode.usb
                ? _buildUsbInput()
                : _buildUdpInput(),
          ),

          const SizedBox(width: 16),

          // Connect / Disconnect Action Button
          ElevatedButton.icon(
            onPressed: (_connectionMode == ConnectionMode.usb && _selectedPort == null)
                ? null
                : _toggleConnection,
            icon: Icon(_isListening ? Icons.stop : Icons.play_arrow),
            label: Text(_isListening ? 'Disconnect' : 'Connect'),
          ),
        ],
      ),
    );
  }

  Widget _buildUsbInput() {
    return Row(
      children: [
        const Text('Port:', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButton<String>(
            value: _selectedPort,
            isExpanded: true,
            hint: const Text('Select port'),
            items: _availablePorts.map((port) {
              return DropdownMenuItem<String>(
                value: port,
                child: Text(port, style: const TextStyle(fontFamily: 'monospace')),
              );
            }).toList(),
            onChanged: _isListening
                ? null
                : (value) {
                    setState(() {
                      _selectedPort = value;
                      _errorMessage = null;
                    });
                  },
          ),
        ),
      ],
    );
  }

  Widget _buildUdpInput() {
    return Row(
      children: [
        const Text('Port:', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        SizedBox(
          width: 120,
          child: TextField(
            controller: _udpPortController,
            enabled: !_isListening,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              hintText: '5000',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionStatus() {
    return Container(
      width: double.infinity,
      color: _isListening ? Colors.green.shade900 : Colors.red.shade900,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Row(
        children: [
          Icon(_isListening ? Icons.check_circle : Icons.error, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isListening ? _status : (_errorMessage ?? _status),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeInfoCard() {
    final dt = _lastTimeFrame?.timestamp;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.cyan.shade900.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.cyan.shade700, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 6,
            offset: Offset(0, 3),
          )
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.access_time_filled, color: Colors.cyanAccent, size: 36),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CAN BUS SYSTEM CLOCK',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: Colors.cyanAccent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  dt != null
                      ? '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}'
                      : 'Waiting for time payload...',
                  style: const TextStyle(
                    fontSize: 20,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          if (_lastTimeFrame != null)
            Chip(
              backgroundColor: Colors.cyan.shade900,
              label: Text(
                'ID: ${_lastTimeFrame!.canIdHex}',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Colors.white70,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFrameHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Raw Frame Stream (${_frames.length})', style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }

  Widget _buildFrameList() {
    if (_frames.isEmpty) {
      return const Center(child: Text('Waiting for CAN frames...'));
    }

    return ListView.builder(
      itemCount: _frames.length,
      itemBuilder: (context, index) {
        final frame = _frames[index];

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${frame.canIdHex} (${frame.isExtended ? "EXT" : "STD"})',
                  style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade800,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    frame.formattedDateTime,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text('DATA: ${frame.dataHex}', style: const TextStyle(fontFamily: 'monospace')),
            ),
            trailing: Text('DLC: ${frame.dlc}'),
          ),
        );
      },
    );
  }
}