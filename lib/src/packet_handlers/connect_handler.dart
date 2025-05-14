import 'dart:math';
import 'dart:typed_data';

import 'package:mqtt_server/src/core/packet_generator.dart';
import 'package:mqtt_server/src/core/packet_handler_base.dart';
import 'package:mqtt_server/src/core/mqtt_packet_parser.dart';
import 'package:mqtt_server/src/models/mqtt_connection.dart';
import 'package:mqtt_server/src/models/mqtt_message.dart';
import 'package:mqtt_server/src/mqtt_broker.dart';

class ConnectHandler extends PacketHandlerBase {
  final MqttBroker _broker;
  ConnectHandler(this._broker);

  @override
  Future<void> handle(Uint8List data, MqttConnection connection) async {
    try {
      // Validate minimum packet length
      if (data.length < 12) {
        await _sendConnack(connection, 0x01); // Unacceptable protocol version
        return;
      }

      // Use MqttPacketParser to parse the CONNECT packet
      final connectData = MqttPacketParser.parseConnectPacket(data);

      // Validate protocol name and version
      if (connectData.protocol != 'MQTT' || connectData.version != 0x04) {
        await _sendConnack(connection, 0x01); // Unacceptable protocol version
        return;
      }

      // Extract connect flags
      final cleanSession = connectData.cleanSession;
      final willFlag = connectData.willFlag;
      final willQoS = connectData.willQos;

      // Validate QoS level for will message
      if (willFlag && willQoS > 2) {
        await _sendConnack(connection, 0x01);
        return;
      }

      // Handle client ID
      String clientId = connectData.clientId;

      // If client ID is empty and clean session is false, reject
      if (clientId.isEmpty && !cleanSession) {
        await _sendConnack(connection, 0x02); // Identifier rejected
        return;
      }

      // Generate client ID if empty
      if (clientId.isEmpty) {
        clientId = _generateClientId();
      }

      // Handle authentication
      String? username = connectData.username;
      String? password = connectData.password;

      if (!_broker.config.allowAnonymous) {
        if (!_broker.authenticate(username, password)) {
          await _sendConnack(connection, 0x05); // Not authorized
          return;
        }
      }

      String? willTopic = connectData.willTopic;
      Uint8List? willMessage = connectData.willMessage;

      MqttMessage? willMessageObj;

      if (willMessage != null) {
        willMessageObj = MqttMessage(willMessage, 0, true, DateTime.now());
      }

      // Create session and associate with connection
      _broker.connectionsManager.createSession(clientId, cleanSession, willTopic, willMessageObj);
      connection.clientId = clientId;

      // Send CONNACK
      connection.isConnected = true;
      await _sendConnack(connection, 0x00);

      _broker.connectionsManager.registerConnection(connection, clientId);

      // Process any stored messages for this client
      _broker.messageManager.processQueuedMessages(clientId);
    } catch (e) {
      await _sendConnack(connection, 0x04);
    }
  }

  Future<void> _sendConnack(MqttConnection connection, int returnCode) async {
    final connack = PacketGenerator.connectackPacket(returnCode);
    await connection.send(connack);
  }

  String _generateClientId() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return String.fromCharCodes(
      Iterable.generate(
        23,
        (_) => chars.codeUnitAt(random.nextInt(chars.length)),
      ),
    );
  }
}
