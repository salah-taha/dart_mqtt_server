import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:developer' as developer;

import 'package:mqtt_server/src/enums/qos_message_state.dart';
import 'package:mqtt_server/src/models/qos_message.dart';
import 'package:mqtt_server/src/models/mqtt_broker_config.dart';
import 'package:mqtt_server/src/mqtt_connection.dart';
import 'package:mqtt_server/src/models/mqtt_message.dart';

class QosHandler {
  final Map<String, Map<int, QosMessage>> _pendingMessages = {};
  final Map<String, Queue<QosMessage>> _messageQueues = {};
  final Map<String, bool> _processingQueues = {};
  final Map<String, bool> _pausedQueues = {};
  final MqttBrokerConfig config;
  final void Function(QosMessage) onMessageComplete;
  final void Function(QosMessage) onMessageFailed;
  final Future<void> Function(MqttConnection, Uint8List) sendPacket;

  QosHandler({
    required this.config,
    required this.onMessageComplete,
    required this.onMessageFailed,
    required this.sendPacket,
  });

  Future<void> handlePublishQos(
    MqttConnection client,
    String topic,
    MqttMessage message,
    int messageId,
    String clientId, {
    bool isRetry = false,
  }) async {
    if (message.qos == 0) return;

    _pendingMessages.putIfAbsent(clientId, () => {});
    _messageQueues.putIfAbsent(clientId, () => Queue<QosMessage>());

    final existingMessage = _pendingMessages[clientId]?[messageId];
    if (existingMessage != null && isRetry) {
      await _processMessage(client, existingMessage);
      return;
    }

    final qosMessage = QosMessage(
      topic: topic,
      message: message,
      messageId: messageId,
      clientId: clientId,
      state: QosMessageState.pending,
      timestamp: DateTime.now(),
      retryCount: 0,
    );

    _pendingMessages[clientId]![messageId] = qosMessage;
    _messageQueues[clientId]!.add(qosMessage);

    await _processQueue(client, clientId);
  }

  Future<void> _processQueue(MqttConnection client, String clientId) async {
    // Check both processing state and pause state
    if (_processingQueues[clientId] == true || _pausedQueues[clientId] == true) return;
    _processingQueues[clientId] = true;

    try {
      final queue = _messageQueues[clientId];
      if (queue == null || queue.isEmpty) return;

      while (queue.isNotEmpty) {
        final message = queue.first;
        
        // Only check expiry if messageExpiryInterval is set
        if (config.messageExpiryInterval != null && 
            DateTime.now().difference(message.timestamp) > config.messageExpiryInterval!) {
          _handleMessageFailed(message);
          queue.removeFirst();
          continue;
        }

        if (message.state == QosMessageState.completed) {
          queue.removeFirst();
          continue;
        }

        await _processMessage(client, message);
        if (message.state != QosMessageState.completed) {
          break; // Wait for acknowledgment before processing next message
        }
        queue.removeFirst();
      }
    } finally {
      _processingQueues[clientId] = false;
    }
  }

  Future<void> _processMessage(MqttConnection client, QosMessage message) async {
    try {
      if (message.retryCount >= config.maxRetryAttempts) {
        developer.log('Max retry attempts reached for message');
        _handleMessageFailed(message);
        return;
      }

      if (message.message.qos == 1) {
        await _handleQos1Flow(client, message);
      } else if (message.message.qos == 2) {
        await _handleQos2Flow(client, message);
      }
    } catch (e) {
      developer.log('Error processing QoS message: $e');
      message.retryCount++;
      message.timestamp = DateTime.now();
    }
  }

  Future<void> _handleQos1Flow(MqttConnection client, QosMessage message) async {
    message.state = QosMessageState.pubAckPending;
    final puback = _createPubAckPacket(message.messageId);
    await sendPacket(client, puback);
  }

  Future<void> _handleQos2Flow(MqttConnection client, QosMessage message) async {
    message.state = QosMessageState.pubRecPending;
    final pubrec = _createPubRecPacket(message.messageId);
    await sendPacket(client, pubrec);
  }

  void handlePubAck(MqttConnection client, int messageId) {
    final clientId = _getClientId(client);
    if (clientId == null) return;

    final message = _pendingMessages[clientId]?[messageId];
    if (message == null) return;

    message.state = QosMessageState.completed;
    _handleMessageComplete(message);
  }

  Future<void> handlePubRec(MqttConnection client, int messageId) async {
    final clientId = _getClientId(client);
    if (clientId == null) return;

    final message = _pendingMessages[clientId]?[messageId];
    if (message == null) return;

    message.state = QosMessageState.pubRelPending;
    final pubrel = _createPubRelPacket(messageId);
    await sendPacket(client, pubrel);
  }

  Future<void> handlePubRel(MqttConnection client, int messageId) async {
    final clientId = _getClientId(client);
    if (clientId == null) return;

    final message = _pendingMessages[clientId]?[messageId];
    if (message == null) return;

    message.state = QosMessageState.pubCompPending;
    final pubcomp = _createPubCompPacket(messageId);
    await sendPacket(client, pubcomp);
  }

  void handlePubComp(MqttConnection client, int messageId) {
    final clientId = _getClientId(client);
    if (clientId == null) return;

    final message = _pendingMessages[clientId]?[messageId];
    if (message == null) return;

    message.state = QosMessageState.completed;
    _handleMessageComplete(message);
  }

  void _handleMessageComplete(QosMessage message) {
    _pendingMessages[message.clientId]?.remove(message.messageId);
    onMessageComplete(message);
    _processQueue(
      _getClientConnection(message.clientId),
      message.clientId,
    );
  }

  void _handleMessageFailed(QosMessage message) {
    _pendingMessages[message.clientId]?.remove(message.messageId);
    onMessageFailed(message);
  }

  final Map<MqttConnection, String> _connectionToClientId = {};
  final Map<String, MqttConnection> _clientIdToConnection = {};

  void registerClient(MqttConnection client, String clientId) {
    _connectionToClientId[client] = clientId;
    _clientIdToConnection[clientId] = client;
  }

  void unregisterClient(MqttConnection client) {
    final clientId = _connectionToClientId.remove(client);
    if (clientId != null) {
      _clientIdToConnection.remove(clientId);
    }
  }

  String? _getClientId(MqttConnection client) {
    return _connectionToClientId[client];
  }

  MqttConnection _getClientConnection(String clientId) {
    final connection = _clientIdToConnection[clientId];
    if (connection == null) {
      throw StateError('No connection found for client ID: $clientId');
    }
    return connection;
  }

  // Packet creation helpers remain the same
  Uint8List _createPubAckPacket(int messageId) {
    return Uint8List.fromList([
      0x40, // PUBACK fixed header
      0x02, // Remaining length
      (messageId >> 8) & 0xFF,
      messageId & 0xFF,
    ]);
  }

  Uint8List _createPubRecPacket(int messageId) {
    return Uint8List.fromList([
      0x50, // PUBREC fixed header
      0x02, // Remaining length
      (messageId >> 8) & 0xFF,
      messageId & 0xFF,
    ]);
  }

  Uint8List _createPubRelPacket(int messageId) {
    return Uint8List.fromList([
      0x62, // PUBREL fixed header
      0x02, // Remaining length
      (messageId >> 8) & 0xFF,
      messageId & 0xFF,
    ]);
  }

  Uint8List _createPubCompPacket(int messageId) {
    return Uint8List.fromList([
      0x70, // PUBCOMP fixed header
      0x02, // Remaining length
      (messageId >> 8) & 0xFF,
      messageId & 0xFF,
    ]);
  }

  void clearClientQueue(String clientId) {
    _pendingMessages.remove(clientId);
    _messageQueues.remove(clientId);
    _processingQueues.remove(clientId);
    _pausedQueues.remove(clientId);  // Also clear pause state
  }

  void pauseClientQueue(String clientId) {
    _pausedQueues[clientId] = true;
  }

  Future<void> resumeClientQueue(MqttConnection client, String clientId) async {
    // Ensure CONNACK is sent first by delaying queue processing
    await Future.delayed(Duration.zero);
    _pausedQueues.remove(clientId);
    await _processQueue(client, clientId);
  }
}
