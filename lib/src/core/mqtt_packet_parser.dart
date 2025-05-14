import 'dart:convert';
import 'dart:typed_data';

/// A utility class for parsing MQTT packets
class MqttPacketParser {
  /// Extract the packet type from the first byte of an MQTT packet
  static int getPacketType(Uint8List data) {
    if (data.isEmpty) return 0;
    return (data[0] >> 4) & 0x0F;
  }

  /// Parse a CONNECT packet and return a record with the extracted values
  /// Returns (protocol, version, flags, keepAlive, clientId, willTopic, willMessage, username, password)
  static ({
    String protocol,
    int version,
    bool cleanSession,
    bool willFlag,
    int willQos,
    bool willRetain,
    bool passwordFlag,
    bool usernameFlag,
    int keepAlive,
    String clientId,
    String? willTopic,
    Uint8List? willMessage,
    String? username,
    String? password
  }) parseConnectPacket(Uint8List data) {
    var offset = 2; // Skip fixed header and remaining length

    // Protocol name
    final protocolNameLength = ((data[offset] << 8) | data[offset + 1]);
    offset += 2;
    final protocol = utf8.decode(data.sublist(offset, offset + protocolNameLength));
    offset += protocolNameLength;

    // Protocol version
    final version = data[offset++];

    // Connect flags
    final connectFlags = data[offset++];
    final usernameFlag = (connectFlags & 0x80) != 0;
    final passwordFlag = (connectFlags & 0x40) != 0;
    final willRetain = (connectFlags & 0x20) != 0;
    final willQos = (connectFlags & 0x18) >> 3;
    final willFlag = (connectFlags & 0x04) != 0;
    final cleanSession = (connectFlags & 0x02) != 0;

    // Keep alive
    final keepAlive = ((data[offset] << 8) | data[offset + 1]);
    offset += 2;

    // Client ID
    final clientIdLength = ((data[offset] << 8) | data[offset + 1]);
    offset += 2;
    final clientId = utf8.decode(data.sublist(offset, offset + clientIdLength));
    offset += clientIdLength;

    // Will Topic & Message (if will flag is set)
    String? willTopic;
    Uint8List? willMessage;
    if (willFlag) {
      final willTopicLength = ((data[offset] << 8) | data[offset + 1]);
      offset += 2;
      willTopic = utf8.decode(data.sublist(offset, offset + willTopicLength));
      offset += willTopicLength;

      final willMessageLength = ((data[offset] << 8) | data[offset + 1]);
      offset += 2;
      willMessage = data.sublist(offset, offset + willMessageLength);
      offset += willMessageLength;
    }

    // Username (if username flag is set)
    String? username;
    if (usernameFlag) {
      final usernameLength = ((data[offset] << 8) | data[offset + 1]);
      offset += 2;
      username = utf8.decode(data.sublist(offset, offset + usernameLength));
      offset += usernameLength;
    }

    // Password (if password flag is set)
    String? password;
    if (passwordFlag) {
      final passwordLength = ((data[offset] << 8) | data[offset + 1]);
      offset += 2;
      password = utf8.decode(data.sublist(offset, offset + passwordLength));
    }

    return (
      protocol: protocol,
      version: version,
      cleanSession: cleanSession,
      willFlag: willFlag,
      willQos: willQos,
      willRetain: willRetain,
      passwordFlag: passwordFlag,
      usernameFlag: usernameFlag,
      keepAlive: keepAlive,
      clientId: clientId,
      willTopic: willTopic,
      willMessage: willMessage,
      username: username,
      password: password
    );
  }

  /// Parse a PUBLISH packet and return a record with the extracted values
  /// Returns (topic, payload, qos, messageId, retain, duplicate)
  static ({String topic, Uint8List payload, int qos, int? messageId, bool retain, bool duplicate}) parsePublishPacket(Uint8List data) {
    final headerByte = data[0];
    final duplicate = (headerByte & 0x08) != 0;
    final qos = (headerByte & 0x06) >> 1;
    final retain = (headerByte & 0x01) != 0;

    var offset = 2; // Skip fixed header and assuming 1 byte for remaining length for simplicity

    // Extract topic length and topic
    final topicLength = ((data[offset] << 8) | data[offset + 1]);
    offset += 2;
    final topic = utf8.decode(data.sublist(offset, offset + topicLength));
    offset += topicLength;

    // Extract message ID if QoS > 0
    int? messageId;
    if (qos > 0) {
      messageId = ((data[offset] << 8) | data[offset + 1]);
      offset += 2;
    }

    // Extract payload (everything after the message ID if present)
    final payload = data.sublist(offset);

    return (topic: topic, payload: payload, qos: qos, messageId: messageId, retain: retain, duplicate: duplicate);
  }

  /// Parse a SUBSCRIBE packet and return a record with the extracted values
  /// Returns (messageId, subscriptions) where subscriptions is a list of (topic, qos) records
  static ({int messageId, List<({String topic, int qos})> subscriptions}) parseSubscribePacket(Uint8List data) {
    var offset = 2; // Skip fixed header and remaining length

    // Extract message ID
    final messageId = ((data[offset] << 8) | data[offset + 1]);
    offset += 2;

    // Extract subscriptions
    final subscriptions = <({String topic, int qos})>[];
    while (offset < data.length) {
      // Extract topic length and topic
      final topicLength = ((data[offset] << 8) | data[offset + 1]);
      offset += 2;
      final topic = utf8.decode(data.sublist(offset, offset + topicLength));
      offset += topicLength;

      // Extract QoS
      final qos = data[offset++] & 0x03;

      subscriptions.add((topic: topic, qos: qos));
    }

    return (messageId: messageId, subscriptions: subscriptions);
  }

  /// Parse an UNSUBSCRIBE packet and return a record with the extracted values
  /// Returns (messageId, topics)
  static ({int messageId, List<String> topics}) parseUnsubscribePacket(Uint8List data) {
    var offset = 2; // Skip fixed header and remaining length

    // Extract message ID
    final messageId = ((data[offset] << 8) | data[offset + 1]);
    offset += 2;

    // Extract topics
    final topics = <String>[];
    while (offset < data.length) {
      // Extract topic length and topic
      final topicLength = ((data[offset] << 8) | data[offset + 1]);
      offset += 2;
      final topic = utf8.decode(data.sublist(offset, offset + topicLength));
      offset += topicLength;

      topics.add(topic);
    }

    return (messageId: messageId, topics: topics);
  }

  /// Parse a PUBACK, PUBREC, PUBREL, PUBCOMP, or UNSUBACK packet and return the message ID
  static int parseMessageIdPacket(Uint8List data) {
    return ((data[2] << 8) | data[3]);
  }

  /// Parse a CONNACK packet and return a record with the extracted values
  /// Returns (sessionPresent, returnCode)
  static ({bool sessionPresent, int returnCode}) parseConnackPacket(Uint8List data) {
    final sessionPresent = (data[2] & 0x01) != 0;
    final returnCode = data[3];

    return (sessionPresent: sessionPresent, returnCode: returnCode);
  }

  /// Parse a SUBACK packet and return a record with the extracted values
  /// Returns (messageId, grantedQos)
  static ({int messageId, List<int> grantedQos}) parseSubackPacket(Uint8List data) {
    final messageId = ((data[2] << 8) | data[3]);
    final grantedQos = data.sublist(4);

    return (messageId: messageId, grantedQos: grantedQos.toList());
  }

  /// Parse the remaining length field of an MQTT packet
  /// Returns (value, bytesRead)
  static ({int value, int bytesRead}) parseRemainingLength(Uint8List data, int startIndex) {
    int multiplier = 1;
    int value = 0;
    int bytesRead = 0;
    int encodedByte;

    do {
      if (startIndex + bytesRead >= data.length) {
        throw Exception('Malformed remaining length');
      }

      encodedByte = data[startIndex + bytesRead];
      value += (encodedByte & 127) * multiplier;
      multiplier *= 128;
      bytesRead++;

      if (multiplier > 128 * 128 * 128) {
        throw Exception('Malformed remaining length');
      }
    } while ((encodedByte & 128) != 0);

    return (value: value, bytesRead: bytesRead);
  }
}
