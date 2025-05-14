import 'dart:typed_data';

import 'package:mqtt_server/mqtt_server.dart';
import 'package:mqtt_server/src/core/packet_generator.dart';
import 'package:mqtt_server/src/core/packet_handler_base.dart';
import 'package:mqtt_server/src/models/mqtt_connection.dart';

class PubrelHandler extends PacketHandlerBase {
  final MqttBroker _broker;
  PubrelHandler(this._broker);

  @override
  Future<void> handle(Uint8List data, MqttConnection connection, {int qos = 0, bool retain = false}) async {
    if (data.length < 4) return;
    if (connection.clientId == null) return;

    final session = _broker.connectionsManager.getSession(connection.clientId);
    if (session == null) return;

    var messageId = (data[2] << 8) | data[3];
    var messageExisting = _broker.messageManager.incomingPubRel(messageId, connection.clientId!);

    if (messageExisting) {
      final pubcompPacket = PacketGenerator.pubcompPacket(messageId);
      await connection.send(pubcompPacket);
    }
    
    session.lastActivity = DateTime.now();
  }
}
