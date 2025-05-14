import 'dart:typed_data';
import 'package:mqtt_server/src/core/packet_generator.dart';
import 'package:mqtt_server/src/models/mqtt_connection.dart';
import 'package:mqtt_server/src/core/packet_handler_base.dart';
import 'package:mqtt_server/src/mqtt_broker.dart';

class PingreqHandler extends PacketHandlerBase {
  final MqttBroker _broker;
  PingreqHandler(this._broker);

  @override
  Future<void> handle(Uint8List data, MqttConnection connection) async {
    if (connection.clientId == null) return;
    
    final session = _broker.connectionsManager.getSession(connection.clientId);
    if (session == null) return;

    // Send PINGRESP
    final pingresp = PacketGenerator.pingrespPacket();
    await connection.send(pingresp);

    session.lastActivity = DateTime.now();
  }
}
