class MqttBrokerConfig {
  final int port;
  final bool useSsl;
  final String? certificatePath;
  final String? privateKeyPath;
  final bool authenticationRequired;
  final int maxRetryAttempts;
  final Duration retryDelay;
  final Duration sessionExpiryInterval;
  final int maxQueueSize;
  final bool enableMetrics;
  final int maxConnectionsPerClient;
  final Duration keepAliveTimeout;

  MqttBrokerConfig({
    this.port = 1883,
    this.useSsl = false,
    this.certificatePath,
    this.privateKeyPath,
    this.authenticationRequired = false,
    this.maxRetryAttempts = 3,
    this.retryDelay = const Duration(seconds: 5),
    this.sessionExpiryInterval = const Duration(hours: 24),
    this.maxQueueSize = 1000,
    this.enableMetrics = true,
    this.maxConnectionsPerClient = 5,
    this.keepAliveTimeout = const Duration(seconds: 60),
  });
}
