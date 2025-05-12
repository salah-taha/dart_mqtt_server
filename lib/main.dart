import 'dart:developer';
import 'dart:io';
import 'package:mqtt_server/mqtt_server.dart';

void main() async {
  final config = MqttBrokerConfig(
    port: 12343,
    useSSL: false,
    allowAnonymous: true,
    maxQosRetries: 3,
    retryDelay: Duration(seconds: 5),
    sessionExpiryInterval: Duration(hours: 24),
    messageExpiryInterval: Duration(hours: 1),
    maxQueueSize: 1000,
    enableMetrics: true,
    maxConnectionsPerClient: 5,
    keepAliveTimeout: Duration(seconds: 60),
  );

  final broker = MqttBroker(config);

  try {
    await broker.start();

    // Add users if authentication is enabled
    if (config.authenticationRequired) {
      broker.stateManager.addUser('admin', 'secure_password');
      broker.stateManager.addUser('user1', 'password123');
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
