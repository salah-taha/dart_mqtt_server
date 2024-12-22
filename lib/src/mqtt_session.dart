import 'package:mqtt_server/src/mqtt_message.dart';

class MqttSession {
  final String clientId;
  final Map<String, int> qosLevels = {};
  int messageId = 0;
  MqttMessage? willMessage;
  String? willTopic;
  DateTime lastActivity;

  MqttSession(this.clientId) : lastActivity = DateTime.now();

  int getNextMessageId() {
    messageId = (messageId + 1) % 65536;
    return messageId;
  }
}
