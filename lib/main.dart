import 'dart:developer';
import 'dart:io';
import 'package:mqtt_server/mqtt_server.dart';

void main() async {
  final config = MqttBrokerConfig(
    port: 12343,
    useSSL: false,
    allowAnonymous: true,
    sessionExpiryInterval: Duration(hours: 24),
    messageExpiryInterval: Duration(hours: 1),
  );

  final broker = MqttBroker(config);

  try {
    await broker.start();

    // Add users if authentication is enabled
    if (config.authenticationRequired) {
      broker.addCredentials('admin', 'secure_password');
      broker.addCredentials('user1', 'password123');
    }

    log('Broker is running. Press Ctrl+C to stop.');

    // Handle shutdown gracefully
    ProcessSignal.sigint.watch().listen((_) async {
      log('\nShutting down broker...');
      await broker.stop();
      exit(0);
    });
  } catch (e) {
    log('Failed to start broker: $e');
    exit(1);
  }
}
