import 'dart:typed_data';

import 'package:mqtt_server/mqtt_server.dart';
import 'package:mqtt_server/src/core/packet_handler_base.dart';
import 'package:mqtt_server/src/models/mqtt_connection.dart';


class PublishHandler extends PacketHandlerBase {
  final MqttBroker _broker;
  
  PublishHandler(this._broker);

  @override
  Future<void> handle(Uint8List data, MqttConnection connection, {int qos = 0, bool retain = false}) async {
    if (connection.clientId == null) return;

    final session = _broker.connectionsManager.getSession(connection.clientId);
    if (session == null) {
      return;
    }

    final extractResult = _broker.messageManager.extractPublishData(data);
    if (extractResult == null) {
      return;
    }

    final topic = extractResult['topic'] as String;
    final payload = extractResult['payload'] as Uint8List;
    final messageId = extractResult['messageId'] as int;
    final isDuplicate = extractResult['isDuplicate'] as bool;


    // Get active subscribers for this topic
    await _broker.messageManager.sendMessage(
      topic: topic,
      payload: payload,
      messageQos: qos,
      retain: retain,
      messageId: messageId,
      isDuplicate: isDuplicate,
        );

    session.lastActivity = DateTime.now();

    // send puback if QoS 1
    if (qos == 1) {
      var packet = _broker.messageManager.createPubackPacket(messageId);
      connection.send(packet);
    } 

    // send pubrec if QoS 2
    else if (qos == 2) {
      var packet = _broker.messageManager.createPubrecPacket(messageId);
      connection.send(packet);
    }
  }
}
