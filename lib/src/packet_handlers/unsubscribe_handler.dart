import 'dart:convert';
import 'dart:typed_data';

import 'package:mqtt_server/mqtt_server.dart';
import 'package:mqtt_server/src/core/packet_handler_base.dart';
import 'package:mqtt_server/src/models/mqtt_connection.dart';

class UnsubscribeHandler extends PacketHandlerBase {
  final MqttBroker _broker;
  UnsubscribeHandler(this._broker);

  @override
  Future<void> handle(Uint8List data, MqttConnection connection, {int qos = 0, bool retain = false}) async {
    if (connection.clientId == null) return;

    final session = _broker.connectionsManager.getSession(connection.clientId!);
    final messageId = ((data[2] << 8) | data[3]);
    var pos = 4;

    while (pos < data.length) {
      if (pos + 2 > data.length) break;

      final topicLength = ((data[pos] << 8) | data[pos + 1]);
      pos += 2;

      if (pos + topicLength > data.length) break;

      final topic = utf8.decode(data.sublist(pos, pos + topicLength));
      pos += topicLength;

      // Remove QoS level for this topic
      session?.qosLevels.remove(topic);

      // Remove client from topic subscribers
      _broker.connectionsManager.unsubscribe(connection.clientId!, topic);

      //TODO: remove topic messages in queue
    }

    // Send UNSUBACK
    final unsuback = Uint8List.fromList([0xB0, 0x02, (messageId >> 8) & 0xFF, messageId & 0xFF]);
    await connection.send(unsuback);

    session?.lastActivity = DateTime.now();
  }
}
