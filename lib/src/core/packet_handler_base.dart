import 'dart:typed_data';
import 'package:mqtt_server/src/models/mqtt_connection.dart';

abstract class PacketHandlerBase {

  PacketHandlerBase();

  Future<void> handle(Uint8List data, MqttConnection connection);
}
