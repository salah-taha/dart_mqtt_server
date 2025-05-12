import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:mqtt_server/src/core/broker_state_manager.dart';
import 'package:mqtt_server/src/core/handler_dependencies.dart';
import 'package:mqtt_server/src/core/packet_handler_registry.dart';
import 'package:mqtt_server/src/models/mqtt_broker_config.dart';
import 'package:mqtt_server/src/models/mqtt_message.dart';
import 'package:mqtt_server/src/models/mqtt_connection.dart';
import 'package:mqtt_server/src/models/mqtt_session.dart';
import 'package:mqtt_server/src/models/mqtt_credentials.dart';


class MqttBroker implements HandlerDependencies {
  // Configuration
  static MqttBrokerConfig config = MqttBrokerConfig();

  // State manager
  final BrokerStateManager _stateManager = BrokerStateManager();

  // Server infrastructure
  ServerSocket? _server;
  SecureServerSocket? _secureServer;
  Timer? _maintenanceTimer;
  bool _isRunning = false;

  // Handler registry
  late final PacketHandlerRegistry _packetHandlerRegistry;

  // Implement HandlerDependencies interface
  @override
  Map<String, MqttMessage> get retainedMessages => _stateManager.retainedMessages;
  
  @override
  Map<String, Set<String>> get topicSubscriptions => _stateManager.topicSubscriptions;

  @override
  Map<String, Map<String, int>> get clientSubscriptions => _stateManager.clientSubscriptions;

  @override
  void subscribe(String clientId, String topic, int qos) {
    _stateManager.subscribe(clientId, topic, qos);
  }

  @override
  void unsubscribe(String clientId, String topic) {
    _stateManager.unsubscribe(clientId, topic);
  }

  @override
  Map<String, Map<int, MqttMessage>> get inFlightMessages => _stateManager.inFlightMessages;

  @override
  Map<String, MqttConnection> get clientConnections => _stateManager.clientConnections;

  @override
  MqttSession? getSession(String? clientId) {
    return _stateManager.getSession(clientId);
  }

  @override
  void removeSession(String clientId) {
    _stateManager.removeSession(clientId);
  }
  
  @override
  void addSession(String clientId, MqttSession session) {
    _stateManager.addSession(clientId, session);
  }
  
  @override
  Map<String, MqttCredentials> getCredentials() {
    return _stateManager.getCredentials();
  }

  @override
  void queueMessage(String clientId, String topic, List<int> payload, int qos) {
    _stateManager.queueMessage(clientId, topic, payload, qos);
  }
  
  @override
  void processQueuedMessages(String clientId) {
    _stateManager.processQueuedMessages(clientId);
  }
  
  @override
  bool get allowAnonymousConnections => config.allowAnonymous;

  // Public getters for broker state
  Map<String, MqttSession> get clientSessions => _stateManager.sessions;
  Map<String, MqttCredentials> get credentials => _stateManager.credentials;


  MqttBroker([MqttBrokerConfig? brokerConfig]) {
    if (brokerConfig != null) {
      MqttBroker.config = brokerConfig;
    }
    _packetHandlerRegistry = PacketHandlerRegistry(this);
  }

  void _startMaintenanceTimer() {
    _maintenanceTimer = Timer.periodic(Duration(seconds: 60), (_) {
      _performMaintenance();
    });
  }

  void _performMaintenance() {
    // Delegate maintenance to state manager
    _stateManager.performMaintenance();
    
    // Save persistent sessions
    _stateManager.savePersistentSessions();
  }

  void addUser(String username, String password) {
    _stateManager.addUser(username, password);
  }

  Future<void> start() async {
    if (_isRunning) {
      throw StateError('Broker is already running');
    }

    try {
      if (MqttBroker.config.useSSL) {
        if (MqttBroker.config.sslCertPath == null || MqttBroker.config.sslKeyPath == null) {
          throw ArgumentError('Certificate and private key paths are required for SSL');
        }

        SecurityContext context = SecurityContext()
          ..useCertificateChain(MqttBroker.config.sslCertPath!)
          ..usePrivateKey(MqttBroker.config.sslKeyPath!);

        _secureServer = await SecureServerSocket.bind(
          InternetAddress.anyIPv4,
          MqttBroker.config.port,
          context,
          shared: true,
        );

        developer.log('MQTT Broker listening securely on port ${MqttBroker.config.port}');
        _secureServer!.listen(_handleConnection);
      } else {
        _server = await ServerSocket.bind(
          InternetAddress.anyIPv4,
          MqttBroker.config.port,
          shared: true,
        );

        developer.log('MQTT Broker listening on port ${MqttBroker.config.port}');
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

  Future<void> _loadPersistentSessions() async {
    await _stateManager.loadPersistentSessions();
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
            _handleMqttPacket(packetData, connection);
            
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

  Future<void> _handleMqttPacket(Uint8List data, MqttConnection connection) async {
    await _packetHandlerRegistry.handlePacket(data, connection);
  }

  Future<void> _disconnectClient(MqttConnection connection) async {
    if (connection.clientId != null) {
      _stateManager.disconnectClient(connection.clientId!);
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
    await _stateManager.dispose();

    _isRunning = false;
    developer.log('MQTT Broker stopped');
  }

}
