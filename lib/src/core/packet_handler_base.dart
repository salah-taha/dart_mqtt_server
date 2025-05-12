import 'dart:typed_data';
import 'package:mqtt_server/src/models/mqtt_connection.dart';
import 'package:mqtt_server/src/core/handler_dependencies.dart';

abstract class PacketHandlerBase {
  final HandlerDependencies deps;

  PacketHandlerBase(this.deps);

  Future<void> handle(Uint8List data, MqttConnection connection, {int qos = 0, bool retain = false});
}
