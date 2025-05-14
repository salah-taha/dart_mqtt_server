import 'dart:typed_data';

import 'package:mqtt_server/src/enums/qos_message_state.dart';

class MqttMessage {
  final Uint8List payload;
  final int qos;
  final bool retain;
  final DateTime timestamp;
  final String? topic; 
  QosMessageState? state;
  int? messageId;

  MqttMessage(this.payload, this.qos, this.retain, DateTime? time, {this.topic, this.state, this.messageId})
      : timestamp = time ?? DateTime.now();

  MqttMessage copyWith({
    Uint8List? payload,
    int? qos,
    bool? retain,
    DateTime? timestamp,
    String? topic,
    QosMessageState? state,
    int? messageId,
  }) {
    return MqttMessage(
      payload ?? this.payload,
      qos ?? this.qos,
      retain ?? this.retain,
      timestamp ?? this.timestamp,
      topic: topic ?? this.topic,
      state: state ?? this.state,
      messageId: messageId ?? this.messageId,
    );
  }

  Map<String, dynamic> toPersistentData() {
    return {
      'payload': payload,
      'qos': qos,
      'retain': retain,
      'timestamp': timestamp.toIso8601String(),
      'topic': topic,
    };
  }

  factory MqttMessage.fromPersistentData(Map<String, dynamic> data) {
    return MqttMessage(
      data['payload'] as Uint8List,
      data['qos'] as int,
      data['retain'] as bool,
      DateTime.parse(data['timestamp'] as String),
      topic: data['topic'] as String?,
    );
  }
}
