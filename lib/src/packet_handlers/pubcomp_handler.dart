import 'dart:typed_data';

import 'package:mqtt_server/mqtt_server.dart';
import 'package:mqtt_server/src/core/packet_handler_base.dart';
import 'package:mqtt_server/src/models/mqtt_connection.dart';


class PubcompHandler extends PacketHandlerBase {
  final MqttBroker _broker;
  PubcompHandler(this._broker);

  @override
  Future<void> handle(Uint8List data, MqttConnection connection, {int qos = 0, bool retain = false}) async {
    if (data.length < 4) return;
    if (connection.clientId == null) return;

    final session = _broker.stateManager.getSession(connection.clientId);
    if (session == null) return;

    final messageId = ((data[2] << 8) | data[3]);

    // Remove message from in-flight messages
    _broker.stateManager.inFlightMessages[session.clientId]?.remove(messageId);

    session.lastActivity = DateTime.now();
  }
}
