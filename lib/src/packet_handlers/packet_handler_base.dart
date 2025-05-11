import 'dart:typed_data';
import '../mqtt_connection.dart';
import 'handler_dependencies.dart';

abstract class PacketHandlerBase {
  final HandlerDependencies deps;

  PacketHandlerBase(this.deps);

  Future<void> handle(Uint8List data, MqttConnection client, {int qos = 0, bool retain = false});
}
