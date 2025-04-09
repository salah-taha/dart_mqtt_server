import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:mqtt_server/src/models/broker_metrics.dart';
import 'package:mqtt_server/src/models/mqtt_broker_config.dart';
import 'package:mqtt_server/src/mqtt_connection.dart';
import 'package:mqtt_server/src/models/mqtt_message.dart';
import 'package:mqtt_server/src/mqtt_session.dart';
import 'package:mqtt_server/src/qos_handler.dart';

class MqttCredentials {
  final String username;
  final String hashedPassword;

  MqttCredentials(this.username, this.hashedPassword);
}

class MqttBroker {
  final MqttBrokerConfig config;
  final Map<String, Set<MqttConnection>> _topicSubscriptions = {};
  final Map<MqttConnection, MqttSession> _clientSessions = {};
  final Map<String, MqttMessage> _retainedMessages = {};
  final Map<String, MqttCredentials> _credentials = {};
  final Map<String, int> _clientConnectionCount = {};

  // Metrics tracking
  final BrokerMetrics _metrics;

  ServerSocket? _server;
  SecureServerSocket? _secureServer;
  Timer? _maintenanceTimer;
  bool _isRunning = false;

  // Persistence
  final Map<String, Map<String, dynamic>> _persistentSessions = {};
  final String _persistencePath = 'mqtt_sessions.json';

  late final QosHandler _qosHandler;

  MqttBroker(this.config) : _metrics = BrokerMetrics() {
    _qosHandler = QosHandler(
      config: config,
      onMessageComplete: (msg) {
        if (config.enableMetrics) {
          _metrics.recordPublish(msg.topic, msg.clientId);
        }
      },
      onMessageFailed: (msg) {
        if (config.enableMetrics) {
          _metrics.messagesFailed++;
        }
      },
      sendPacket: (client, packet) async {
        await client.send(packet);
        final session = _clientSessions[client];
        if (session != null) {
          session.lastActivity = DateTime.now();
        }
      },
    );
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
        _handleDisconnection(client);
      }
    });

    // Save current state
    _savePersistentSessions();

    // Log metrics if enabled
    // if (config.enableMetrics) {
    //   developer.log('Broker Metrics: ${_metrics.getMetricsSnapshot()}');
    // }
  }

  Future<void> start() async {
    if (_isRunning) {
      throw StateError('Broker is already running');
    }

    try {
      if (config.useSsl) {
        if (config.certificatePath == null || config.privateKeyPath == null) {
          throw ArgumentError('Certificate and private key paths are required for SSL');
        }

        SecurityContext context = SecurityContext()
          ..useCertificateChain(config.certificatePath!)
          ..usePrivateKey(config.privateKeyPath!);

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
      final file = File(_persistencePath);
      final data = jsonEncode(_persistentSessions);
      await file.writeAsString(data);
    } catch (e) {
      developer.log('Error saving persistent sessions: $e');
    }
  }

  Future<void> _loadPersistentSessions() async {
    try {
      final file = File(_persistencePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;

        _persistentSessions.clear();
        data.forEach((key, value) {
          _persistentSessions[key] = value as Map<String, dynamic>;
        });
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
          _handleDisconnection(client);
        }
      },
      onDisconnect: () {
        _handleDisconnection(client);
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
    if (data.isEmpty) return;

    final packetType = (data[0] >> 4) & 0x0F;
    final qos = (data[0] >> 1) & 0x03;
    final retain = (data[0] & 0x01) == 0x01;

    try {
      switch (packetType) {
        case 1: // CONNECT
          await _handleConnect(data, client);
          break;

        case 3: // PUBLISH
          await _handlePublish(data, client, qos, retain);
          break;

        case 4: // PUBACK
          if (data.length < 4) return;

          final messageId = ((data[2] << 8) | data[3]);
          _qosHandler.handlePubAck(client, messageId);
          break;

        case 5: // PUBREC
          if (data.length < 4) return;

          final messageId = ((data[2] << 8) | data[3]);
          await _qosHandler.handlePubRec(client, messageId);
          break;

        case 6: // PUBREL
          if (data.length < 4) return;

          final messageId = ((data[2] << 8) | data[3]);
          await _qosHandler.handlePubRel(client, messageId);
          break;

        case 7: // PUBCOMP
          if (data.length < 4) return;

          final messageId = ((data[2] << 8) | data[3]);
          _qosHandler.handlePubComp(client,messageId);
          break;

        case 8: // SUBSCRIBE
          await _handleSubscribe(data, client);
          break;

        case 10: // UNSUBSCRIBE
          await _handleUnsubscribe(data, client);
          break;

        case 12: // PINGREQ
          _handlePingRequest(client);
          break;

        case 14: // DISCONNECT
          await _handleDisconnection(client);
          break;

        default:
          developer.log('Unsupported packet type: $packetType');
      }
    } catch (e, stackTrace) {
      developer.log('Error handling MQTT packet: $e');
      developer.log('Stack trace: $stackTrace');
    }
  }

  Future<void> _handleConnect(Uint8List data, MqttConnection client) async {
    try {
      // Validate minimum packet length (2 bytes fixed header + 6 bytes protocol name length and string + 4 bytes flags and keep alive)
      if (data.length < 12) {
        await _sendConnack(client, 0x01); // Unacceptable protocol version
        return;
      }

      // // Validate protocol name (should be "MQTT" for MQTT 3.1.1)
      // final protocolLength = ((data[2] << 8) | data[3]);
      // if (protocolLength != 4 ||
      //     data[4] != 'M'.codeUnitAt(0) ||
      //     data[5] != 'Q'.codeUnitAt(0) ||
      //     data[6] != 'T'.codeUnitAt(0) ||
      //     data[7] != 'T'.codeUnitAt(0)) {
      //   await _sendConnack(client, 0x01);
      //   return;
      // }

      // // Protocol version check (0x04 for MQTT 3.1.1)
      // if (data[8] != 0x04) {
      //   await _sendConnack(client, 0x01);
      //   return;
      // }

      final connectFlags = data[9];
      final cleanSession = (connectFlags & 0x02) != 0;
      final willFlag = (connectFlags & 0x04) != 0;
      final willQoS = (connectFlags >> 3) & 0x03;
      final willRetain = (connectFlags & 0x20) != 0;
      final passwordFlag = (connectFlags & 0x40) != 0;
      final usernameFlag = (connectFlags & 0x80) != 0;

      var pos = 12;

      // Validate remaining length
      if (pos >= data.length) {
        await _sendConnack(client, 0x04); // Bad format
        return;
      }

      // Extract client ID
      if (pos + 2 > data.length) {
        await _sendConnack(client, 0x04);
        return;
      }

      final clientIdLength = ((data[pos] << 8) | data[pos + 1]);
      pos += 2;

      if (pos + clientIdLength > data.length) {
        await _sendConnack(client, 0x04);
        return;
      }

      final clientId = utf8.decode(data.sublist(pos, pos + clientIdLength), allowMalformed: false);
      pos += clientIdLength;

      // Check connection limit
      if (!_canClientConnect(clientId)) {
        await _sendConnack(client, 0x07); // Connection refused
        return;
      }

      // Handle authentication
      if (config.authenticationRequired) {
        String? username;
        String? password;

        if (usernameFlag) {
          if (pos + 2 > data.length) {
            await _sendConnack(client, 0x04);
            return;
          }

          final usernameLength = ((data[pos] << 8) | data[pos + 1]);
          pos += 2;

          if (pos + usernameLength > data.length) {
            await _sendConnack(client, 0x04);
            return;
          }

          username = utf8.decode(data.sublist(pos, pos + usernameLength), allowMalformed: false);
          pos += usernameLength;
        }

        if (passwordFlag) {
          if (pos + 2 > data.length) {
            await _sendConnack(client, 0x04);
            return;
          }

          final passwordLength = ((data[pos] << 8) | data[pos + 1]);
          pos += 2;

          if (pos + passwordLength > data.length) {
            await _sendConnack(client, 0x04);
            return;
          }

          password = utf8.decode(data.sublist(pos, pos + passwordLength), allowMalformed: false);
          pos += passwordLength;
        }

        if (username == null || password == null || !_authenticateClient(username, password)) {
          await _sendConnack(client, 0x05); // Not authorized
          return;
        }
      }

      // Create or restore session
      final session = MqttSession(clientId);
      _clientSessions[client] = session;
      
      // Register client with QoS handler
      _qosHandler.registerClient(client, clientId);
      session.lastActivity = DateTime.now();

      // Handle Will message if present
      if (willFlag) {
        if (pos + 4 > data.length) {
          await _sendConnack(client, 0x04);
          return;
        }

        final willTopicLength = ((data[pos] << 8) | data[pos + 1]);
        pos += 2;

        if (pos + willTopicLength > data.length) {
          await _sendConnack(client, 0x04);
          return;
        }

        final willTopic = utf8.decode(data.sublist(pos, pos + willTopicLength), allowMalformed: false);
        pos += willTopicLength;

        if (pos + 2 > data.length) {
          await _sendConnack(client, 0x04);
          return;
        }

        final willMessageLength = ((data[pos] << 8) | data[pos + 1]);
        pos += 2;

        if (pos + willMessageLength > data.length) {
          await _sendConnack(client, 0x04);
          return;
        }

        final willPayload = data.sublist(pos, pos + willMessageLength);

        session.willMessage = MqttMessage(
          Uint8List.fromList(willPayload),
          willQoS,
          willRetain,
        );
        session.willTopic = willTopic;
      }

      // Update metrics
      if (config.enableMetrics) {
        _metrics.totalConnections++;
        _metrics.activeConnections++;
      }

      // Send successful CONNACK
      final sessionPresent = !cleanSession && _persistentSessions.containsKey(clientId);
      await _sendConnack(client, 0x00, sessionPresent: sessionPresent);

      // Send retained messages
      for (final entry in _retainedMessages.entries) {
        if (_topicSubscriptions[entry.key]?.contains(client) ?? false) {
          await _sendPublish(client, entry.key, entry.value);
        }
      }
    } catch (e, stackTrace) {
      developer.log('Error handling CONNECT packet: $e\n$stackTrace');
      await _sendConnack(client, 0x04); // Bad format
      return;
    }
  }

  Future<void> _sendConnack(MqttConnection client, int returnCode, {bool sessionPresent = false}) async {
    final connack = Uint8List.fromList([
      0x20, // CONNACK fixed header
      0x02, // Remaining length
      sessionPresent ? 0x01 : 0x00, // Connect acknowledge flags
      returnCode, // Connect return code
    ]);
    await client.send(connack);

    if (returnCode != 0x00) {
      await client.disconnect();
    }
  }

  bool _authenticateClient(String username, String password) {
    if (!_credentials.containsKey(username)) return false;

    final hashedPassword = sha256.convert(utf8.encode(password)).toString();
    return _credentials[username]!.hashedPassword == hashedPassword;
  }

  bool _canClientConnect(String clientId) {
    return (_clientConnectionCount[clientId] ?? 0) < config.maxConnectionsPerClient;
  }

  Future<void> _handlePublish(Uint8List data, MqttConnection client, int qos, bool retain) async {
    final session = _clientSessions[client];
    if (session == null) return;

    try {
      final ByteData byteData = ByteData.sublistView(data);
      int offset = 1;

      // Parse remaining length (variable byte integer)
      // int multiplier = 1;
      // int remainingLength = 0;
      // int byte;
      // do {
      //   byte = byteData.getUint8(offset++);
      //   remainingLength += (byte & 0x7F) * multiplier;
      //   multiplier *= 128;
      // } while ((byte & 0x80) != 0);

      // Parse variable header
      // Topic name (UTF-8 encoded string)
      int topicLength = byteData.getUint16(offset);
      offset += 2;
      String topic = String.fromCharCodes(data.sublist(offset, offset + topicLength));
      offset += topicLength;

      // Packet ID (only present if QoS > 0)
      int messageId = 0;
      if (qos > 0) {
        messageId = byteData.getUint16(offset);
        offset += 2;
      }

      // Parse payload
      Uint8List payload = Uint8List.sublistView(data, offset, data.length);

      // Create message
      final message = MqttMessage(Uint8List.fromList(payload), qos, retain);

      // Handle retained messages
      if (retain) {
        if (payload.isEmpty) {
          _retainedMessages.remove(topic);
        } else {
          _retainedMessages[topic] = message;
        }
      }

      // Get subscribers including the sender
      final subscribers = (_topicSubscriptions[topic] ?? {}).toList();

      // Forward message to subscribers
      for (final subscriber in subscribers) {
        if (!subscriber.isConnected) continue;

        final subscriberSession = _clientSessions[subscriber];
        if (subscriberSession != null) {
          final subscriberQoS = subscriberSession.qosLevels[topic] ?? 0;
          final effectiveQoS = min(qos, subscriberQoS);

          await _sendPublish(subscriber, topic, MqttMessage(Uint8List.fromList(payload), effectiveQoS, false));
        }
      }

      // Handle QoS acknowledgment
      if (qos > 0) {
        await _qosHandler.handlePublishQos(
          client,
          topic,
          message,
          messageId,
          session.clientId,
        );
      }

      // Update metrics
      if (config.enableMetrics) {
        _metrics.recordPublish(topic, session.clientId);
      }
    } catch (e, stackTrace) {
      developer.log('Error handling PUBLISH packet: $e');
      developer.log('Stack trace: $stackTrace');
    }
  }

  Future<void> _handleSubscribe(Uint8List data, MqttConnection client) async {
    final session = _clientSessions[client]!;
    final messageId = ((data[2] << 8) | data[3]);
    var pos = 4;

    final returnCodes = <int>[];

    while (pos < data.length) {
      final topicLength = ((data[pos] << 8) | data[pos + 1]);
      pos += 2;
      final topic = utf8.decode(data.sublist(pos, pos + topicLength));
      pos += topicLength;
      final requestedQoS = data[pos++];

      // Store subscription with QoS
      session.qosLevels[topic] = requestedQoS;
      _topicSubscriptions.putIfAbsent(topic, () => {}).add(client);
      returnCodes.add(requestedQoS);

      // Send retained message for this topic if exists
      if (_retainedMessages.containsKey(topic)) {
        await _sendPublish(client, topic, _retainedMessages[topic]!);
      }
    }

    // Send SUBACK
    final suback = Uint8List.fromList([
      0x90,
      2 + returnCodes.length,
      (messageId >> 8) & 0xFF,
      messageId & 0xFF,
      ...returnCodes,
    ]);
    await client.send(suback);

    session.lastActivity = DateTime.now();
  }

  Future<void> _handleUnsubscribe(Uint8List data, MqttConnection client) async {
    final session = _clientSessions[client]!;
    final messageId = ((data[2] << 8) | data[3]);
    var pos = 4;

    while (pos < data.length) {
      final topicLength = ((data[pos] << 8) | data[pos + 1]);
      pos += 2;
      final topic = utf8.decode(data.sublist(pos, pos + topicLength));
      pos += topicLength;

      _topicSubscriptions[topic]?.remove(client);
      session.qosLevels.remove(topic);

      // Clean up empty topic subscriptions
      if (_topicSubscriptions[topic]?.isEmpty ?? false) {
        _topicSubscriptions.remove(topic);
      }
    }

    // Send UNSUBACK
    final unsuback = Uint8List.fromList([
      0xB0,
      0x02,
      (messageId >> 8) & 0xFF,
      messageId & 0xFF,
    ]);
    await client.send(unsuback);

    session.lastActivity = DateTime.now();
  }

  void _handlePingRequest(MqttConnection client) async {
    final pingresp = Uint8List.fromList([0xD0, 0x00]);
    await client.send(pingresp);

    final session = _clientSessions[client];
    if (session != null) {
      session.lastActivity = DateTime.now();
    }
  }

  void addUser(String username, String password) {
    final hashedPassword = sha256.convert(utf8.encode(password)).toString();
    _credentials[username] = MqttCredentials(username, hashedPassword);
  }

  Future<void> _handleDisconnection(MqttConnection client) async {
    final session = _clientSessions[client];
    if (session == null) return;

    // Process Will message if client didn't disconnect cleanly
    if (client.isConnected && session.willMessage != null && session.willTopic != null) {
      final subscribers = _topicSubscriptions[session.willTopic] ?? {};
      for (final subscriber in subscribers) {
        if (subscriber != client) {
          await _sendPublish(subscriber, session.willTopic!, session.willMessage!);
        }
      }
    }

    // Update connection count
    _clientConnectionCount[session.clientId] = (_clientConnectionCount[session.clientId] ?? 1) - 1;

    // Save session if persistence is enabled
    final persistentData = {
      'subscriptions': session.qosLevels.keys.toList(),
      'qosLevels': session.qosLevels,
      'timestamp': DateTime.now().toIso8601String(),
    };
    _persistentSessions[session.clientId] = persistentData;
    await _savePersistentSessions();

    // Clean up subscriptions
    for (final topic in List.from(_topicSubscriptions.keys)) {
      _topicSubscriptions[topic]?.remove(client);
      if (_topicSubscriptions[topic]?.isEmpty ?? false) {
        _topicSubscriptions.remove(topic);
      }
    }

    // Update metrics
    if (config.enableMetrics) {
      _metrics.activeConnections--;
    }
    _qosHandler.unregisterClient(client);
    _clientSessions.remove(client);
    await client.disconnect();
  }

  Future<void> _sendPublish(
    MqttConnection client,
    String topic,
    MqttMessage message, {
    bool isRetry = false,
  }) async {
    if (!client.isConnected) {
      developer.log('Client not connected when attempting to publish');
      return;
    }

    final session = _clientSessions[client];
    if (session == null) {
      developer.log('No session found for client when attempting to publish');
      return;
    }

    final messageId = message.qos > 0 ? session.getNextMessageId() : null;
    try {
      final publishPacket = _createPublishPacket(
        topic,
        message,
        messageId,
        session.clientId,
      );

      // Send synchronously
      await client.send(publishPacket);

      if (message.qos > 0 && messageId != null) {
        // Pass the session.clientId to handlePublishQos
        await _qosHandler.handlePublishQos(
          client,
          topic,
          message,
          messageId,
          session.clientId, // Add this parameter
        );
      }

      if (config.enableMetrics) {
        _metrics.recordPublish(topic, session.clientId);
      }
    } catch (e, stackTrace) {
      developer.log('Error in _sendPublish: $e');
      developer.log('Stack trace: $stackTrace');

      if (!isRetry && message.qos > 0 && messageId != null) {
        try {
          // Use QoS handler to handle the retry
          await _qosHandler.handlePublishQos(client, topic, message, messageId, session.clientId,
              isRetry: true // Add isRetry parameter to handlePublishQos
              );
        } catch (retryError) {
          developer.log('Retry failed: $retryError');
          _metrics.messagesFailed++;
        }
      } else {
        // If it's already a retry or QoS 0, just increment failed metrics
        _metrics.messagesFailed++;
      }
    }
  }

  Uint8List _createPublishPacket(
    String topic,
    MqttMessage message,
    int? messageId,
    String clientId,
  ) {
    final remainingLength = 2 + utf8.encode(topic).length + message.payload.length + (message.qos > 0 ? 2 : 0);

    final headerByte = 0x30 | (message.qos << 1) | (message.retain ? 0x01 : 0x00);

    final publishPacket = BytesBuilder();
    publishPacket.addByte(headerByte);

    _addRemainingLength(publishPacket, remainingLength);

    final topicBytes = utf8.encode(topic);
    publishPacket.addByte((topicBytes.length >> 8) & 0xFF);
    publishPacket.addByte(topicBytes.length & 0xFF);
    publishPacket.add(topicBytes);

    if (message.qos > 0 && messageId != null) {
      publishPacket.addByte((messageId >> 8) & 0xFF);
      publishPacket.addByte(messageId & 0xFF);
    }

    publishPacket.add(message.payload);
    return publishPacket.toBytes();
  }

  void _addRemainingLength(BytesBuilder builder, int length) {
    do {
      var byte = length % 128;
      length = length ~/ 128;
      if (length > 0) {
        byte = byte | 0x80;
      }
      builder.addByte(byte);
    } while (length > 0);
  }

  Future<void> stop() async {
    if (!_isRunning) return;

    _maintenanceTimer?.cancel();

    // Disconnect all clients
    final clients = List<MqttConnection>.from(_clientSessions.keys);
    for (final client in clients) {
      await _handleDisconnection(client);
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
