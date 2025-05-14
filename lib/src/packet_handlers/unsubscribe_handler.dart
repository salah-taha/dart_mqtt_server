import 'dart:convert';
import 'dart:typed_data';

import 'package:mqtt_server/mqtt_server.dart';
import 'package:mqtt_server/src/core/packet_generator.dart';
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

      session?.qosLevels.remove(topic);
      _broker.connectionsManager.unsubscribe(connection.clientId!, topic);
      _broker.messageManager.removeClientTopicMessages(connection.clientId!, topic);
    }

    final unsuback = PacketGenerator.unsubackPacket(messageId);
    await connection.send(unsuback);

    session?.lastActivity = DateTime.now();
  }
}
