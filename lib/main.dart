// Example usage
import 'dart:io';

import 'package:mqtt_server/mqtt_server.dart';
import 'package:mqtt_server/src/mqtt_broker_config.dart';

void main() async {
  final config = MqttBrokerConfig(
    port: 18561,
    useSsl: false,
    authenticationRequired: false,
    maxRetryAttempts: 3,
    retryDelay: Duration(seconds: 5),
    sessionExpiryInterval: Duration(hours: 24),
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
      broker.addUser('admin', 'secure_password');
      broker.addUser('user1', 'password123');
    }

    print('Broker is running. Press Ctrl+C to stop.');

    // Handle shutdown gracefully
    ProcessSignal.sigint.watch().listen((_) async {
      print('\nShutting down broker...');
      await broker.stop();
      exit(0);
    });
  } catch (e) {
    print('Failed to start broker: $e');
    exit(1);
  }
}
