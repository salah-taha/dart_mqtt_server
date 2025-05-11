import 'dart:typed_data';
import '../mqtt_connection.dart';
import '../mqtt_broker.dart';
import 'packet_handler_base.dart';

class PubrecHandler extends PacketHandlerBase {
  PubrecHandler(MqttBroker broker) : super(broker);

  @override
  Future<void> handle(Uint8List data, MqttConnection client, {int qos = 0, bool retain = false}) async {
    if (data.length < 4) return;

    final session = deps.getSession(client);
    if (session == null) return;

    // Send PUBREL
    final pubrelPacket = Uint8List(4);
    pubrelPacket[0] = 0x62; // PUBREL with QoS 1
    pubrelPacket[1] = 0x02; // Remaining length
    pubrelPacket[2] = data[2]; // Message ID MSB
    pubrelPacket[3] = data[3]; // Message ID LSB

    await client.send(pubrelPacket);
    session.lastActivity = DateTime.now();
  }
}
