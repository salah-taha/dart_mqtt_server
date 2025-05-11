import 'dart:typed_data';

class MqttPacket {
  final int type;
  final Uint8List payload;
  final Map<String, dynamic> properties;

  MqttPacket({
    required this.type,
    required this.payload,
    this.properties = const {},
  });

  bool get isDuplicate => (type & 0x08) == 0x08;
  int get qos => (type & 0x06) >> 1;
  bool get retain => (type & 0x01) == 0x01;
}
