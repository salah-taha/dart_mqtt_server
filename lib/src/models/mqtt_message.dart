import 'dart:convert';
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
  
  // Helper method to get base64 encoded payload
  String get encodedPayload => base64Encode(payload);

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

  // Manual JSON serialization methods
  factory MqttMessage.fromJson(Map<String, dynamic> json) {
    // Convert base64 encoded payload back to Uint8List
    final payload = base64Decode(json['encodedPayload'] as String);
    
    // Parse QosMessageState from string if present
    QosMessageState? state;
    if (json.containsKey('state') && json['state'] != null) {
      final stateStr = json['state'] as String;
      state = QosMessageState.values.firstWhere(
        (s) => s.toString() == stateStr,
        orElse: () => QosMessageState.pending,
      );
    }
    
    return MqttMessage(
      payload,
      json['qos'] as int,
      json['retain'] as bool,
      DateTime.parse(json['timestamp'] as String),
      topic: json['topic'] as String?,
      state: state,
      messageId: json['messageId'] as int?,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'encodedPayload': encodedPayload,
      'qos': qos,
      'retain': retain,
      'timestamp': timestamp.toIso8601String(),
      'topic': topic,
      'state': state?.toString(),
      'messageId': messageId,
    };
  }


 
}
