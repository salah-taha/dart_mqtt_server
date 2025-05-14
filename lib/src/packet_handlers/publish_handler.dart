import 'dart:typed_data';

import 'package:mqtt_server/mqtt_server.dart';
import 'package:mqtt_server/src/core/packet_generator.dart';
import 'package:mqtt_server/src/core/packet_handler_base.dart';
import 'package:mqtt_server/src/core/mqtt_packet_parser.dart';
import 'package:mqtt_server/src/models/mqtt_connection.dart';

class PublishHandler extends PacketHandlerBase {
  final MqttBroker _broker;

  PublishHandler(this._broker);

  @override
  Future<void> handle(Uint8List data, MqttConnection connection) async {
    if (connection.clientId == null) return;

    final session = _broker.connectionsManager.getSession(connection.clientId);
    if (session == null) {
      return;
    }

    // Use MqttPacketParser to parse the PUBLISH packet
    final publishData = MqttPacketParser.parsePublishPacket(data);

    final topic = publishData.topic;
    final payload = publishData.payload;
    final messageId = publishData.messageId ?? 0;
    final isDuplicate = publishData.duplicate;
    final qos = publishData.qos;
    final retain = publishData.retain;
    

    // send message to subscribers
    await _broker.messageManager.sendMessage(
      topic: topic,
      payload: payload,
      messageQos: qos,
      retain: retain,
      messageId: messageId,
      isDuplicate: isDuplicate,
      senderId: connection.clientId!,
    );

    // store retained message
    _broker.messageManager.storeRetainedMessage(topic, payload, qos, retain);

    session.lastActivity = DateTime.now();

    if (qos == 1) {
      var packet = PacketGenerator.pubackPacket(messageId);
      connection.send(packet);
    }
    else if (qos == 2) {
      var packet = PacketGenerator.pubrecPacket(messageId);
      connection.send(packet);
    }

  }
}
