import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:mqtt_server/src/core/broker_state_manager.dart';
import 'package:mqtt_server/src/core/packet_handler_registry.dart';
import 'package:mqtt_server/src/models/mqtt_broker_config.dart';
import 'package:mqtt_server/src/models/mqtt_connection.dart';

class MqttBroker {
  // Configuration
  late MqttBrokerConfig config;

  // State manager
  late BrokerStateManager stateManager;

  // Handler registry
  late PacketHandlerRegistry _packetHandlerRegistry;

  // Server infrastructure
  ServerSocket? _server;
  SecureServerSocket? _secureServer;
  Timer? _maintenanceTimer;
  bool _isRunning = false;

  MqttBroker([MqttBrokerConfig? brokerConfig]) {
    config = brokerConfig ?? MqttBrokerConfig();
    stateManager = BrokerStateManager(this);
    _packetHandlerRegistry = PacketHandlerRegistry(this);
  }

  void _startMaintenanceTimer() {
    _maintenanceTimer = Timer.periodic(Duration(seconds: 60), (_) {
      _performMaintenance();
    });
  }

  void _performMaintenance() {
    // Delegate maintenance to state manager
    stateManager.performMaintenance();

    // Save persistent sessions
    stateManager.savePersistentSessions();
  }

  Future<void> start() async {
    if (_isRunning) {
      throw StateError('Broker is already running');
    }

    try {
      if (config.useSSL) {
        if (config.sslCertPath == null || config.sslKeyPath == null) {
          throw ArgumentError('Certificate and private key paths are required for SSL');
        }

        SecurityContext context = SecurityContext()
          ..useCertificateChain(config.sslCertPath!)
          ..usePrivateKey(config.sslKeyPath!);

        _secureServer = await SecureServerSocket.bind(
          InternetAddress.anyIPv4,
          config.port,
          context,
          shared: true,
        );

        developer.log('MQTT Broker listening securely on port ${config.port}');
        _secureServer!.listen(_handleConnection);
      } else {
        _server = await ServerSocket.bind(
          InternetAddress.anyIPv4,
          config.port,
          shared: true,
        );

        developer.log('MQTT Broker listening on port ${config.port}');
        _server!.listen(_handleConnection);
      }

      _isRunning = true;
      _startMaintenanceTimer();
      await stateManager.loadPersistentSessions();
    } catch (e) {
      developer.log('Failed to start MQTT broker: $e');
      await stop();
      rethrow;
    }
  }

  void _handleConnection(Socket socket) {
    developer.log('New client connected: ${socket.remoteAddress.address}:${socket.remotePort}');

    final connection = MqttConnection(socket);
    _setupClientHandlers(connection);
  }

  void _setupClientHandlers(MqttConnection connection) {
    var buffer = <int>[];

    connection.setCallbacks(
      onData: (data) {
        try {
          buffer.addAll(data);

          while (buffer.isNotEmpty) {
            final packetInfo = _parsePacketLength(buffer);
            if (packetInfo == null) break;

            final totalLength = packetInfo[0];
            if (buffer.length < totalLength) break;

            final packetData = Uint8List.fromList(buffer.sublist(0, totalLength));
            buffer = buffer.sublist(totalLength);

            // Process immediately instead of scheduling
            _packetHandlerRegistry.handlePacket(packetData, connection);
          }
        } catch (e, stackTrace) {
          developer.log('Error processing data: $e');
          developer.log('Stack trace: $stackTrace');
          _disconnectClient(connection);
        }
      },
      onDisconnect: () {
        _disconnectClient(connection);
      },
    );
  }

  List<int>? _parsePacketLength(List<int> buffer) {
    if (buffer.isEmpty) return null;

    var multiplier = 1;
    var value = 0;
    var pos = 1;

    while (pos < buffer.length) {
      value += (buffer[pos] & 127) * multiplier;
      multiplier *= 128;

      if (multiplier > 128 * 128 * 128) {
        return null; // Malformed length
      }

      if ((buffer[pos] & 128) == 0) {
        break;
      }

      pos++;
    }

    final remainingLength = value;
    final totalLength = pos + 1 + remainingLength;

    if (totalLength > buffer.length) {
      return null; // Not enough data yet
    }

    return [totalLength, remainingLength];
  }

  Future<void> _disconnectClient(MqttConnection connection) async {
    if (connection.clientId != null) {
      stateManager.disconnectClient(connection.clientId!);
    } else {
      // If we can't find the client ID, just disconnect the connection
      connection.disconnect();
    }
    return Future.value();
  }

  Future<void> stop() async {
    if (!_isRunning) return;

    _isRunning = false;
    _server?.close();
    _secureServer?.close();
    _maintenanceTimer?.cancel();

    // Clean up all state
    await stateManager.dispose();

    _isRunning = false;
    developer.log('MQTT Broker stopped');
  }
}
