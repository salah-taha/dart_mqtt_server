import 'package:mqtt_server/src/mqtt_connection.dart';
import 'package:mqtt_server/src/models/mqtt_message.dart';
import 'dart:collection';

class BrokerPublishEvent {
  final String topic;
  final MqttMessage message;
  final MqttConnection publisher;
  final bool retain;
  final Set<MqttConnection> subscribers;

  BrokerPublishEvent({
    required this.topic,
    required this.message,
    required this.publisher,
    required this.retain,
    required Set<MqttConnection> subscribers,
  }) : subscribers = UnmodifiableSetView(subscribers);

  get payload => message.payload;
}
