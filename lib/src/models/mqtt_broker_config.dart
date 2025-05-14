class MqttBrokerConfig {
  final int port;
  final bool useSSL;
  final String? sslCertPath;
  final String? sslKeyPath;
  final bool allowAnonymous;
  final Duration sessionExpiryInterval;
  final Duration messageExpiryInterval;
  final bool enablePersistence;
  final bool authenticationRequired;
  final int maxRetryAttempts;
  final String persistencePath;

  const MqttBrokerConfig({
    this.authenticationRequired = true,
    this.maxRetryAttempts = 3,
    this.port = 1883,
    this.useSSL = false,
    this.sslCertPath,
    this.sslKeyPath,
    this.allowAnonymous = true,
    this.sessionExpiryInterval = const Duration(hours: 1),
    this.messageExpiryInterval = const Duration(minutes: 5),
    this.enablePersistence = false,
    this.persistencePath = 'mqtt_sessions.json',
  });
}
