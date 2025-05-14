import 'dart:convert';
import 'dart:typed_data';

class PacketGenerator {
  static Uint8List connectackPacket(int returnCode) {
    final connectack = Uint8List(4);
    connectack[0] = 0x20; // CONNACK packet type
    connectack[1] = 0x02; // Remaining length
    connectack[2] = 0x00; // Flags
    connectack[3] = returnCode; // Return code
    return connectack;
  }

  static Uint8List pingrespPacket() {
    final pingresp = Uint8List(2);
    pingresp[0] = 0xD0; // PINGRESP packet type
    pingresp[1] = 0x00; // Remaining length
    return pingresp;
  }

  static Uint8List unsubackPacket(int messageId) {
    final unsuback = Uint8List(4);
    unsuback[0] = 0xB0; // UNSUBACK packet type
    unsuback[1] = 0x02; // Remaining length
    unsuback[2] = (messageId >> 8) & 0xFF; // Message ID MSB
    unsuback[3] = messageId & 0xFF; // Message ID LSB
    return unsuback;
  }

  static Uint8List pubcompPacket(int messageId) {
    final pubcomp = Uint8List(4);
    pubcomp[0] = 0x70; // PUBCOMP packet type
    pubcomp[1] = 0x02; // Remaining length
    pubcomp[2] = (messageId >> 8) & 0xFF; // Message ID MSB
    pubcomp[3] = messageId & 0xFF; // Message ID LSB
    return pubcomp;
  }

  static Uint8List pubrelPacket(int messageId) {
    final pubrel = Uint8List(4);
    pubrel[0] = 0x62; // PUBREL packet type (includes required flags)
    pubrel[1] = 0x02; // Remaining length
    pubrel[2] = (messageId >> 8) & 0xFF; // Message ID MSB
    pubrel[3] = messageId & 0xFF; // Message ID LSB
    return pubrel;
  }

  static Uint8List pubrecPacket(int messageId) {
    final pubrec = Uint8List(4);
    pubrec[0] = 0x50; // PUBREC packet type
    pubrec[1] = 0x02; // Remaining length
    pubrec[2] = (messageId >> 8) & 0xFF; // Message ID MSB
    pubrec[3] = messageId & 0xFF; // Message ID LSB
    return pubrec;
  }

  static Uint8List pubackPacket(int messageId) {
    final puback = Uint8List(4);
    puback[0] = 0x40; // PUBACK packet type
    puback[1] = 0x02; // Remaining length
    puback[2] = (messageId >> 8) & 0xFF; // Message ID MSB
    puback[3] = messageId & 0xFF; // Message ID LSB
    return puback;
  }

  static Uint8List subackPacket(int messageId, List<int> grantedQos) {
    final suback = Uint8List(4 + grantedQos.length);
    suback[0] = 0x90; // SUBACK packet type
    suback[1] = 2 + grantedQos.length; // Remaining length
    suback[2] = (messageId >> 8) & 0xFF; // Message ID MSB
    suback[3] = messageId & 0xFF; // Message ID LSB

    // Add granted QoS levels
    for (var i = 0; i < grantedQos.length; i++) {
      suback[4 + i] = grantedQos[i];
    }

    return suback;
  }

  static Uint8List publishPacket({
    required String topic,
    required Uint8List payload,
    required int qos,
    required int messageId,
    required bool retain,
    required bool isDuplicate,
  }) {
    // Calculate remaining length
    final topicBytes = utf8.encode(topic);
    int remainingLength = 2 + topicBytes.length + payload.length; // 2 for topic length
    if (qos > 0) remainingLength += 2; // 2 for message ID if QoS > 0

    // Create header byte
    int headerByte = 0x30; // PUBLISH packet type
    if (isDuplicate) headerByte |= 0x08; // DUP flag
    if (qos > 0) headerByte |= (qos << 1); // QoS level
    if (retain) headerByte |= 0x01; // RETAIN flag

    final publishPacket = BytesBuilder();
    publishPacket.addByte(headerByte);

    _addRemainingLength(publishPacket, remainingLength);

    // Add topic
    publishPacket.addByte((topicBytes.length >> 8) & 0xFF);
    publishPacket.addByte(topicBytes.length & 0xFF);
    publishPacket.add(topicBytes);

    // Add message ID for QoS > 0
    if (qos > 0) {
      publishPacket.addByte((messageId >> 8) & 0xFF);
      publishPacket.addByte(messageId & 0xFF);
    }

    // Add payload
    publishPacket.add(payload);
    return publishPacket.toBytes();
  }

  static void _addRemainingLength(BytesBuilder builder, int length) {
    do {
      var byte = length % 128;
      length = length ~/ 128;
      if (length > 0) {
        byte = byte | 0x80;
      }
      builder.addByte(byte);
    } while (length > 0);
  }
}
