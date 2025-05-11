class MqttBrokerConfig {
  /// The port number for the MQTT broker to listen on
  final int port;

  /// The host address for the MQTT broker to bind to
  final String host;

  /// Whether to enable SSL/TLS for secure connections
  final bool useSSL;

  /// Path to the SSL certificate file (required if useSSL is true)
  final String? sslCertPath;

  /// Path to the SSL private key file (required if useSSL is true)
  final String? sslKeyPath;

  /// Maximum number of retry attempts for QoS messages
  final int maxQosRetries;

  /// Timeout in seconds for QoS messages before they are considered failed
  final int qosMessageTimeout;

  /// Maximum number of in-flight messages per client
  final int maxInflightMessages;

  /// Whether to allow anonymous connections
  final bool allowAnonymous;

  /// Maximum number of concurrent connections
  final int maxConnections;

  /// Session expiry interval
  final Duration sessionExpiryInterval;

  /// Message expiry interval
  final Duration messageExpiryInterval;

  /// Maximum queue size per client
  final int maxQueueSize;

  /// Whether to enable metrics tracking
  final bool enableMetrics;

  /// Maximum number of connections per client
  final int maxConnectionsPerClient;

  /// Keep alive timeout
  final Duration keepAliveTimeout;

  /// Whether to enable persistence
  final bool enablePersistence;

  /// Whether authentication is required
  final bool authenticationRequired;

  /// Maximum retry attempts for operations
  final int maxRetryAttempts;

  /// Path to the persistence file
  final String persistencePath;

  /// Retry delay for QoS messages
  final Duration retryDelay;

  // Private key path
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
