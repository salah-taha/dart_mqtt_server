import 'dart:typed_data';

import 'package:mqtt_server/mqtt_server.dart';
import 'package:mqtt_server/src/core/packet_generator.dart';
import 'package:mqtt_server/src/core/packet_handler_base.dart';
import 'package:mqtt_server/src/core/mqtt_packet_parser.dart';
import 'package:mqtt_server/src/models/mqtt_connection.dart';


class PubrecHandler extends PacketHandlerBase {
  final MqttBroker _broker;
  PubrecHandler(this._broker);

  @override
  Future<void> handle(Uint8List data, MqttConnection connection) async {
    if (data.length < 4) return;
    if (connection.clientId == null) return;

    final session = _broker.connectionsManager.getSession(connection.clientId);
    if (session == null) return;

    // Use MqttPacketParser to parse the PUBREC packet
    final messageId = MqttPacketParser.parseMessageIdPacket(data);
    var messageExisting = _broker.messageManager.incomingPubRec(messageId, connection.clientId!);

    if (messageExisting) {
      final pubrelPacket = PacketGenerator.pubrelPacket(messageId);
      await connection.send(pubrelPacket);
    }
    session.lastActivity = DateTime.now();
  }
}
