import 'dart:typed_data';

class MqttMessage {
  final Uint8List payload;
  final int qos;
  final bool retain;
  final DateTime timestamp;

  MqttMessage(this.payload, this.qos, this.retain, DateTime? time) : timestamp = time ?? DateTime.now();

  Map<String, dynamic> toPersistentData() {
    return {
      'payload': payload,
      'qos': qos,
      'retain': retain,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory MqttMessage.fromPersistentData(Map<String, dynamic> data) {
    return MqttMessage(
      data['payload'] as Uint8List,
      data['qos'] as int,
      data['retain'] as bool,
      DateTime.parse(data['timestamp'] as String),
    );
  }
}
