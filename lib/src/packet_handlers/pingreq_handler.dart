import 'dart:typed_data';
import '../mqtt_connection.dart';
import 'packet_handler_base.dart';

class PingreqHandler extends PacketHandlerBase {
  PingreqHandler(super.deps);

  @override
  Future<void> handle(Uint8List data, MqttConnection client, {int qos = 0, bool retain = false}) async {
    final session = deps.getSession(client);
    if (session == null) return;

    // Send PINGRESP
    final pingresp = Uint8List.fromList([0xD0, 0x00]);
    await client.send(pingresp);

    session.lastActivity = DateTime.now();
  }
}
