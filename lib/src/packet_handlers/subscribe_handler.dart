import 'dart:typed_data';

import 'package:mqtt_server/src/core/packet_handler_base.dart';
import 'package:mqtt_server/src/models/mqtt_connection.dart';
import 'package:mqtt_server/src/mqtt_broker.dart';

class SubscribeHandler extends PacketHandlerBase {
  final MqttBroker _broker;

  SubscribeHandler(this._broker);

  @override
  Future<void> handle(Uint8List data, MqttConnection connection, {int qos = 0, bool retain = false}) async {
    if (connection.clientId == null) return;

    final session = _broker.connectionsManager.getSession(connection.clientId!);
    final messageId = _broker.messageManager.extractMessageId(data) ?? 0;
    final subscriptions = _broker.messageManager.extractSubscriptions(data);
    final grantedQos = <int>[];

    for (final subscription in subscriptions) {
      final topic = subscription['topic'] as String;
      final requestedQos = subscription['qos'] as int;
      grantedQos.add(requestedQos);

      session?.qosLevels[topic] = requestedQos;

      // Add client to topic subscribers
      _broker.connectionsManager.subscribe(connection.clientId!, topic, qos);

      //TODO: Send retained messages for this topic
    }

    // Send SUBACK using the MessageManager
    final suback = _broker.messageManager.createSubackPacket(messageId, grantedQos);

    await connection.send(suback);

    session?.lastActivity = DateTime.now();
  }

}
