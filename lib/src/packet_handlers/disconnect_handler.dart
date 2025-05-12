import 'dart:typed_data';
import 'package:mqtt_server/src/models/mqtt_connection.dart';
import 'package:mqtt_server/src/core/packet_handler_base.dart';
import 'package:mqtt_server/src/mqtt_broker.dart';

class DisconnectHandler extends PacketHandlerBase {
  final MqttBroker _broker;
  DisconnectHandler(this._broker);

  @override
  Future<void> handle(Uint8List data, MqttConnection connection, {int qos = 0, bool retain = false}) async {
    if (connection.clientId == null) return;
    
    final session = _broker.stateManager.getSession(connection.clientId);
    if (session == null) return;

    // Remove client from all topic subscriptions
    for (final topic in _broker.stateManager.topicSubscriptions.keys.toList()) {
      _broker.stateManager.topicSubscriptions[topic]?.remove(connection.clientId);
      if (_broker.stateManager.topicSubscriptions[topic]?.isEmpty ?? false) {
        _broker.stateManager.topicSubscriptions.remove(topic);
      }
    }

    // Clean up session if not persistent
    if (!session.cleanSession) {
      _broker.stateManager.removeSession(connection.clientId!);
    }

    // Close connection
    await connection.disconnect();
  }
}
