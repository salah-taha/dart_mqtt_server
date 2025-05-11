import 'dart:typed_data';
import '../mqtt_connection.dart';
import '../mqtt_broker.dart';
import 'packet_handler_base.dart';

class PubackHandler extends PacketHandlerBase {
  PubackHandler(MqttBroker broker) : super(broker);

  @override
  Future<void> handle(Uint8List data, MqttConnection client, {int qos = 0, bool retain = false}) async {
    if (data.length < 4) return;

    final session = deps.getSession(client);
    if (session == null) return;

    final messageId = ((data[2] << 8) | data[3]);

    // Remove message from in-flight messages
    deps.inFlightMessages[session.clientId]?.remove(messageId);

    session.lastActivity = DateTime.now();
  }
}
