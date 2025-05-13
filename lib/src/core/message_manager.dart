import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';
import 'dart:typed_data';

import 'package:mqtt_server/mqtt_server.dart';
import 'package:mqtt_server/src/enums/qos_message_state.dart';
import 'package:mqtt_server/src/models/mqtt_message.dart';

class MessageManager {
  final MqttBroker _broker;

  MessageManager(this._broker);

  // Store for retained messages (topic -> message)
  final Map<String, MqttMessage> _retainedMessages = {};

  final Map<String, ListQueue<MqttMessage>> _messageStore = {};

  final Map<String, ListQueue<MqttMessage>> _qos2Store = {};

  // Getters for message stores
  Map<String, MqttMessage> get retainedMessages => _retainedMessages;

  void incomingPubAck(int messageId, String clientId) {
    var messages = _messageStore[clientId];
    if (messages == null || messages.isEmpty) return;

    messages.removeWhere((message) => message.messageId == messageId);

    processQueuedMessages(clientId);
  }

  bool incomingPubRec(int messageId, String clientId) {
    var messages = _messageStore[clientId];
    if (messages == null || messages.isEmpty) return false;

    if (messages.any((message) => message.messageId == messageId)) {
      return true;
    }
    return false;
  }

  bool incomingPubRel(int messageId, String clientId) {
    var messages = _qos2Store[clientId];
    if (messages == null || messages.isEmpty) return false;

    if (!messages.any((message) => message.messageId == messageId)) {
      return false;
    }

    messages.removeWhere((message) => message.messageId == messageId);
    return true;
  }

  /// Extracts topic and payload from a PUBLISH packet
  ///  and messageId, isDuplicate
  Map<String, dynamic>? extractPublishData(Uint8List data) {
    try {
      var offset = 2;

      final topicLength = ((data[offset] << 8) | data[offset + 1]);
      offset += 2;

      final topic = utf8.decode(data.sublist(offset, offset + topicLength), allowMalformed: false);
      offset += topicLength;

      final payload = data.sublist(offset);

      final messageId = ((data[offset] << 8) | data[offset + 1]);
      offset += 2;

      final isDuplicate = (data[offset] & 0x08) != 0;

      return {
        'topic': topic,
        'payload': Uint8List.fromList(payload),
        'messageId': messageId,
        'isDuplicate': isDuplicate,
      };
    } catch (e) {
      return null;
    }
  }

  /// Creates a PUBLISH packet
  Uint8List createPublishPacket({
    required String topic,
    required MqttMessage message,
    int? messageId,
    required String clientId,
    bool isDuplicate = false,
  }) {
    final remainingLength = 2 + utf8.encode(topic).length + message.payload.length + (message.qos > 0 ? 2 : 0);

    // PUBLISH packet fixed header
    // Bit 7-4: Message type (3 for PUBLISH)
    // Bit 3: DUP flag
    // Bit 2-1: QoS level
    // Bit 0: RETAIN flag
    final headerByte = 0x30 | (isDuplicate ? 0x08 : 0x00) | (message.qos << 1) | (message.retain ? 0x01 : 0x00);

    final publishPacket = BytesBuilder();
    publishPacket.addByte(headerByte);

    addRemainingLength(publishPacket, remainingLength);

    // Add topic
    publishPacket.addByte((utf8.encode(topic).length >> 8) & 0xFF);
    publishPacket.addByte(utf8.encode(topic).length & 0xFF);
    publishPacket.add(utf8.encode(topic));

    // Add message ID for QoS > 0
    if (message.qos > 0) {
      publishPacket.addByte((messageId ?? 0 >> 8) & 0xFF);
      publishPacket.addByte((messageId ?? 0) & 0xFF);
    }

    // Add payload
    publishPacket.add(message.payload);
    return publishPacket.toBytes();
  }

  /// Creates a PUBLISH packet from direct parameters
  Uint8List createPublishPacketDirect({
    required String topic,
    required Uint8List payload,
    required int qos,
    required int messageId,
    required bool retain,
    required bool isDuplicate,
  }) {
    // Calculate remaining length
    final topicBytes = utf8.encode(topic);
    int remainingLength = 2 + topicBytes.length + payload.length; // 2 for topic length
    if (qos > 0) remainingLength += 2; // 2 for message ID if QoS > 0

    // Create header byte
    int headerByte = 0x30; // PUBLISH packet type
    if (isDuplicate) headerByte |= 0x08; // DUP flag
    if (qos > 0) headerByte |= (qos << 1); // QoS level
    if (retain) headerByte |= 0x01; // RETAIN flag

    final publishPacket = BytesBuilder();
    publishPacket.addByte(headerByte);

    addRemainingLength(publishPacket, remainingLength);

    // Add topic
    publishPacket.addByte((topicBytes.length >> 8) & 0xFF);
    publishPacket.addByte(topicBytes.length & 0xFF);
    publishPacket.add(topicBytes);

    // Add message ID for QoS > 0
    if (qos > 0) {
      publishPacket.addByte((messageId >> 8) & 0xFF);
      publishPacket.addByte(messageId & 0xFF);
    }

    // Add payload
    publishPacket.add(payload);
    return publishPacket.toBytes();
  }

  /// Creates a PUBLISH packet from a message object
  /// This is used internally for compatibility with existing code
  Uint8List createPublishPacketFromMessage({
    required MqttMessage message,
    required String clientId,
    int? messageId,
  }) {
    final topic = message.topic ?? 'unknown';

    return createPublishPacketDirect(
        topic: topic, payload: message.payload, qos: message.qos, messageId: messageId ?? 0, retain: message.retain, isDuplicate: false);
  }

  /// Creates a SUBACK packet
  Uint8List createSubackPacket(int messageId, List<int> grantedQos) {
    final suback = Uint8List(4 + grantedQos.length);
    suback[0] = 0x90; // SUBACK packet type
    suback[1] = 2 + grantedQos.length; // Remaining length
    suback[2] = (messageId >> 8) & 0xFF; // Message ID MSB
    suback[3] = messageId & 0xFF; // Message ID LSB

    // Add granted QoS levels
    for (var i = 0; i < grantedQos.length; i++) {
      suback[4 + i] = grantedQos[i];
    }

    return suback;
  }

  /// Creates a PUBACK packet (for QoS 1)
  Uint8List createPubackPacket(int messageId) {
    final puback = Uint8List(4);
    puback[0] = 0x40; // PUBACK packet type
    puback[1] = 0x02; // Remaining length
    puback[2] = (messageId >> 8) & 0xFF; // Message ID MSB
    puback[3] = messageId & 0xFF; // Message ID LSB
    return puback;
  }

  /// Creates a PUBREC packet (for QoS 2, first response)
  Uint8List createPubrecPacket(int messageId) {
    final pubrec = Uint8List(4);
    pubrec[0] = 0x50; // PUBREC packet type
    pubrec[1] = 0x02; // Remaining length
    pubrec[2] = (messageId >> 8) & 0xFF; // Message ID MSB
    pubrec[3] = messageId & 0xFF; // Message ID LSB
    return pubrec;
  }

  /// Creates a PUBREL packet (for QoS 2, second response)
  Uint8List createPubrelPacket(int messageId) {
    final pubrel = Uint8List(4);
    pubrel[0] = 0x62; // PUBREL packet type (includes required flags)
    pubrel[1] = 0x02; // Remaining length
    pubrel[2] = (messageId >> 8) & 0xFF; // Message ID MSB
    pubrel[3] = messageId & 0xFF; // Message ID LSB
    return pubrel;
  }

  /// Creates a PUBCOMP packet (for QoS 2, final response)
  Uint8List createPubcompPacket(int messageId) {
    final pubcomp = Uint8List(4);
    pubcomp[0] = 0x70; // PUBCOMP packet type
    pubcomp[1] = 0x02; // Remaining length
    pubcomp[2] = (messageId >> 8) & 0xFF; // Message ID MSB
    pubcomp[3] = messageId & 0xFF; // Message ID LSB
    return pubcomp;
  }

  /// Creates an UNSUBACK packet
  Uint8List createUnsubackPacket(int messageId) {
    final unsuback = Uint8List(4);
    unsuback[0] = 0xB0; // UNSUBACK packet type
    unsuback[1] = 0x02; // Remaining length
    unsuback[2] = (messageId >> 8) & 0xFF; // Message ID MSB
    unsuback[3] = messageId & 0xFF; // Message ID LSB
    return unsuback;
  }

  /// Creates a PINGRESP packet
  Uint8List createPingrespPacket() {
    final pingresp = Uint8List(2);
    pingresp[0] = 0xD0; // PINGRESP packet type
    pingresp[1] = 0x00; // Remaining length
    return pingresp;
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

  /// Process queued messages for a client, one at a time with proper QoS handling
  /// This method processes only one message and waits for acknowledgment before processing the next
  void processQueuedMessages(String clientId) async {
    if (!_messageStore.containsKey(clientId)) return;

    final session = _broker.connectionsManager.getSession(clientId);
    if (session == null) return;

    final connection = _broker.connectionsManager.getConnection(clientId);
    if (connection == null || !connection.isConnected) return;

    // Get all queued messages (with negative IDs)
    final queuedEntries = _messageStore[clientId];
    if (queuedEntries == null || queuedEntries.isEmpty) return;

    // Process only the first message in the queue
    final message = queuedEntries.first;

    try {
      // For clean session, process all messages
      // For non-clean session, only process QoS 1 and 2 messages

      final topic = message.topic ?? 'unknown';

      // Handle based on QoS level
      switch (message.qos) {
        case 0: // QoS 0: At most once delivery

          final publishPacket = createPublishPacketDirect(
            topic: topic,
            payload: message.payload,
            qos: 0,
            messageId: 0,
            retain: message.retain,
            isDuplicate: false,
          );

          connection.send(publishPacket);
          queuedEntries.removeFirst();

          await Future.delayed(Duration(milliseconds: 50));

          processQueuedMessages(clientId);
          break;

        case 1: // QoS 1: At least once delivery

          final publishPacket = createPublishPacketDirect(
            topic: topic,
            payload: message.payload,
            qos: 1,
            messageId: message.messageId!,
            retain: message.retain,
            isDuplicate: message.state != QosMessageState.pending,
          );

          connection.send(publishPacket);
          developer.log('Sent queued QoS 1 message to $clientId with ID ${message.messageId}');
          break;

        case 2: // QoS 2: Exactly once delivery

          final publishPacket = createPublishPacketDirect(
            topic: topic,
            payload: message.payload,
            qos: 2,
            messageId: message.messageId!,
            retain: message.retain,
            isDuplicate: message.state != QosMessageState.pending,
          );
          connection.send(publishPacket);
          developer.log('Sent queued QoS 2 message to $clientId with ID ${message.messageId}');
          break;
      }
    } catch (e) {
      developer.log('Error sending queued message to client $clientId: $e');
      // If there's an error, stop processing but keep all messages in queue
    }
  }

  /// Remove all messages for a client
  void removeClientMessages(String clientId) {
    _messageStore.remove(clientId);
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
    int messageQos = 0,
    bool retain = false,
    bool isDuplicate = false,
    int? messageId,
  }) async {
    var subscripers = _broker.connectionsManager.getSubscribers(topic);

    for (var clientId in subscripers) {
      try {
        // For QoS 0, just send the message
        // For QoS 1 and 2, we need a message ID
        var session = _broker.connectionsManager.getSession(clientId);
        var actualMessageId = 0;

        var effectiveQos = min(messageQos, session?.qosLevels[topic] ?? 0);
        if (effectiveQos > 0) {
          actualMessageId = messageId ?? session?.getNextMessageId() ?? 0;
        }

        //TODO: check if message is already in the message store

        // create message and store it in the message store
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

        processQueuedMessages(clientId);
      } catch (e) {
        developer.log('Error sending message to $clientId: $e');
      }
    }
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

  /// Adds the remaining length encoding to a packet
  void addRemainingLength(BytesBuilder builder, int length) {
    do {
      var byte = length % 128;
      length = length ~/ 128;
      if (length > 0) {
        byte = byte | 0x80;
      }
      builder.addByte(byte);
    } while (length > 0);
  }
}
