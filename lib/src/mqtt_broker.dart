import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:mqtt_server/mqtt_server.dart';
import 'package:mqtt_server/src/core/connections_manager.dart';
import 'package:mqtt_server/src/core/packet_handler_registry.dart';
import 'package:mqtt_server/src/models/mqtt_connection.dart';
import 'package:mqtt_server/src/models/mqtt_credentials.dart';

class MqttBroker {
  // Configuration
  late MqttBrokerConfig config;

  // Message manager
  late MessageManager messageManager;

  // Connections manager
  late ConnectionsManager connectionsManager;

  // Handler registry
  late PacketHandlerRegistry _packetHandlerRegistry;

  // User credentials
  final Map<String, MqttCredentials> _credentials = {};

  // Server infrastructure
  ServerSocket? _server;
  SecureServerSocket? _secureServer;
  Timer? _maintenanceTimer;
  bool _isRunning = false;

  MqttBroker([MqttBrokerConfig? brokerConfig]) {
    config = brokerConfig ?? MqttBrokerConfig();
    messageManager = MessageManager(this);
    connectionsManager = ConnectionsManager();
    _packetHandlerRegistry = PacketHandlerRegistry(this);
  }
  
  /// Adds a user credential to the broker
  void addUser(String username, String password) {
    _credentials[username] = MqttCredentials(username, password);
  }

  /// Removes a user from the broker
  void removeUser(String username) {
    _credentials.remove(username);
  }

  /// Gets all credentials
  Map<String, MqttCredentials> getCredentials() {
    return _credentials;
  }

  /// Authenticates a user
  bool authenticate(String? username, String? password) {
    if (config.allowAnonymous) return true;
    if (username == null || password == null) return false;

    final credential = _credentials[username];
    if (credential == null) return false;

    return credential.password == password;
  }

  void _startMaintenanceTimer() {
    _maintenanceTimer = Timer.periodic(Duration(seconds: 60), (_) {
      _performMaintenance();
    });
  }

  void _performMaintenance() {
    // Delegate maintenance to state manager
    performMaintenance();

    // Save persistent sessions
    savePersistentSessions();
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
      await loadPersistentSessions();
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
      connectionsManager.disconnectClient(connection.clientId!, clearSession: false);
    } else {
      // If we can't find the client ID, just disconnect the connection
      connection.disconnect();
    }
    return Future.value();
  }

  void performMaintenance() {
    //TODO: Clean up expired messages and expired sessions
  }

  Future<void> savePersistentSessions() async {
    try {
      if (!config.enablePersistence) return;
      //TODO: Save persistent sessions to disk
    } catch (e) {
      developer.log('Error saving persistent sessions: $e');
    }
  }

  /// Loads persistent sessions from disk
  Future<void> loadPersistentSessions() async {
    try {
      if (!config.enablePersistence) return;
      //TODO: Load persistent sessions from disk
    } catch (e) {
      developer.log('Error loading persistent sessions: $e');
    }
  }



  Future<void> stop() async {
    if (!_isRunning) return;

    _isRunning = false;
    _server?.close();
    _secureServer?.close();
    _maintenanceTimer?.cancel();

    // Clean up all state
    //TODO: Disconnect all clients

    await savePersistentSessions();

    _isRunning = false;
    developer.log('MQTT Broker stopped');
  }
}
