import 'dart:typed_data';

import 'package:mqtt_server/src/core/packet_handler_base.dart';
import 'package:mqtt_server/src/core/mqtt_packet_parser.dart';
import 'package:mqtt_server/src/models/mqtt_connection.dart';
import 'package:mqtt_server/src/mqtt_broker.dart';

class PubackHandler extends PacketHandlerBase {
  final MqttBroker _broker;
  PubackHandler(this._broker);

  @override
  Future<void> handle(Uint8List data, MqttConnection connection) async {
    if (data.length < 4) return;
    if (connection.clientId == null) return;

    final session = _broker.connectionsManager.getSession(connection.clientId);
    if (session == null) return;

    // Use MqttPacketParser to parse the PUBACK packet
    final messageId = MqttPacketParser.parseMessageIdPacket(data);

    _broker.messageManager.incomingPubAck(messageId, connection.clientId!);

    session.lastActivity = DateTime.now();
  }
}
