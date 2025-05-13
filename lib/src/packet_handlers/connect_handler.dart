import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:mqtt_server/src/core/packet_handler_base.dart';
import 'package:mqtt_server/src/models/mqtt_connection.dart';
import 'package:mqtt_server/src/models/mqtt_session.dart';
import 'package:mqtt_server/src/mqtt_broker.dart';


class ConnectHandler extends PacketHandlerBase {
  final MqttBroker _broker;
  ConnectHandler(this._broker);

  @override
  Future<void> handle(Uint8List data, MqttConnection connection, {int qos = 0, bool retain = false}) async {
    try {
      // Validate minimum packet length
      if (data.length < 12) {
        await _sendConnack(connection, 0x01); // Unacceptable protocol version
        return;
      }

      var pos = 2; // Skip fixed header

      // Validate protocol name
      final protocolLength = ((data[pos] << 8) | data[pos + 1]);
      pos += 2;

      if (protocolLength != 4 || pos + protocolLength > data.length) {
        await _sendConnack(connection, 0x01);
        return;
      }

      final protocolName = String.fromCharCodes(data.sublist(pos, pos + protocolLength));
      if (protocolName != 'MQTT') {
        await _sendConnack(connection, 0x01);
        return;
      }
      pos += protocolLength;

      // Validate protocol version (3.1.1 = 0x04)
      final protocolVersion = data[pos++];
      if (protocolVersion != 0x04) {
        await _sendConnack(connection, 0x01);
        return;
      }

      // Parse connect flags
      final connectFlags = data[pos++];
      final cleanSession = (connectFlags & 0x02) != 0;
      final willFlag = (connectFlags & 0x04) != 0;
      final willQoS = (connectFlags >> 3) & 0x03;
      final passwordFlag = (connectFlags & 0x40) != 0;
      final usernameFlag = (connectFlags & 0x80) != 0;

      // Validate QoS level for will message
      if (willFlag && willQoS > 2) {
        await _sendConnack(connection, 0x01);
        return;
      }

      // Read keep alive (in seconds)
      if (pos + 2 > data.length) {
        await _sendConnack(connection, 0x04);
        return;
      }
      pos += 2; // Skip keep alive

      // Extract client ID
      if (pos + 2 > data.length) {
        await _sendConnack(connection, 0x04);
        return;
      }

      final clientIdLength = ((data[pos] << 8) | data[pos + 1]);
      pos += 2;

      if (clientIdLength == 0 && !cleanSession) {
        await _sendConnack(connection, 0x02); // Identifier rejected
        return;
      }

      if (pos + clientIdLength > data.length) {
        await _sendConnack(connection, 0x04);
        return;
      }

      final clientId =
          clientIdLength > 0 ? utf8.decode(data.sublist(pos, pos + clientIdLength), allowMalformed: false) : _generateClientId();
      pos += clientIdLength;

      // Handle authentication
      String? username;
      String? password;
      if (!_broker.config.allowAnonymous) {
        if (usernameFlag) {
          if (pos + 2 > data.length) {
            await _sendConnack(connection, 0x04);
            return;
          }

          final usernameLength = ((data[pos] << 8) | data[pos + 1]);
          pos += 2;

          if (pos + usernameLength > data.length) {
            await _sendConnack(connection, 0x04);
            return;
          }

          username = utf8.decode(data.sublist(pos, pos + usernameLength));
          pos += usernameLength;
        }

        if (passwordFlag) {
          if (pos + 2 > data.length) {
            await _sendConnack(connection, 0x04);
            return;
          }

          final passwordLength = ((data[pos] << 8) | data[pos + 1]);
          pos += 2;

          if (pos + passwordLength > data.length) {
            await _sendConnack(connection, 0x04);
            return;
          }

          password = utf8.decode(data.sublist(pos, pos + passwordLength));
          pos += passwordLength;
        }

        if (!_broker.authenticate(username, password)) {
          await _sendConnack(connection, 0x05); // Not authorized
          return;
        }
      }

      // Create session and associate with connection
      final session = MqttSession(clientId, cleanSession);
      _broker.connectionsManager.addSession(clientId, session);
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
    final connack = Uint8List.fromList([0x20, 0x02, 0x00, returnCode]);
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
