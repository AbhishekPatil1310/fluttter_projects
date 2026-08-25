import 'package:flutter/material.dart';
import 'services/mavlink_timesync_service.dart';

void main() {
  runApp(const LinuxGcsApp());
}

class LinuxGcsApp extends StatelessWidget {
  final MavlinkTimeSyncService? service;

  const LinuxGcsApp({super.key, this.service});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UGV MAVLink TimeSync GCS',
      debugShowCheckedModeBanner: true,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF32D6FF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF07111E),
        cardColor: const Color(0xFF101C2E),
      ),
      home: DashboardScreen(service: service),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  final MavlinkTimeSyncService? service;

  const DashboardScreen({super.key, this.service});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final MavlinkTimeSyncService _service;
  late final bool _isLocallyOwnedService;

  @override
  void initState() {
    super.initState();
    _isLocallyOwnedService = widget.service == null;
    _service = widget.service ?? MavlinkTimeSyncService();
    _service.start();
  }

  @override
  void dispose() {
    if (_isLocallyOwnedService) {
      _service.dispose();
    }
    super.dispose();
  }

  Color _statusColor(SyncStatus status) {
    switch (status) {
      case SyncStatus.synced:
        return const Color(0xFF32D583);
      case SyncStatus.syncing:
        return const Color(0xFFF5B942);
      case SyncStatus.disconnected:
        return const Color(0xFFEF5F6C);
    }
  }

  String _statusLabel(SyncStatus status) {
    switch (status) {
      case SyncStatus.synced:
        return 'Synced';
      case SyncStatus.syncing:
        return 'Syncing';
      case SyncStatus.disconnected:
        return 'Disconnected';
    }
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.75)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<TimeSyncSnapshot>(
        stream: _service.dataStream,
        builder: (context, snapshot) {
          final data = snapshot.data;
          final syncStatus = data?.syncStatus ?? SyncStatus.disconnected;
          final syncColor = _statusColor(syncStatus);

          final String gcsTime = data?.currentGcsTimeDisplay ?? 'Waiting...';
          final String offsetStr = data?.offsetDisplay ?? 'N/A';
          final String vehicleTime = data?.vehicleTimeDisplay ?? 'N/A';
          final String correctedGcsTime = data?.correctedGcsTimeDisplay ?? 'N/A';
          final String rttStr = data?.rttDisplay ?? 'N/A';

          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0A1322), Color(0xFF050B13)],
              ),
            ),
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'MAVLink TimeSync GCS',
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                    fontSize: 26, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Real-time Ground Control Telemetry Dashboard (1–5 Hz)',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                      _chip(_statusLabel(syncStatus), syncColor),
                    ],
                  ),
                  const SizedBox(height: 20),

                  if (data?.errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF5F6C).withValues(alpha: 0.15),
                        border: Border.all(color: const Color(0xFFEF5F6C)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        data!.errorMessage!,
                        style: const TextStyle(color: Color(0xFFEF5F6C)),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF101C2E),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(
                          const Color(0xFF081424),
                        ),
                        columns: const [
                          DataColumn(
                            label: Text(
                              'Parameter Field',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Units / Format',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Live Value / Source',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                        rows: [
                          DataRow(cells: [
                            const DataCell(Text('Current GCS Date & Time',
                                style: TextStyle(fontWeight: FontWeight.w600))),
                            const DataCell(Text('YYYY-MM-DD HH:mm:ss.SSS')),
                            DataCell(Text(gcsTime,
                                style: const TextStyle(
                                    fontFamily: 'monospace',
                                    color: Color(0xFF32D6FF)))),
                          ]),
                          DataRow(cells: [
                            const DataCell(Text('Time Offset',
                                style: TextStyle(fontWeight: FontWeight.w600))),
                            const DataCell(Text('ms / µs')),
                            DataCell(Text(offsetStr,
                                style: const TextStyle(
                                    fontFamily: 'monospace',
                                    color: Color(0xFFF5B942)))),
                          ]),
                          DataRow(cells: [
                            const DataCell(Text('System Time (Vehicle Time)',
                                style: TextStyle(fontWeight: FontWeight.w600))),
                            const DataCell(Text('HH:mm:ss.SSS / Boot Epoch')),
                            DataCell(Text(vehicleTime,
                                style: const TextStyle(
                                    fontFamily: 'monospace',
                                    color: Color(0xFF45E6C9)))),
                          ]),
                          DataRow(cells: [
                            const DataCell(Text('Corrected GCS Time',
                                style: TextStyle(fontWeight: FontWeight.w600))),
                            const DataCell(Text('YYYY-MM-DD HH:mm:ss.SSS')),
                            DataCell(Text(correctedGcsTime,
                                style: const TextStyle(
                                    fontFamily: 'monospace',
                                    color: Color(0xFF32D583)))),
                          ]),
                          DataRow(cells: [
                            const DataCell(Text('Round-Trip Time (RTT)',
                                style: TextStyle(fontWeight: FontWeight.w600))),
                            const DataCell(Text('ms')),
                            DataCell(Text(rttStr,
                                style: const TextStyle(
                                    fontFamily: 'monospace',
                                    color: Color(0xFFB37BFF)))),
                          ]),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Sent Packets: ${data?.sentPackets ?? 0}',
                          style: const TextStyle(color: Colors.white54)),
                      Text('Received Packets: ${data?.receivedPackets ?? 0}',
                          style: const TextStyle(color: Colors.white54)),
                      Text('Sync Samples: ${data?.syncSamples ?? 0}',
                          style: const TextStyle(color: Colors.white54)),
                    ],
                  )
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}