import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;

import 'package:mqtt_server/mqtt_server.dart';
import 'package:mqtt_server/src/core/connections_manager.dart';
import 'package:mqtt_server/src/core/packet_handler_registry.dart';
import 'package:mqtt_server/src/models/mqtt_connection.dart';
import 'package:mqtt_server/src/models/mqtt_credentials.dart';
import 'package:mqtt_server/src/models/mqtt_session.dart';

class MqttBroker {
  late MqttBrokerConfig config;
  late MessageManager messageManager;
  late ConnectionsManager connectionsManager;
  late PacketHandlerRegistry _packetHandlerRegistry;
  final Map<String, MqttCredentials> _credentials = {};

  ServerSocket? _server;
  SecureServerSocket? _secureServer;
  Timer? _maintenanceTimer;
  bool _isRunning = false;

  MqttBroker([MqttBrokerConfig? brokerConfig]) {
    config = brokerConfig ?? MqttBrokerConfig();
    messageManager = MessageManager(this);
    connectionsManager = ConnectionsManager(this);
    _packetHandlerRegistry = PacketHandlerRegistry(this);
  }

  void addCredentials(String username, String password) {
    _credentials[username] = MqttCredentials(username, password);
  }

  void removeCredentials(String username) {
    _credentials.remove(username);
  }

  Map<String, MqttCredentials> getCredentials() {
    return _credentials;
  }

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
    performMaintenance();
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

            _packetHandlerRegistry.handlePacket(packetData, connection);

            // Clear the packet data after processing to help with GC
            packetData.clear();
          }

          // If buffer gets too large, clear it to prevent memory buildup
          if (buffer.length > 1024 * 1024) {
            // 1MB limit
            developer.log('Buffer exceeded size limit, clearing');
            buffer.clear();
          }
        } catch (e, stackTrace) {
          developer.log('Error processing data: $e');
          developer.log('Stack trace: $stackTrace');
          buffer.clear(); // Clear buffer on error
          _disconnectClient(connection);
        }
      },
      onDisconnect: () {
        buffer.clear(); // Clear buffer on disconnect
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
      messageManager.notifyClientDisconnected(connection.clientId!);
      connectionsManager.disconnectClient(connection.clientId!);
    } else {
      connection.disconnect();
    }
    return Future.value();
  }

  void performMaintenance() {
    // Clean up expired messages
    messageManager.cleanupExpiredMessages(config.messageExpiryInterval);
    // Clean up expired sessions
    connectionsManager.cleanupExpiredSessions(config.sessionExpiryInterval);
  }

  Future<void> savePersistentSessions() async {
    try {
      if (!config.enablePersistence) return;

      // Get all persistent sessions (non-clean sessions)
      final persistentSessions = <String, Map<String, dynamic>>{};
      final sessionIds = connectionsManager.getAllSessionIds();

      for (final clientId in sessionIds) {
        final session = connectionsManager.getSession(clientId);
        if (session != null && !session.cleanSession) {
          // Only save non-clean sessions
          persistentSessions[clientId] = session.toJson();
        }
      }

      if (persistentSessions.isEmpty) {
        return;
      }

      // Create the sessions directory if it doesn't exist
      final sessionsDir = Directory(path.dirname(config.persistencePath));
      if (!await sessionsDir.exists()) {
        await sessionsDir.create(recursive: true);
      }

      // Save sessions to file
      final file = File(config.persistencePath);
      final jsonData = jsonEncode(persistentSessions);
      await file.writeAsString(jsonData);
    } catch (_) {}
  }

  Future<void> loadPersistentSessions() async {
    try {
      if (!config.enablePersistence) return;

      final file = File(config.persistencePath);
      if (!await file.exists()) {
        return;
      }

      // Read the file content
      final jsonData = await file.readAsString();
      final Map<String, dynamic> sessionsData = jsonDecode(jsonData);

      // Load each session
      for (final clientId in sessionsData.keys) {
        try {
          final sessionData = sessionsData[clientId] as Map<String, dynamic>;
          final session = MqttSession.fromJson(sessionData);

          // Register the session
          connectionsManager.createSession(clientId, false);
          final newSession = connectionsManager.getSession(clientId);

          if (newSession != null) {
            // Copy properties from loaded session to new session
            newSession.qosLevels.addAll(session.qosLevels);
            newSession.messageId = session.messageId;
            newSession.willMessage = session.willMessage;
            newSession.willTopic = session.willTopic;
            newSession.lastActivity = session.lastActivity;
            newSession.keepAlive = session.keepAlive;
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> stop() async {
    if (!_isRunning) return;

    _isRunning = false;
    _server?.close();
    _secureServer?.close();
    _maintenanceTimer?.cancel();

    await connectionsManager.dispose(config.enablePersistence);

    await savePersistentSessions();

    _isRunning = false;
    developer.log('MQTT Broker stopped');
  }
}
