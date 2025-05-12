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

  MqttSession(this.clientId, this.cleanSession)
      : lastActivity = DateTime.now(),
        keepAlive = 60;

  factory MqttSession.fromPersistentData(Map<String, dynamic> data) {
    var clientId = data['clientId'] as String? ?? '';
    final session = MqttSession(clientId, data['cleanSession'] ?? true);

    if (data.containsKey('qosLevels')) {
      final qosMap = data['qosLevels'] as Map<String, dynamic>;
      session.qosLevels.addAll(
        qosMap.map((key, value) => MapEntry(key, value as int)),
      );
    }

    if (data.containsKey('messageId')) {
      session.messageId = data['messageId'] as int;
    }

    if (data.containsKey('willMessage')) {
      session.willMessage = MqttMessage.fromPersistentData(data['willMessage'] as Map<String, dynamic>);
    }

    if (data.containsKey('willTopic')) {
      session.willTopic = data['willTopic'] as String;
    }

    if (data.containsKey('lastActivity')) {
      session.lastActivity = DateTime.parse(data['lastActivity'] as String);
    }

    if (data.containsKey('keepAlive')) {
      session.keepAlive = data['keepAlive'] as int;
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
      'messageId': messageId,
      'willMessage': willMessage?.toPersistentData(),
      'willTopic': willTopic,
      'lastActivity': lastActivity.toIso8601String(),
      'keepAlive': keepAlive,
      'cleanSession': cleanSession,
      'clientId': clientId,
    };
  }
}
