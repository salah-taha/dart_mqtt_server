# MQTT Server

A lightweight, efficient MQTT broker implementation in pure Dart. This package provides a full-featured MQTT server that can be embedded in your Dart applications or run as a standalone broker.

[![Dart Version](https://img.shields.io/badge/Dart-3.0.0+-00B4AB.svg)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Features

- **MQTT 3.1.1 Protocol Support**: Implements the MQTT 3.1.1 protocol specification
- **QoS Levels**: Supports QoS 0, 1, and 2 message delivery
- **Session Persistence**: Optional persistent sessions across client reconnects
- **Authentication**: Built-in username/password authentication system
- **SSL/TLS Support**: Secure connections with SSL/TLS
- **Will Messages**: Support for last will and testament messages
- **Retained Messages**: Store and forward retained messages to new subscribers
- **Topic Wildcards**: Support for + and # wildcards in topic subscriptions
- **Clean Architecture**: Modular design with clear separation of concerns

## Getting Started

### Installation

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  mqtt_server: ^1.0.0
```

Then run:

```bash
dart pub get
```

### Prerequisites

- Dart SDK 3.0.0 or higher

## Usage

### Basic Broker Setup

```dart
import 'package:mqtt_server/mqtt_server.dart';

Future<void> main() async {
  // Create a broker with default configuration
  final broker = MqttBroker();
  
  // Start the broker
  await broker.start();
  
  print('MQTT broker running on port 1883');
}
```

### Custom Configuration

```dart
import 'package:mqtt_server/mqtt_server.dart';

Future<void> main() async {
  // Create a broker with custom configuration
  final config = MqttBrokerConfig(
    port: 8883,
    useSSL: true,
    sslCertPath: 'path/to/certificate.pem',
    sslKeyPath: 'path/to/key.pem',
    allowAnonymous: false,
    enablePersistence: true,
    persistencePath: 'mqtt_data/sessions.json',
    sessionExpiryInterval: Duration(days: 1),
  );
  
  final broker = MqttBroker(config);
  
  // Add user credentials
  broker.addCredentials('username', 'password');
  
  // Start the broker
  await broker.start();
  
  print('Secure MQTT broker running on port 8883');
}
```

## Advanced Usage

### Session Persistence

The broker can automatically persist sessions to disk and restore them on restart:

```dart
final config = MqttBrokerConfig(
  enablePersistence: true,
  persistencePath: 'data/sessions.json',
);

final broker = MqttBroker(config);

// Sessions will be saved periodically and on clean shutdown
await broker.start();

// To manually trigger session persistence
await broker.savePersistentSessions();
```

## API Reference

For detailed API documentation, see the [API reference](https://pub.dev/documentation/mqtt_server/latest/).

## Examples

Check the `/example` directory for more comprehensive examples:

- Basic broker setup
- Secure broker with SSL/TLS
- Authentication examples
- Custom packet handling

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- MQTT Protocol Specification: [MQTT.org](https://mqtt.org/)
- Inspired by other MQTT implementations like Mosquitto and HiveMQ
