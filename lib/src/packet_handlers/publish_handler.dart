import 'dart:convert';
import 'dart:typed_data';

import 'package:mqtt_server/src/core/packet_handler_base.dart';
import 'package:mqtt_server/src/models/mqtt_connection.dart';
import 'package:mqtt_server/src/models/mqtt_message.dart';


class PublishHandler extends PacketHandlerBase {
  PublishHandler(super.deps);

  @override
  Future<void> handle(Uint8List data, MqttConnection connection, {int qos = 0, bool retain = false}) async {
    if (connection.clientId == null) return;

    final session = deps.getSession(connection.clientId);
    if (session == null) {
      return;
    }

    final extractResult = _extractPublishData(data);
    if (extractResult == null) {
      return;
    }

    final topic = extractResult['topic'] as String;
    final payload = extractResult['payload'] as Uint8List;
    final message = MqttMessage(payload, qos, retain, DateTime.now());

    _handleRetainedMessage(topic, payload, retain, message);

    // Get active subscribers for this topic
    final subscriberIds = _getSubscribersForTopic(topic);

    if (subscriberIds.isNotEmpty) {
      for (final subscriberId in subscriberIds) {
        final subscriberSession = deps.getSession(subscriberId);
        if (subscriberSession == null) continue;
        
        final subscriberConnection = _getConnection(subscriberId);
        final subscriberQos = subscriberSession.qosLevels[topic] ?? 0;
        final effectiveQos = qos < subscriberQos ? qos : subscriberQos;

        // If QoS > 0 , queue the message for message delivery
        if (effectiveQos > 0) {
          deps.queueMessage(subscriberId, topic, payload, effectiveQos);
        }

        // Skip if subscriber is offline and QoS is 0
        if (subscriberConnection == null || !subscriberConnection.isConnected) continue;

        int? messageId;
        if (effectiveQos > 0) {
          messageId = subscriberSession.getNextMessageId();
        }

        final packet = _createPublishPacket(
          topic,
          message,
          messageId,
          subscriberSession.clientId,
        );

        await subscriberConnection.send(packet);
      }
    }

    session.lastActivity = DateTime.now();
  }

  Map<String, dynamic>? _extractPublishData(Uint8List data) {
    try {
      var offset = 2;

      if (offset + 2 > data.length) {
        return null;
      }

      final topicLength = ((data[offset] << 8) | data[offset + 1]);
      offset += 2;

      if (offset + topicLength > data.length) {
        return null;
      }

      final topic = utf8.decode(data.sublist(offset, offset + topicLength), allowMalformed: false);
      offset += topicLength;

      final payload = data.sublist(offset);

      return {
        'topic': topic,
        'payload': Uint8List.fromList(payload),
      };
    } catch (e) {
      return null;
    }
  }

  void _handleRetainedMessage(String topic, Uint8List payload, bool retain, MqttMessage message) {
    if (retain) {
      if (payload.isEmpty) {
        deps.retainedMessages.remove(topic);
      } else {
        deps.retainedMessages[topic] = message;
      }
    }
  }

  Set<String> _getSubscribersForTopic(String topic) {
    final subscribers = <String>{};

    for (final entry in deps.topicSubscriptions.entries) {
      // Quick check for direct match
      if (entry.key == topic) {
        subscribers.addAll(entry.value);
        continue;
      }

      // Check wildcard patterns
      final pattern = entry.key;
      if (pattern.contains('+') || pattern.endsWith('#')) {
        if (_matchTopicPattern(topic, pattern)) {
          subscribers.addAll(entry.value);
        }
      }
    }

    return subscribers;
  }

  MqttConnection? _getConnection(String clientId) {
    return deps.clientConnections[clientId];
  }

  bool _matchTopicPattern(String topic, String pattern) {
    if (topic == pattern) return true;

    final topicParts = topic.split('/');
    final patternParts = pattern.split('/');

    // Handle trailing '#' wildcard
    if (pattern.endsWith('#')) {
      patternParts.removeLast();
      if (topicParts.length < patternParts.length) return false;

      // Check all parts before '#'
      return !patternParts.asMap().entries.any((entry) {
        final i = entry.key;
        final part = entry.value;
        return part != '+' && part != topicParts[i];
      });
    }

    // For exact matches, lengths must be equal
    if (topicParts.length != patternParts.length) return false;

    // Check each part matches or is wildcard
    return patternParts.asMap().entries.every((entry) {
      final i = entry.key;
      final part = entry.value;
      return part == '+' || part == topicParts[i];
    });
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
}
