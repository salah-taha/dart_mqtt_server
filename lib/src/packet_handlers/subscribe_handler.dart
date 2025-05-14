import 'dart:typed_data';

import 'package:mqtt_server/src/core/packet_generator.dart';
import 'package:mqtt_server/src/core/packet_handler_base.dart';
import 'package:mqtt_server/src/core/mqtt_packet_parser.dart';
import 'package:mqtt_server/src/models/mqtt_connection.dart';
import 'package:mqtt_server/src/mqtt_broker.dart';

class SubscribeHandler extends PacketHandlerBase {
  final MqttBroker _broker;

  SubscribeHandler(this._broker);

  @override
  Future<void> handle(Uint8List data, MqttConnection connection) async {
    if (connection.clientId == null) return;

    final session = _broker.connectionsManager.getSession(connection.clientId!);
    
    // Use MqttPacketParser to parse the SUBSCRIBE packet
    final subscribeData = MqttPacketParser.parseSubscribePacket(data);
    final messageId = subscribeData.messageId;
    final grantedQos = <int>[];

    for (final subscription in subscribeData.subscriptions) {
      final topic = subscription.topic;
      final requestedQos = subscription.qos;
      grantedQos.add(requestedQos);

      session?.qosLevels[topic] = requestedQos;

      _broker.connectionsManager.subscribe(connection.clientId!, topic, requestedQos);
      _broker.messageManager.sendRetainedMessage(clientId: connection.clientId!, topic: topic);
    }

    final suback = PacketGenerator.subackPacket(messageId, grantedQos);
    await connection.send(suback);

    session?.lastActivity = DateTime.now();
  }

}
