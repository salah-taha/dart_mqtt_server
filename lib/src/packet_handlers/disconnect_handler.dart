import 'dart:typed_data';
import '../mqtt_connection.dart';
import 'packet_handler_base.dart';

class DisconnectHandler extends PacketHandlerBase {
  DisconnectHandler(super.deps);

  @override
  Future<void> handle(Uint8List data, MqttConnection client, {int qos = 0, bool retain = false}) async {
    final session = deps.getSession(client);
    if (session == null) return;

    // Remove client from all topic subscriptions
    for (final topic in deps.topicSubscriptions.keys.toList()) {
      deps.topicSubscriptions[topic]?.remove(client);
      if (deps.topicSubscriptions[topic]?.isEmpty ?? false) {
        deps.topicSubscriptions.remove(topic);
      }
    }

    // Clean up session if not persistent
    if (!session.cleanSession) {
      deps.removeSession(client);
    }

    // Close connection
    await client.disconnect();
  }
}
