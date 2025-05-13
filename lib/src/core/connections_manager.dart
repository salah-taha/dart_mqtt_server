import 'dart:async';
import 'package:mqtt_server/src/models/mqtt_connection.dart';
import 'package:mqtt_server/src/models/mqtt_session.dart';

/// Manages MQTT client connections and sessions
class ConnectionsManager {
  // Connection and session management
  final Map<String, MqttConnection> _connections = {};
  final Map<String, MqttSession> _sessions = {};

  // Subscription management
  final Map<String, Set<String>> _topicSubscriptions = {}; // topic -> Set<clientId>
  final Map<String, Map<String, int>> _clientSubscriptions = {}; // clientId -> Map<topic, qos>

  MqttConnection? getConnection(String? clientId) {
    if (clientId == null) return null;
    return _connections[clientId];
  }

  /// Register a new connection
  void registerConnection(MqttConnection connection, String clientId) {
    _connections[clientId] = connection;
  }

  /// Get or create a session for a client
  MqttSession getOrCreateSession(String clientId, bool cleanSession) {
    if (_sessions.containsKey(clientId) && !cleanSession) {
      return _sessions[clientId]!;
    }

    final session = MqttSession(clientId, cleanSession);
    _sessions[clientId] = session;
    return session;
  }

  /// Get a session for a client
  MqttSession? getSession(String? clientId) {
    if (clientId == null) return null;
    return _sessions[clientId];
  }

  /// Remove a session
  void removeSession(String clientId) {
    _sessions.remove(clientId);
  }

  /// Add a session
  void addSession(String clientId, MqttSession session) {
    _sessions[clientId] = session;
  }

  /// Disconnect a client
  Future<void> disconnectClient(String clientId, {bool clearSession = true}) async {
    final connection = _connections[clientId];
    if (connection != null) {
      await connection.close();
      _connections.remove(clientId);
    }
    if (clearSession) {
      removeSession(clientId);
    }
  }

  /// Check if a client is connected
  bool isClientConnected(String clientId) {
    final connection = _connections[clientId];
    return connection != null && connection.isConnected;
  }

  /// Get total number of active connections
  int get activeConnections => _connections.length;

  /// Get total number of active sessions
  int get activeSessions => _sessions.length;

  /// Clean up resources
  /// Subscribe a client to a topic with specified QoS
  void subscribe(String clientId, String topic, int qos) {
    // Add to topic subscriptions
    _topicSubscriptions.putIfAbsent(topic, () => {}).add(clientId);

    // Add to client subscriptions
    _clientSubscriptions.putIfAbsent(clientId, () => {}).putIfAbsent(topic, () => qos);

  }

  /// Unsubscribe a client from a topic
  void unsubscribe(String clientId, String topic) {
    // Remove from topic subscriptions
    _topicSubscriptions[topic]?.remove(clientId);
    if (_topicSubscriptions[topic]?.isEmpty ?? false) {
      _topicSubscriptions.remove(topic);
    }

    // Remove from client subscriptions
    _clientSubscriptions[clientId]?.remove(topic);
    if (_clientSubscriptions[clientId]?.isEmpty ?? false) {
      _clientSubscriptions.remove(clientId);
    }

  }

  /// Get subscribers for a topic
  Set<String> getSubscribers(String topic) {
    var subscribers = <String>{};

    // Add exact match subscribers
    if (_topicSubscriptions.containsKey(topic)) {
      subscribers.addAll(_topicSubscriptions[topic]!);
    }

    // Add wildcard subscribers
    _topicSubscriptions.forEach((subscribedTopic, clientIds) {
      if (_isTopicMatch(subscribedTopic, topic)) {
        subscribers.addAll(clientIds);
      }
    });

    return subscribers;
  }

  /// Get QoS level for a client's subscription to a topic
  int? getSubscriptionQos(String clientId, String topic) {
    return _clientSubscriptions[clientId]?[topic];
  }

  /// Clean up client subscriptions
  void cleanupClientSubscriptions(String clientId) {
    // Remove from client subscriptions
    final topics = _clientSubscriptions.remove(clientId)?.keys.toList() ?? [];

    // Remove from topic subscriptions
    for (final topic in topics) {
      _topicSubscriptions[topic]?.remove(clientId);
      if (_topicSubscriptions[topic]?.isEmpty ?? false) {
        _topicSubscriptions.remove(topic);
      }
    }
  }

  bool _isTopicMatch(String subscribedTopic, String publishedTopic) {
    final subParts = subscribedTopic.split('/');
    final pubParts = publishedTopic.split('/');

    if (subParts.length > pubParts.length && subParts.last != '#') {
      return false;
    }

    for (var i = 0; i < subParts.length; i++) {
      if (subParts[i] == '#') {
        return true;
      }
      if (subParts[i] != '+' && subParts[i] != pubParts[i]) {
        return false;
      }
    }

    return subParts.length == pubParts.length;
  }

  Future<void> dispose() async {
    for (var clientId in _connections.keys.toList()) {
      await disconnectClient(clientId);
    }
  }

 
}
