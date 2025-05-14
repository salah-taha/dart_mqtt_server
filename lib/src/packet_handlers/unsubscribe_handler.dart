import 'dart:typed_data';

import 'package:mqtt_server/mqtt_server.dart';
import 'package:mqtt_server/src/core/packet_generator.dart';
import 'package:mqtt_server/src/core/packet_handler_base.dart';
import 'package:mqtt_server/src/core/mqtt_packet_parser.dart';
import 'package:mqtt_server/src/models/mqtt_connection.dart';

class UnsubscribeHandler extends PacketHandlerBase {
  final MqttBroker _broker;
  UnsubscribeHandler(this._broker);

  @override
  Future<void> handle(Uint8List data, MqttConnection connection) async {
    if (connection.clientId == null) return;

    final session = _broker.connectionsManager.getSession(connection.clientId!);
    
    // Use MqttPacketParser to parse the UNSUBSCRIBE packet
    final unsubscribeData = MqttPacketParser.parseUnsubscribePacket(data);
    final messageId = unsubscribeData.messageId;
    
    // Process each topic in the unsubscribe packet
    for (final topic in unsubscribeData.topics) {
      session?.qosLevels.remove(topic);
      _broker.connectionsManager.unsubscribe(connection.clientId!, topic);
      _broker.messageManager.removeClientTopicMessages(connection.clientId!, topic);
    }

    final unsuback = PacketGenerator.unsubackPacket(messageId);
    await connection.send(unsuback);

    session?.lastActivity = DateTime.now();
  }
}
