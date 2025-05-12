import 'dart:typed_data';
import 'package:mqtt_server/src/models/mqtt_connection.dart';
import 'package:mqtt_server/src/core/packet_handler_base.dart';

class DisconnectHandler extends PacketHandlerBase {
  DisconnectHandler(super.deps);

  @override
  Future<void> handle(Uint8List data, MqttConnection connection, {int qos = 0, bool retain = false}) async {
    if (connection.clientId == null) return;
    
    final session = deps.getSession(connection.clientId);
    if (session == null) return;

    // Remove client from all topic subscriptions
    for (final topic in deps.topicSubscriptions.keys.toList()) {
      deps.topicSubscriptions[topic]?.remove(connection.clientId);
      if (deps.topicSubscriptions[topic]?.isEmpty ?? false) {
        deps.topicSubscriptions.remove(topic);
      }
    }

    // Clean up session if not persistent
    if (!session.cleanSession) {
      deps.removeSession(connection.clientId!);
    }

    // Close connection
    await connection.disconnect();
  }
}
