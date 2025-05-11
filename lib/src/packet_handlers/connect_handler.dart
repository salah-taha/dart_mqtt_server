import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import '../mqtt_connection.dart';
import '../mqtt_broker.dart';
import '../mqtt_session.dart';
import 'packet_handler_base.dart';

class ConnectHandler extends PacketHandlerBase {
  ConnectHandler(super.deps);

  @override
  Future<void> handle(Uint8List data, MqttConnection client, {int qos = 0, bool retain = false}) async {
    try {
      // Validate minimum packet length
      if (data.length < 12) {
        await _sendConnack(client, 0x01); // Unacceptable protocol version
        return;
      }

      var pos = 2; // Skip fixed header

      // Validate protocol name
      final protocolLength = ((data[pos] << 8) | data[pos + 1]);
      pos += 2;

      if (protocolLength != 4 || pos + protocolLength > data.length) {
        await _sendConnack(client, 0x01);
        return;
      }

      final protocolName = String.fromCharCodes(data.sublist(pos, pos + protocolLength));
      if (protocolName != 'MQTT') {
        await _sendConnack(client, 0x01);
        return;
      }
      pos += protocolLength;

      // Validate protocol version (3.1.1 = 0x04)
      final protocolVersion = data[pos++];
      if (protocolVersion != 0x04) {
        await _sendConnack(client, 0x01);
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
        await _sendConnack(client, 0x01);
        return;
      }

      // Read keep alive (in seconds)
      if (pos + 2 > data.length) {
        await _sendConnack(client, 0x04);
        return;
      }
      pos += 2; // Skip keep alive

      // Extract client ID
      if (pos + 2 > data.length) {
        await _sendConnack(client, 0x04);
        return;
      }

      final clientIdLength = ((data[pos] << 8) | data[pos + 1]);
      pos += 2;

      if (clientIdLength == 0 && !cleanSession) {
        await _sendConnack(client, 0x02); // Identifier rejected
        return;
      }

      if (pos + clientIdLength > data.length) {
        await _sendConnack(client, 0x04);
        return;
      }

      final clientId =
          clientIdLength > 0 ? utf8.decode(data.sublist(pos, pos + clientIdLength), allowMalformed: false) : _generateClientId();
      pos += clientIdLength;

      // Handle authentication
      String? username;
      String? password;
      if (deps is MqttBroker && !(deps as MqttBroker).config.allowAnonymous) {
        if (usernameFlag) {
          if (pos + 2 > data.length) {
            await _sendConnack(client, 0x04);
            return;
          }

          final usernameLength = ((data[pos] << 8) | data[pos + 1]);
          pos += 2;

          if (pos + usernameLength > data.length) {
            await _sendConnack(client, 0x04);
            return;
          }

          username = utf8.decode(data.sublist(pos, pos + usernameLength));
          pos += usernameLength;
        }

        if (passwordFlag) {
          if (pos + 2 > data.length) {
            await _sendConnack(client, 0x04);
            return;
          }

          final passwordLength = ((data[pos] << 8) | data[pos + 1]);
          pos += 2;

          if (pos + passwordLength > data.length) {
            await _sendConnack(client, 0x04);
            return;
          }

          password = utf8.decode(data.sublist(pos, pos + passwordLength));
          pos += passwordLength;
        }

        if (!_authenticate(username, password)) {
          await _sendConnack(client, 0x05); // Not authorized
          return;
        }
      }

      // Create session
      final session = MqttSession(clientId, cleanSession);
      if (deps is MqttBroker) {
        (deps as MqttBroker).clientSessions[client] = session;
      }

      // Send CONNACK
      await _sendConnack(client, 0x00);

      client.isConnected = true;
    } catch (e) {
      await _sendConnack(client, 0x04);
    }
  }

  Future<void> _sendConnack(MqttConnection client, int returnCode) async {
    final connack = Uint8List.fromList([0x20, 0x02, 0x00, returnCode]);
    await client.send(connack);
  }

  bool _authenticate(String? username, String? password) {
    // TODO: Implement authentication
    if (deps is! MqttBroker) return true; // No auth for non-broker deps
    final broker = deps as MqttBroker;
    if (broker.config.allowAnonymous) return true;
    if (username == null || password == null) return false;
    final credentials = broker.credentials;
    if (!credentials.containsKey(username)) return false;
    final storedCredentials = credentials[username]!;
    return storedCredentials.hashedPassword == password; // In real impl, use proper hashing
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
