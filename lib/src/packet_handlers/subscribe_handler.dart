import 'dart:convert';
import 'dart:typed_data';

import 'package:mqtt_server/src/core/packet_handler_base.dart';
import 'package:mqtt_server/src/models/mqtt_connection.dart';
import 'package:mqtt_server/src/models/mqtt_message.dart';
import 'package:mqtt_server/src/mqtt_broker.dart';

class SubscribeHandler extends PacketHandlerBase {
  final MqttBroker _broker;
  SubscribeHandler(this._broker);

  @override
  Future<void> handle(Uint8List data, MqttConnection connection, {int qos = 0, bool retain = false}) async {
    if (connection.clientId == null) return;
    
    final session = _broker.stateManager.getSession(connection.clientId)!;
    final messageId = ((data[2] << 8) | data[3]);
    var pos = 4;

    final grantedQos = <int>[];

    while (pos < data.length) {
      if (pos + 2 > data.length) break;

      final topicLength = ((data[pos] << 8) | data[pos + 1]);
      pos += 2;

      if (pos + topicLength > data.length) break;

      final topic = utf8.decode(data.sublist(pos, pos + topicLength));
      pos += topicLength;

      if (pos >= data.length) break;

      final requestedQos = data[pos++] & 0x03;
      grantedQos.add(requestedQos);

      session.qosLevels[topic] = requestedQos;

      // Add client to topic subscribers
      _broker.stateManager.topicSubscriptions.putIfAbsent(topic, () => <String>{}).add(connection.clientId!);

      // Send retained messages for this topic
      _sendRetainedMessages(topic, connection, session);
    }

    // Send SUBACK
    final suback = Uint8List(4 + grantedQos.length);
    suback[0] = 0x90;
    suback[1] = 2 + grantedQos.length;
    suback[2] = (messageId >> 8) & 0xFF;
    suback[3] = messageId & 0xFF;

    for (var i = 0; i < grantedQos.length; i++) {
      suback[4 + i] = grantedQos[i];
    }

    await connection.send(suback);

    session.lastActivity = DateTime.now();
  }

  void _sendRetainedMessages(String subscribedTopic, MqttConnection connection, session) {
    for (final entry in _broker.stateManager.retainedMessages.entries) {
      final topic = entry.key;
      final message = entry.value;

      if (_matchTopicPattern(topic, subscribedTopic)) {
        final subscriberQos = session.qosLevels[subscribedTopic] ?? 0;
        final effectiveQos = message.qos < subscriberQos ? message.qos : subscriberQos;

        int? messageId;
        if (effectiveQos > 0) {
          messageId = session.getNextMessageId();
        }

        final packet = _createPublishPacket(
          topic,
          message,
          messageId,
          session.clientId,
        );

        connection.send(packet);
      }
    }
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
