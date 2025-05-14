import 'dart:async';
import 'package:mqtt_server/mqtt_server.dart';
import 'package:mqtt_server/src/models/mqtt_connection.dart';
import 'package:mqtt_server/src/models/mqtt_message.dart';
import 'package:mqtt_server/src/models/mqtt_session.dart';

/// Manages MQTT client connections and sessions
class ConnectionsManager {
  final MqttBroker _broker;

  ConnectionsManager(this._broker);

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

  MqttSession? getSession(String? clientId) {
    if (clientId == null) return null;
    return _sessions[clientId];
  }

  void removeSession(String clientId) {
    _sessions.remove(clientId);
  }

  void createSession(String clientId, bool cleanSession, [String? willTopic, MqttMessage? willMessage]) {
    if (_sessions.containsKey(clientId) && !cleanSession) {
      return;
    }
    var oldSession = _sessions.remove(clientId);
    if (oldSession != null) {
      _broker.messageManager.removeClientMessages(clientId);
    }
    final session = MqttSession(clientId, cleanSession, willTopic: willTopic, willMessage: willMessage);
    _sessions[clientId] = session;
  }

  Future<void> disconnectClient(String clientId) async {
    final connection = _connections[clientId];
    if (connection != null) {
      await connection.close();
      _connections.remove(clientId);
    }
  }

  bool isClientConnected(String clientId) {
    final connection = _connections[clientId];
    return connection != null && connection.isConnected;
  }


  void subscribe(String clientId, String topic, int qos) {
    _topicSubscriptions.putIfAbsent(topic, () => {}).add(clientId);
    _clientSubscriptions.putIfAbsent(clientId, () => {}).putIfAbsent(topic, () => qos);
  }

  void unsubscribe(String clientId, String topic) {
    _topicSubscriptions[topic]?.remove(clientId);
    if (_topicSubscriptions[topic]?.isEmpty ?? false) {
      _topicSubscriptions.remove(topic);
    }

    _clientSubscriptions[clientId]?.remove(topic);
    if (_clientSubscriptions[clientId]?.isEmpty ?? false) {
      _clientSubscriptions.remove(clientId);
    }
  }

  Set<String> getSubscribers(String topic) {
    var subscribers = <String>{};

    if (_topicSubscriptions.containsKey(topic)) {
      subscribers.addAll(_topicSubscriptions[topic]!);
    }

    _topicSubscriptions.forEach((subscribedTopic, clientIds) {
      if (_isTopicMatch(subscribedTopic, topic)) {
        subscribers.addAll(clientIds);
      }
    });

    return subscribers;
  }

  int? getSubscriptionQos(String clientId, String topic) {
    return _clientSubscriptions[clientId]?[topic];
  }

  void cleanupClientSubscriptions(String clientId) {
    final topics = _clientSubscriptions.remove(clientId)?.keys.toList() ?? [];

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
  
  /// Get all client IDs that have sessions
  Set<String> getAllSessionIds() {
    return _sessions.keys.toSet();
  }

  /// Clean up expired sessions based on the provided expiry interval
  /// Returns the number of sessions that were cleaned up
  int cleanupExpiredSessions(Duration sessionExpiryInterval) {
    final now = DateTime.now();
    final expiredSessions = <String>[];

    // Check each session for expiration
    for (final clientId in _sessions.keys.toList()) {
      final session = _sessions[clientId];
      if (session == null) continue;

      // Skip if client is still connected
      if (isClientConnected(clientId)) {
        continue;
      }

      // Check if session has expired
      if (now.difference(session.lastActivity) > sessionExpiryInterval) {
        // Only remove non-clean sessions that have expired
        // Clean sessions are removed immediately on disconnect
        if (!session.cleanSession) {
          expiredSessions.add(clientId);
        }
      }
    }

    // Remove expired sessions
    for (final clientId in expiredSessions) {
      // Clean up the session
      removeSession(clientId);

      // Clean up subscriptions
      cleanupClientSubscriptions(clientId);

      // Clean up messages
      _broker.messageManager.removeClientMessages(clientId);
    }

    return expiredSessions.length;
  }
}
