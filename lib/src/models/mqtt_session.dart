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

  MqttSession(this.clientId, this.cleanSession, {this.willTopic, this.willMessage})
      : lastActivity = DateTime.now(),
        keepAlive = 60;

  // Manual JSON serialization methods
  factory MqttSession.fromJson(Map<String, dynamic> json) {
    final session = MqttSession(
      json['clientId'] as String,
      json['cleanSession'] as bool,
    );
    
    // Parse qosLevels
    if (json.containsKey('qosLevels') && json['qosLevels'] != null) {
      final qosMap = json['qosLevels'] as Map<String, dynamic>;
      session.qosLevels.addAll(
        qosMap.map((key, value) => MapEntry(key, value as int)),
      );
    }
    
    // Parse messageId
    if (json.containsKey('messageId')) {
      session.messageId = json['messageId'] as int;
    }
    
    // Parse willMessage
    if (json.containsKey('willMessage') && json['willMessage'] != null) {
      session.willMessage = MqttMessage.fromJson(json['willMessage'] as Map<String, dynamic>);
    }
    
    // Parse willTopic
    if (json.containsKey('willTopic')) {
      session.willTopic = json['willTopic'] as String?;
    }
    
    // Parse lastActivity
    if (json.containsKey('lastActivity')) {
      session.lastActivity = DateTime.parse(json['lastActivity'] as String);
    }
    
    // Parse keepAlive
    if (json.containsKey('keepAlive')) {
      session.keepAlive = json['keepAlive'] as int;
    }
    
    return session;
  }
  
  Map<String, dynamic> toJson() {
    return {
      'clientId': clientId,
      'qosLevels': qosLevels,
      'messageId': messageId,
      'willMessage': willMessage?.toJson(),
      'willTopic': willTopic,
      'lastActivity': lastActivity.toIso8601String(),
      'keepAlive': keepAlive,
      'cleanSession': cleanSession,
    };
  }

  int getNextMessageId() {
    messageId = (messageId + 1) % 65536;
    if (messageId == 0) messageId = 1;
    return messageId;
  }

}
