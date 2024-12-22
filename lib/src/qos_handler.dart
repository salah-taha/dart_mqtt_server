// QoS message states
import 'dart:async';
import 'dart:typed_data';

import 'package:mqtt_server/src/mqtt_broker_config.dart';
import 'package:mqtt_server/src/mqtt_connection.dart';
import 'package:mqtt_server/src/mqtt_message.dart';

// QoS message states
enum QosState { published, pubAckPending, pubRecPending, pubRelPending, pubCompPending, completed, failed }

// Represents a message in the QoS flow
class QosMessage {
  final String topic;
  final MqttMessage message;
  final int messageId;
  final String clientId;
  QosState state;
  int retryCount;
  Timer? retryTimer;
  final Completer<void> completer;

  QosMessage({
    required this.topic,
    required this.message,
    required this.messageId,
    required this.clientId,
  })  : state = QosState.published,
        retryCount = 0,
        completer = Completer<void>();
}

// Handles QoS flow logic
class QosHandler {
  final Map<int, QosMessage> _pendingMessages = {};
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
    bool isRetry = false, // Add isRetry parameter
  }) async {
    if (message.qos == 0) {
      return;
    }

    // If this message is already being handled and this is a retry, increment retry count
    final existingMessage = _pendingMessages[messageId];
    if (existingMessage != null && isRetry) {
      _handleRetry(client, existingMessage);
      return;
    }

    // Otherwise create new QoS message
    final qosMessage = QosMessage(
      topic: topic,
      message: message,
      messageId: messageId,
      clientId: clientId,
    );

    _pendingMessages[messageId] = qosMessage;

    try {
      if (message.qos == 1) {
        await _handleQos1Flow(client, qosMessage);
      } else if (message.qos == 2) {
        await _handleQos2Flow(client, qosMessage);
      }
    } catch (e) {
      print('Error in QoS flow: $e');
      _handleRetry(client, qosMessage);
    }

    return qosMessage.completer.future;
  }

  Future<void> _handleQos1Flow(MqttConnection client, QosMessage qosMessage) async {
    qosMessage.state = QosState.pubAckPending;

    // Send PUBACK
    final puback = _createPubAckPacket(qosMessage.messageId);
    await sendPacket(client, puback);

    // Start timeout for PUBACK
    _startAckTimeout(client, qosMessage);
  }

  Future<void> _handleQos2Flow(MqttConnection client, QosMessage qosMessage) async {
    qosMessage.state = QosState.pubRecPending;

    // Send PUBREC
    final pubrec = _createPubRecPacket(qosMessage.messageId);
    await sendPacket(client, pubrec);

    // Start timeout for PUBREC
    _startAckTimeout(client, qosMessage);
  }

  void handlePubAck(MqttConnection client, int messageId) {
    final qosMessage = _pendingMessages[messageId];
    if (qosMessage == null) return;

    qosMessage.state = QosState.completed;
    _cleanupMessage(messageId, true);
  }

  Future<void> handlePubRec(MqttConnection client, int messageId) async {
    final qosMessage = _pendingMessages[messageId];
    if (qosMessage == null) return;

    qosMessage.state = QosState.pubRelPending;

    // Send PUBREL
    final pubrel = _createPubRelPacket(messageId);
    await sendPacket(client, pubrel);

    // Start timeout for PUBCOMP
    _startAckTimeout(client, qosMessage);
  }

  Future<void> handlePubRel(MqttConnection client, int messageId) async {
    final qosMessage = _pendingMessages[messageId];
    if (qosMessage == null) return;

    qosMessage.state = QosState.pubCompPending;

    // Send PUBCOMP
    final pubcomp = _createPubCompPacket(messageId);
    await sendPacket(client, pubcomp);
  }

  void handlePubComp(int messageId) {
    final qosMessage = _pendingMessages[messageId];
    if (qosMessage == null) return;

    qosMessage.state = QosState.completed;
    _cleanupMessage(messageId, true);
  }

  void _handleRetry(MqttConnection client, QosMessage qosMessage) {
    if (qosMessage.retryCount >= config.maxRetryAttempts) {
      qosMessage.state = QosState.failed;
      _cleanupMessage(qosMessage.messageId, false);
      return;
    }

    qosMessage.retryCount++;
    qosMessage.retryTimer = Timer(
      config.retryDelay * qosMessage.retryCount,
      () => _retryMessage(client, qosMessage),
    );
  }

  Future<void> _retryMessage(MqttConnection client, QosMessage qosMessage) async {
    try {
      if (qosMessage.message.qos == 1) {
        await _handleQos1Flow(client, qosMessage);
      } else {
        await _handleQos2Flow(client, qosMessage);
      }
    } catch (e) {
      print('Retry failed: $e');
      _handleRetry(client, qosMessage);
    }
  }

  void _startAckTimeout(MqttConnection client, QosMessage qosMessage) {
    qosMessage.retryTimer?.cancel();
    qosMessage.retryTimer = Timer(
      config.keepAliveTimeout,
      () => _handleRetry(client, qosMessage),
    );
  }

  void _cleanupMessage(int messageId, bool success) {
    final qosMessage = _pendingMessages[messageId];
    if (qosMessage == null) return;

    qosMessage.retryTimer?.cancel();
    _pendingMessages.remove(messageId);

    if (success) {
      qosMessage.completer.complete();
      onMessageComplete(qosMessage);
    } else {
      qosMessage.completer.completeError('QoS flow failed');
      onMessageFailed(qosMessage);
    }
  }

  // Packet creation helpers
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
}
