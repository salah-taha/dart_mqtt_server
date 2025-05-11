import 'dart:typed_data';
import '../mqtt_connection.dart';
import '../mqtt_broker.dart';
import 'packet_handler_base.dart';

class PubrelHandler extends PacketHandlerBase {
  PubrelHandler(MqttBroker broker) : super(broker);

  @override
  Future<void> handle(Uint8List data, MqttConnection client, {int qos = 0, bool retain = false}) async {
    if (data.length < 4) return;

    final session = deps.getSession(client);
    if (session == null) return;

    // Send PUBCOMP
    final pubcompPacket = Uint8List(4);
    pubcompPacket[0] = 0x70; // PUBCOMP
    pubcompPacket[1] = 0x02; // Remaining length
    pubcompPacket[2] = data[2]; // Message ID MSB
    pubcompPacket[3] = data[3]; // Message ID LSB

    await client.send(pubcompPacket);
    session.lastActivity = DateTime.now();
  }
}
