class BrokerMetrics {
  int totalConnections = 0;
  int activeConnections = 0;
  int messagesPublished = 0;
  int messagesFailed = 0;
  Map<String, int> topicStats = {};
  Map<String, int> clientStats = {};
  Map<String, int> failedStats = {};
  DateTime startTime = DateTime.now();

  void recordPublish(String topic, String clientId) {
    messagesPublished++;
    topicStats[topic] = (topicStats[topic] ?? 0) + 1;
    clientStats[clientId] = (clientStats[clientId] ?? 0) + 1;
  }

  void recordFailedPublish(String topic, String clientId) {
    messagesFailed++;
    failedStats[topic] = (failedStats[topic] ?? 0) + 1;
  }

  Map<String, dynamic> getMetricsSnapshot() {
    return {
      'uptime': DateTime.now().difference(startTime).inSeconds,
      'total_connections': totalConnections,
      'active_connections': activeConnections,
      'messages_published': messagesPublished,
      'messages_failed': messagesFailed,
      'topic_stats': topicStats,
      'client_stats': clientStats,
      'failed_stats': failedStats,
    };
  }
}
