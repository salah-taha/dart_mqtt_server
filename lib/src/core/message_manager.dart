import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:mqtt_server/mqtt_server.dart';
import 'package:mqtt_server/src/core/packet_generator.dart';
import 'package:mqtt_server/src/enums/qos_message_state.dart';
import 'package:mqtt_server/src/models/mqtt_message.dart';

class MessageManager {
  final MqttBroker _broker;

  MessageManager(this._broker);

  final Map<String, Completer<void>> _processingLocks = {};

  // Store for retained messages (topic -> message)
  final Map<String, MqttMessage> _retainedMessages = {};

  final Map<String, ListQueue<MqttMessage>> _messageStore = {};

  final Map<String, ListQueue<MqttMessage>> _qos2Store = {};

  // Getters for message stores
  Map<String, MqttMessage> get retainedMessages => _retainedMessages;

  bool incomingPubAck(int messageId, String clientId) {
    var messages = _messageStore[clientId];
    if (messages == null || messages.isEmpty) return false;

    if (messages.any((message) => message.messageId == messageId && message.state == QosMessageState.pubAckPending)) {
      var message = messages.firstWhere((message) => message.messageId == messageId);
      messages.remove(message);

      if (messages.isEmpty) {
        _messageStore.remove(clientId);
      }

      processQueuedMessages(clientId);
      return true;
    }

    return false;
  }

  bool incomingPubComp(int messageId, String clientId) {
    var messages = _messageStore[clientId];
    if (messages == null || messages.isEmpty) return false;

    if (messages.any((message) => message.messageId == messageId && message.state == QosMessageState.pubCompPending)) {
      var message = messages.firstWhere((message) => message.messageId == messageId);
      messages.remove(message);

      if (messages.isEmpty) {
        _messageStore.remove(clientId);
      }

      processQueuedMessages(clientId);
      return true;
    }
    return false;
  }

  bool incomingPubRec(int messageId, String clientId) {
    var messages = _messageStore[clientId];
    if (messages == null || messages.isEmpty) return false;

    if (messages.any((message) => message.messageId == messageId && message.state == QosMessageState.pubRecPending)) {
      var message = messages.firstWhere((message) => message.messageId == messageId);
      message.state = QosMessageState.pubCompPending;
      return true;
    }
    return false;
  }

  bool incomingPubRel(int messageId, String clientId) {
    var messages = _qos2Store[clientId];
    if (messages == null || messages.isEmpty) {
      return false;
    }

    if (!messages.any((message) => message.messageId == messageId && message.state == QosMessageState.pubRelPending)) {
      return false;
    }

    messages.removeWhere((message) => message.messageId == messageId);

    if (messages.isEmpty) {
      _qos2Store.remove(clientId);
    }
    return true;
  }

  /// Extracts topic and payload from a PUBLISH packet
  ///  and messageId, isDuplicate
  Map<String, dynamic>? extractPublishData(Uint8List data) {
    try {
      var offset = 2;

      // Extract topic length and topic
      final topicLength = ((data[offset] << 8) | data[offset + 1]);
      offset += 2;
      final topic = utf8.decode(data.sublist(offset, offset + topicLength), allowMalformed: false);
      offset += topicLength;

      // Extract message ID if QoS > 0 (check QoS from the first byte)
      int messageId = 0;
      bool isDuplicate = false;
      final headerByte = data[0];
      final qos = (headerByte >> 1) & 0x03; // Extract QoS from bits 2-1
      isDuplicate = (headerByte & 0x08) != 0; // Extract DUP flag from bit 3

      if (qos > 0) {
        messageId = ((data[offset] << 8) | data[offset + 1]);
        offset += 2; // Move past the message ID
      }

      // Now extract the payload (everything after the message ID if present)
      final payload = data.sublist(offset);

      return {
        'topic': topic,
        'payload': payload, // Use the payload after the message ID
        'messageId': messageId,
        'isDuplicate': isDuplicate,
      };
    } catch (e) {
      return null;
    }
  }

  /// Stores a retained message for a topic
  void storeRetainedMessage(String topic, Uint8List payload, int qos, bool retain) {
    if (retain) {
      if (payload.isEmpty) {
        // Empty payload means delete retained message
        _retainedMessages.remove(topic);
      } else {
        // Store the retained message
        _retainedMessages[topic] = MqttMessage(payload, qos, retain, DateTime.now(), topic: topic);
      }
    }
  }

  void processQueuedMessages(String clientId) async {
    // Check if there's an existing lock and it's not completed
    if (_processingLocks.containsKey(clientId)) {
      var lock = _processingLocks[clientId]!;
      if (!lock.isCompleted) {
        try {
          // Add timeout to prevent deadlock
          await lock.future.timeout(Duration(seconds: 30));
        } catch (e) {
          // If timeout occurs, force complete the lock
          if (!lock.isCompleted) {
            lock.complete();
          }
        }
      }
    }

    _processingLocks[clientId] = Completer<void>();

    if (!_messageStore.containsKey(clientId)) {
      var lock = _processingLocks.remove(clientId);
      lock?.complete();
      return;
    }

    final queuedEntries = _messageStore[clientId];
    if (queuedEntries == null || queuedEntries.isEmpty) {
      var lock = _processingLocks.remove(clientId);
      lock?.complete();
      return;
    }

    final message = queuedEntries.first;

    try {
      final topic = message.topic ?? 'unknown';

      switch (message.qos) {
        case 0: // QoS 0: At most once delivery

          final publishPacket = PacketGenerator.publishPacket(
            topic: topic,
            payload: message.payload,
            qos: 0,
            messageId: 0,
            retain: message.retain,
            isDuplicate: false,
          );

          queuedEntries.removeFirst();

          final connection = _broker.connectionsManager.getConnection(clientId);
          if (connection == null) break;

          connection.send(publishPacket);
          await Future.delayed(Duration(milliseconds: 50));

          processQueuedMessages(clientId);
          break;

        case 1: // QoS 1: At least once delivery

          final publishPacket = PacketGenerator.publishPacket(
            topic: topic,
            payload: message.payload,
            qos: 1,
            messageId: message.messageId!,
            retain: message.retain,
            isDuplicate: message.state != QosMessageState.pending,
          );

          final connection = _broker.connectionsManager.getConnection(clientId);
          if (connection == null) break;

          connection.send(publishPacket);
          message.state = QosMessageState.pubAckPending;

          Future.delayed(_broker.config.retryInterval, () {
            processQueuedMessages(clientId);
          });

          break;

        case 2: // QoS 2: Exactly once delivery

          final publishPacket = PacketGenerator.publishPacket(
            topic: topic,
            payload: message.payload,
            qos: 2,
            messageId: message.messageId!,
            retain: message.retain,
            isDuplicate: message.state != QosMessageState.pending,
          );

          final connection = _broker.connectionsManager.getConnection(clientId);
          if (connection == null) break;

          connection.send(publishPacket);
          message.state = QosMessageState.pubRecPending;

          Future.delayed(_broker.config.retryInterval, () {
            processQueuedMessages(clientId);
          });

          break;
      }
    } catch (e) {
      Future.delayed(_broker.config.retryInterval, () {
        processQueuedMessages(clientId);
      });
    } finally {
      _processingLocks[clientId]!.complete();
    }
  }

  /// Remove all messages for a client
  void removeClientMessages(String clientId) {
    _messageStore.remove(clientId);
    _qos2Store.remove(clientId);
    // Clean up any processing locks for this client
    final lock = _processingLocks.remove(clientId);
    if (!lock!.isCompleted) {
      lock.complete();
    }
  }

  void removeClientTopicMessages(String clientId, String topic) {
    _messageStore[clientId]?.removeWhere((message) => message.topic == topic);
  }

  /// Clean up expired messages
  void cleanupExpiredMessages(Duration expiryInterval) {
    final now = DateTime.now();

    // Clean up expired messages
    _messageStore.forEach((clientId, messages) {
      final expiredMessages = <MqttMessage>[];
      for (var message in messages) {
        if (now.difference(message.timestamp) > expiryInterval) {
          expiredMessages.add(message);
        }
      }

      for (final message in expiredMessages) {
        messages.remove(message);
      }
    });
  }

  Future<void> sendMessage({
    required String topic,
    required Uint8List payload,
    String? senderId,
    int messageQos = 0,
    bool retain = false,
    bool isDuplicate = false,
    int? messageId,
  }) async {
    var subscripers = _broker.connectionsManager.getSubscribers(topic);

    for (var clientId in subscripers) {
      try {
        var session = _broker.connectionsManager.getSession(clientId);
        var actualMessageId = 0;

        var effectiveQos = min(messageQos, session?.qosLevels[topic] ?? 0);
        if (effectiveQos > 0) {
          actualMessageId = messageId ?? session?.getNextMessageId() ?? 0;
        }

        if (isDuplicate && _messageStore[clientId]?.any((message) => message.messageId == actualMessageId) == true) {
          continue;
        }

        var message = MqttMessage(
          payload,
          effectiveQos,
          retain,
          DateTime.now(),
          topic: topic,
          messageId: actualMessageId,
          state: QosMessageState.pending,
        );

        _messageStore[clientId] ??= ListQueue<MqttMessage>();
        _messageStore[clientId]!.add(message);

        if (effectiveQos == 2 && senderId != null) {
          var qos2Message = message.copyWith(
            state: QosMessageState.pubRelPending,
          );
          _qos2Store[senderId] ??= ListQueue<MqttMessage>();
          _qos2Store[senderId]!.add(qos2Message);
        }

        processQueuedMessages(clientId);
      } catch (_) {}
    }
  }

  Future<void> sendRetainedMessage({
    required String clientId,
    required String topic,
  }) async {
    try {
      var retainedMessage = _retainedMessages[topic];

      if (retainedMessage == null) {
        return;
      }

      var session = _broker.connectionsManager.getSession(clientId);
      var actualMessageId = 0;

      var effectiveQos = min(retainedMessage.qos, session?.qosLevels[topic] ?? 0);
      if (effectiveQos > 0) {
        actualMessageId = retainedMessage.messageId ?? session?.getNextMessageId() ?? 0;
      }

      if (_messageStore[clientId]?.any((message) => message.messageId == actualMessageId) == true) {
        return;
      }

      var message = retainedMessage.copyWith(
        messageId: actualMessageId,
        state: QosMessageState.pending,
        timestamp: DateTime.now(),
      );

      _messageStore[clientId] ??= ListQueue<MqttMessage>();
      _messageStore[clientId]!.add(message);

      processQueuedMessages(clientId);
    } catch (_) {}
  }

  void notifyClientDisconnected(String clientId) {
    var session = _broker.connectionsManager.getSession(clientId);
    if (session == null) return;
    if (session.willMessage == null || session.willTopic == null) return;
    var willMessage = session.willMessage!;

    sendMessage(topic: session.willTopic!, payload: willMessage.payload, messageQos: willMessage.qos);
  }

  /// Extracts message ID from a packet
  int? extractMessageId(Uint8List data, [int offset = 2]) {
    if (data.length < offset + 2) return null;
    return ((data[offset] << 8) | data[offset + 1]);
  }

  /// Extracts subscription topics and QoS from a SUBSCRIBE packet
  List<Map<String, dynamic>> extractSubscriptions(Uint8List data) {
    final result = <Map<String, dynamic>>[];
    var pos = 4; // Skip fixed header and message ID

    while (pos < data.length) {
      if (pos + 2 > data.length) break;

      final topicLength = ((data[pos] << 8) | data[pos + 1]);
      pos += 2;

      if (pos + topicLength > data.length) break;

      final topic = utf8.decode(data.sublist(pos, pos + topicLength));
      pos += topicLength;

      if (pos >= data.length) break;

      final requestedQos = data[pos++] & 0x03;

      result.add({
        'topic': topic,
        'qos': requestedQos,
      });
    }

    return result;
  }

  /// Extracts unsubscribe topics from an UNSUBSCRIBE packet
  List<String> extractUnsubscribeTopics(Uint8List data) {
    final result = <String>[];
    var pos = 4; // Skip fixed header and message ID

    while (pos < data.length) {
      if (pos + 2 > data.length) break;

      final topicLength = ((data[pos] << 8) | data[pos + 1]);
      pos += 2;

      if (pos + topicLength > data.length) break;

      final topic = utf8.decode(data.sublist(pos, pos + topicLength));
      pos += topicLength;

      result.add(topic);
    }

    return result;
  }
}
