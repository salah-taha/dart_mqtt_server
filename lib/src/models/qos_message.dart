import 'package:mqtt_server/src/enums/qos_message_state.dart';
import 'package:mqtt_server/src/models/mqtt_message.dart';

class QosMessage {
  final String topic;
  final MqttMessage message;
  final int messageId;
  final String clientId;
  QosMessageState state;
  DateTime timestamp;
  int retryCount;

  QosMessage({
    required this.topic,
    required this.message,
    required this.messageId,
    required this.clientId,
    required this.state,
    required this.timestamp,
    required this.retryCount,
  });
}
