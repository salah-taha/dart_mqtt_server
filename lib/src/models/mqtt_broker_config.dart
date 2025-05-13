class MqttBrokerConfig {
  final int port;
  final String host;
  final bool useSSL;
  final String? sslCertPath;
  final String? sslKeyPath;
  final int maxQosRetries;
  final int qosMessageTimeout;
  final int maxInflightMessages;
  final bool allowAnonymous;
  final int maxConnections;
  final Duration sessionExpiryInterval;
  final Duration messageExpiryInterval;
  final int maxQueueSize;
  final bool enableMetrics;
  final int maxConnectionsPerClient;
  final Duration keepAliveTimeout;
  final bool enablePersistence;
  final bool authenticationRequired;
  final int maxRetryAttempts;
  final String persistencePath;
  final Duration retryDelay;
  final String? privateKeyPath;

  const MqttBrokerConfig({
    this.authenticationRequired = true,
    this.maxRetryAttempts = 3,
    this.port = 1883,
    this.host = '0.0.0.0',
    this.useSSL = false,
    this.sslCertPath,
    this.sslKeyPath,
    this.maxQosRetries = 3,
    this.qosMessageTimeout = 30,
    this.maxInflightMessages = 20,
    this.allowAnonymous = true,
    this.maxConnections = 10000,
    this.sessionExpiryInterval = const Duration(hours: 1),
    this.messageExpiryInterval = const Duration(minutes: 5),
    this.maxQueueSize = 1000,
    this.enableMetrics = true,
    this.maxConnectionsPerClient = 5,
    this.keepAliveTimeout = const Duration(seconds: 60),
    this.enablePersistence = false,
    this.persistencePath = 'mqtt_sessions.json',
    this.retryDelay = const Duration(seconds: 5),
    this.privateKeyPath,
  });
}
