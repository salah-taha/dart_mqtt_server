import 'package:mqtt_server/src/models/mqtt_message.dart';

class MqttSession {
  final String clientId;
  final Map<String, int> qosLevels = {};
  int messageId = 0;
  MqttMessage? willMessage;
  String? willTopic;
  DateTime lastActivity;
  int keepAlive;
  bool cleanSession;

  MqttSession(this.clientId)
      : lastActivity = DateTime.now(),
        keepAlive = 60,
        cleanSession = true;

  factory MqttSession.fromPersistentData(String clientId, Map<String, dynamic> data) {
    final session = MqttSession(clientId);
    
    if (data.containsKey('qosLevels')) {
      final qosMap = data['qosLevels'] as Map<String, dynamic>;
      session.qosLevels.addAll(
        qosMap.map((key, value) => MapEntry(key, value as int)),
      );
    }
    
    return session;
  }

  int getNextMessageId() {
    messageId = (messageId + 1) % 65536;
    if (messageId == 0) messageId = 1;
    return messageId;
  }

  Map<String, dynamic> toPersistentData() {
    return {
      'qosLevels': qosLevels,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
}
