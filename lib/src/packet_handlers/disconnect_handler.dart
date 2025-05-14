import 'dart:typed_data';
import 'package:mqtt_server/src/models/mqtt_connection.dart';
import 'package:mqtt_server/src/core/packet_handler_base.dart';
import 'package:mqtt_server/src/mqtt_broker.dart';

class DisconnectHandler extends PacketHandlerBase {
  final MqttBroker _broker;
  DisconnectHandler(this._broker);

  @override
  Future<void> handle(Uint8List data, MqttConnection connection) async {
    if (connection.clientId == null) return;

    _broker.connectionsManager.disconnectClient(connection.clientId!);
  }
}
