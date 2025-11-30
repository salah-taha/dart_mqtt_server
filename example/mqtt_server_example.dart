import 'dart:async';
import 'dart:io';

import 'package:mqtt_server/mqtt_server.dart';

/// This example demonstrates how to set up and run an MQTT broker with various configurations.
Future<void> main() async {
  // Basic broker setup
  await runBasicBroker();
  
  // Uncomment to run other examples
  // await runSecureBroker();
  // await runPersistentBroker();
}

/// Example 1: Basic broker with default configuration
Future<void> runBasicBroker() async {
  print('Starting basic MQTT broker...');
  
  // Create a broker with default configuration
  final broker = MqttBroker();
  
  // Start the broker
  await broker.start();
  
  print('MQTT broker running on port 1883');
  print('Press Enter to stop the broker');
  await stdin.first;
  
  // Stop the broker
  await broker.stop();
  print('Basic MQTT broker stopped');
}

/// Example 2: Secure broker with SSL/TLS
Future<void> runSecureBroker() async {
  print('Starting secure MQTT broker...');
  
  // Create a broker with SSL configuration
  // Note: You need to provide valid certificate and key files
  final config = MqttBrokerConfig(
    port: 8883,
    useSSL: true,
    sslCertPath: 'path/to/certificate.pem',
    sslKeyPath: 'path/to/key.pem',
    allowAnonymous: false,
  );
  
  final broker = MqttBroker(config);
  
  // Add user credentials
  broker.addCredentials('user1', 'password1');
  broker.addCredentials('user2', 'password2');
  
  // Start the broker
  await broker.start();
  
  print('Secure MQTT broker running on port 8883');
  print('Press Enter to stop the broker');
  await stdin.first;
  
  // Stop the broker
  await broker.stop();
  print('Secure MQTT broker stopped');
}

/// Example 3: Broker with session persistence
Future<void> runPersistentBroker() async {
  print('Starting MQTT broker with persistence...');
  
  // Create a temporary directory for session data
  final tempDir = Directory('mqtt_data');
  if (!await tempDir.exists()) {
    await tempDir.create();
  }
  
  // Create a broker with persistence enabled
  final config = MqttBrokerConfig(
    port: 1883,
    enablePersistence: true,
    persistencePath: 'mqtt_data/sessions.json',
    sessionExpiryInterval: Duration(hours: 1),
  );
  
  final broker = MqttBroker(config);
  
  // Start the broker
  await broker.start();
  
  print('MQTT broker with persistence running on port 1883');
  print('Press Enter to stop the broker');
  await stdin.first;
  
  // Stop the broker - this will save sessions automatically
  await broker.stop();
  print('Persistent MQTT broker stopped');
}
