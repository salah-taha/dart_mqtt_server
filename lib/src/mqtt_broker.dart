import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';


import 'models/broker_publish_event.dart';
import 'models/mqtt_broker_config.dart';
import 'models/mqtt_message.dart';
import 'mqtt_connection.dart';
import 'mqtt_session.dart';
import 'packet_handlers/handler_dependencies.dart';
import 'packet_handlers/packet_handler_registry.dart';

class MqttCredentials {
  final String username;
  final String hashedPassword;

  MqttCredentials(this.username, this.hashedPassword);
}

class MqttBroker implements HandlerDependencies {
  final MqttBrokerConfig config;
  final Map<String, Set<MqttConnection>> _topicSubscriptions = {};
  final Map<MqttConnection, MqttSession> _clientSessions = {};
  final Map<String, MqttCredentials> _credentials = {};
  final Map<String, MqttMessage> _retainedMessages = {};
  final Map<String, Map<int, MqttMessage>> _inFlightMessages = {};
  final Map<String, int> _clientConnectionCount = {};

  ServerSocket? _server;
  SecureServerSocket? _secureServer;
  Timer? _maintenanceTimer;
  bool _isRunning = false;

  // Persistence
  final Map<String, Map<String, dynamic>> _persistentSessions = {};

  Map<MqttConnection, MqttSession> get clientSessions => _clientSessions;
  Map<String, MqttCredentials> get credentials => _credentials;
  @override
  Map<String, MqttMessage> get retainedMessages => _retainedMessages;
  @override
  Map<String, Set<MqttConnection>> get topicSubscriptions => _topicSubscriptions;
  @override
  Map<String, Map<int, MqttMessage>> get inFlightMessages => _inFlightMessages;

  @override
  MqttSession? getSession(MqttConnection client) => _clientSessions[client];

  @override
  void removeSession(MqttConnection client) {
    _clientSessions.remove(client);
  }

  late final PacketHandlerRegistry _packetHandlerRegistry;

  // Event system for publish events
  final StreamController<BrokerPublishEvent> _publishController = StreamController.broadcast();
  Stream<BrokerPublishEvent> get publishStream => _publishController.stream;

  MqttBroker(this.config) {
    _packetHandlerRegistry = PacketHandlerRegistry(this);
  }

  void _startMaintenanceTimer() {
    _maintenanceTimer = Timer.periodic(Duration(seconds: 60), (_) {
      _performMaintenance();
    });
  }

  void _performMaintenance() {
    final now = DateTime.now();

    // Clean up expired sessions
    _clientSessions.forEach((client, session) {
      if (now.difference(session.lastActivity) > config.sessionExpiryInterval) {
        disconnectClient(client);
      }
    });

    // Save current state
    _savePersistentSessions();
  }

  void addUser(String username, String password) {
    _credentials[username] = MqttCredentials(username, password);
  }

  // Persistence methods are implemented below

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
      await _loadPersistentSessions();
    } catch (e) {
      developer.log('Failed to start MQTT broker: $e');
      await stop();
      rethrow;
    }
  }

  Future<void> _savePersistentSessions() async {
    try {
      if (!config.enablePersistence) return;
      final file = File(config.persistencePath);
      final data = jsonEncode(_persistentSessions);
      await file.writeAsString(data);
    } catch (e) {
      developer.log('Error saving persistent sessions: $e');
    }
  }

  Future<void> _loadPersistentSessions() async {
    try {
      if (!config.enablePersistence) return;

      final file = File(config.persistencePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;

        _persistentSessions.clear();
        data.forEach((key, value) {
          _persistentSessions[key] = value as Map<String, dynamic>;
        });

        developer.log('Loaded ${_persistentSessions.length} persistent sessions');
      }
    } catch (e) {
      developer.log('Error loading persistent sessions: $e');
    }
  }

  void _handleConnection(Socket socket) {
    developer.log('New client connected: ${socket.remoteAddress.address}:${socket.remotePort}');

    final client = MqttConnection(socket);
    _setupClientHandlers(client);
  }

  void _setupClientHandlers(MqttConnection client) {
    var buffer = <int>[];

    client.setCallbacks(
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
            if (client.isConnected) {
              _handleMqttPacket(packetData, client);
            }
          }
        } catch (e, stackTrace) {
          developer.log('Error processing data: $e');
          developer.log('Stack trace: $stackTrace');
          disconnectClient(client);
        }
      },
      onDisconnect: () {
        disconnectClient(client);
      },
    );
  }

  List<int>? _parsePacketLength(List<int> buffer) {
    if (buffer.isEmpty) return null;

    int multiplier = 1;
    int value = 0;
    int bytesRead = 0;

    for (int i = 1; i < buffer.length && i <= 4; i++) {
      bytesRead++;
      final digit = buffer[i];
      value += (digit & 127) * multiplier;
      multiplier *= 128;

      if ((digit & 128) == 0) {
        return [value + bytesRead + 1, bytesRead + 1];
      }
    }

    return null;
  }

  Future<void> _handleMqttPacket(Uint8List data, MqttConnection client) async {
    try {
      await _packetHandlerRegistry.handlePacket(data, client);
    } catch (e, stackTrace) {
      developer.log('Error handling MQTT packet: $e');
      developer.log('Stack trace: $stackTrace');
      await client.disconnect();
    }
  }


  Future<void> disconnectClient(MqttConnection client) async {
    final session = _clientSessions[client];
    if (session != null) {
      _clientSessions.remove(client);
    }
    client.disconnect();
  }

  Future<void> stop() async {
    _isRunning = false;
    _maintenanceTimer?.cancel();

    // Close all client connections
    for (final client in _clientSessions.keys.toList()) {
      await disconnectClient(client);
    }

    // Save sessions
    await _savePersistentSessions();

    // Close servers
    await _server?.close();
    await _secureServer?.close();

    _topicSubscriptions.clear();
    _clientSessions.clear();
    _retainedMessages.clear();
    _clientConnectionCount.clear();

    _isRunning = false;
    developer.log('MQTT Broker stopped');
  }

  bool get isRunning => _isRunning;
}
