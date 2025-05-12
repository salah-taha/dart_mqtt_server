import 'dart:typed_data';

import 'package:mqtt_server/src/core/packet_handler_base.dart';
import 'package:mqtt_server/src/models/mqtt_connection.dart';


class PubrecHandler extends PacketHandlerBase {
  PubrecHandler(super.deps);

  @override
  Future<void> handle(Uint8List data, MqttConnection connection, {int qos = 0, bool retain = false}) async {
    if (data.length < 4) return;
    if (connection.clientId == null) return;

    final session = deps.getSession(connection.clientId);
    if (session == null) return;

    // Send PUBREL
    final pubrelPacket = Uint8List(4);
    pubrelPacket[0] = 0x62; // PUBREL with QoS 1
    pubrelPacket[1] = 0x02; // Remaining length
    pubrelPacket[2] = data[2]; // Message ID MSB
    pubrelPacket[3] = data[3]; // Message ID LSB

    await connection.send(pubrelPacket);
    session.lastActivity = DateTime.now();
  }
}
