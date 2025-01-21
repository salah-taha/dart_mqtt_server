import 'dart:typed_data';

class MqttMessage {
  final Uint8List payload;
  final int qos;
  final bool retain;
  final DateTime timestamp;

  MqttMessage(this.payload, this.qos, this.retain) : timestamp = DateTime.now();
}
