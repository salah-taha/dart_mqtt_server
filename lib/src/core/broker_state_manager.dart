import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:mqtt_server/src/models/mqtt_connection.dart';
import 'package:mqtt_server/src/models/mqtt_credentials.dart';
import 'package:mqtt_server/src/models/mqtt_message.dart';
import 'package:mqtt_server/src/models/mqtt_session.dart';
import 'package:mqtt_server/src/mqtt_broker.dart';
import 'connections_manager.dart';

/// Manages the state of the MQTT broker, including connections, sessions, and subscriptions.
/// This class centralizes all state management to make it easier to maintain and extend.
class BrokerStateManager {
  final MqttBroker _broker;

  BrokerStateManager(this._broker);

  final ConnectionsManager _connectionsManager = ConnectionsManager();

  final Map<String, MqttMessage> _retainedMessages = {};

  // Message tracking
  final Map<String, Map<int, MqttMessage>> _inFlightMessages = {}; // clientId -> Map<messageId, message>
  final Map<String, List<MqttMessage>> _queuedMessages = {}; // clientId -> List<message>

  // Authentication
  final Map<String, MqttCredentials> _credentials = {};

  // Event streams for monitoring
  final _connectionEventController = StreamController<ConnectionEvent>.broadcast();
  Stream<ConnectionEvent> get connectionEvents => _connectionEventController.stream;

  // Getters for state access
  Map<String, MqttSession> get sessions => _connectionsManager.sessions;

  Map<String, Set<String>> get topicSubscriptions => _connectionsManager.topicSubscriptions;

  Map<String, Map<String, int>> get clientSubscriptions => _connectionsManager.clientSubscriptions;

  Map<String, MqttMessage> get retainedMessages => _retainedMessages;

  Map<String, Map<int, MqttMessage>> get inFlightMessages => _inFlightMessages;

  Map<String, MqttConnection> get clientConnections => _connectionsManager.connections;

  Map<String, MqttCredentials> get credentials => _credentials;

  bool get allowAnonymousConnections => _broker.config.allowAnonymous;

  void processQueuedMessages(String clientId) {
    if (!_queuedMessages.containsKey(clientId)) return;
    if (!_connectionsManager.connections.containsKey(clientId)) return;

    final connection = _connectionsManager.connections[clientId]!;
    final session = _connectionsManager.sessions[clientId];
    if (session == null) return;

    final messages = _queuedMessages[clientId]!;
    final remainingMessages = <MqttMessage>[];

    for (var message in messages) {
      try {
        // For clean session, send all messages
        // For non-clean session, only send QoS 1 and 2 messages
        if (session.cleanSession || message.qos > 0) {
          connection.send(message.payload);

          // If QoS > 0, track the message as in-flight
          if (message.qos > 0) {
            _inFlightMessages.putIfAbsent(clientId, () => <int, MqttMessage>{}).putIfAbsent(messages.indexOf(message), () => message);
          }
        } else {
          // Keep QoS 0 messages in queue for non-clean sessions
          remainingMessages.add(message);
        }
      } catch (e) {
        developer.log('Error sending queued message to client $clientId: $e');
        // If there's an error, keep remaining messages in queue and stop processing
        remainingMessages.addAll(messages.sublist(messages.indexOf(message)));
        _queuedMessages[clientId] = remainingMessages;
        return;
      }
    }

    // Update or clear the queue
    if (remainingMessages.isEmpty) {
      _queuedMessages.remove(clientId);
    } else {
      _queuedMessages[clientId] = remainingMessages;
    }
  }

  /// Registers a new connection with the broker
  void registerConnection(MqttConnection connection, String clientId) {
    _connectionsManager.registerConnection(connection, clientId);
  }

  /// Creates or retrieves a session for a client
  MqttSession getOrCreateSession(String clientId, bool cleanSession) {
    return _connectionsManager.getOrCreateSession(clientId, cleanSession);
  }

  MqttSession? getSession(String? clientId) {
    return _connectionsManager.getSession(clientId);
  }

  /// Subscribes a client to a topic with specified QoS
  void subscribe(String clientId, String topic, int qos) {
    _connectionsManager.subscribe(clientId, topic, qos);
  }

  /// Unsubscribes a client from a topic
  void unsubscribe(String clientId, String topic) {
    _connectionsManager.unsubscribe(clientId, topic);
  }

  Future<void> disconnectClient(String clientId) async {
    final session = _connectionsManager.getSession(clientId);
    await _connectionsManager.disconnectClient(clientId);

    // Clean up session if not persistent
    if (session != null && session.cleanSession) {
      _connectionsManager.removeSession(clientId);
      clientSubscriptions.remove(clientId);

      // Clean up in-flight messages
      _inFlightMessages.remove(clientId);
      _queuedMessages.remove(clientId);
    }

    developer.log('Client disconnected: $clientId');
  }

  /// Publishes a message to all subscribers of a topic
  void publishToSubscribers(String topic, Uint8List payload, int qos, bool retain) {
    // Store retained message if needed
    if (retain) {
      if (payload.isEmpty) {
        // Empty payload means delete retained message
        _retainedMessages.remove(topic);
      } else {
        // Store the retained message
        _retainedMessages[topic] = MqttMessage(payload, qos, retain, DateTime.now());
      }
    }

    // Find matching subscribers
    final matchingTopics = _findMatchingTopics(topic);
    final subscribers = <String>{};

    for (final matchingTopic in matchingTopics) {
      if (topicSubscriptions.containsKey(matchingTopic)) {
        subscribers.addAll(topicSubscriptions[matchingTopic]!);
      }
    }

    // Deliver message to each subscriber
    for (final clientId in subscribers) {
      if (clientConnections.containsKey(clientId)) {
        final subscriberQos = clientSubscriptions[clientId]?[topic] ?? 0;
        final effectiveQos = qos < subscriberQos ? qos : subscriberQos;

        // For QoS 0, deliver immediately
        if (effectiveQos == 0) {
          _deliverMessage(clientId, topic, payload, effectiveQos, false);
        } else {
          // For QoS 1 and 2, add to in-flight messages
          _addToInFlightMessages(clientId, topic, payload, effectiveQos);
        }
      } else if (sessions.containsKey(clientId) && !sessions[clientId]!.cleanSession) {
        // Queue message for offline client with persistent session
        _queueMessage(clientId, topic, payload, qos);
      }
    }
  }

  /// Delivers a message to a client
  void _deliverMessage(String clientId, String topic, Uint8List payload, int qos, bool isDuplicate) {
    final connection = clientConnections[clientId];
    if (connection == null) return;

    // TODO: Implement actual message delivery logic
    developer.log('Delivering message to $clientId on topic $topic with QoS $qos');
  }

  /// Adds a message to the in-flight messages for a client and handles QoS
  void _addToInFlightMessages(String clientId, String topic, Uint8List payload, int qos) {
    if (!sessions.containsKey(clientId)) return;

    final session = sessions[clientId]!;
    final messageId = session.getNextMessageId();
    final message = MqttMessage(payload, qos, false, DateTime.now());

    // Store message in in-flight messages map
    _inFlightMessages.putIfAbsent(clientId, () => <int, MqttMessage>{});
    _inFlightMessages[clientId]![messageId] = message;

    // Handle QoS levels
    switch (qos) {
      case 0: // At most once delivery (fire and forget)
        // No acknowledgment needed, message is sent and forgotten
        break;

      case 1: // At least once delivery
        // Store message for potential retransmission
        // Will be removed when PUBACK is received
        developer.log('QoS 1 message stored for $clientId with ID $messageId');
        break;

      case 2: // Exactly once delivery
        // Store message for 4-way handshake
        // Will be removed after complete handshake (PUBREL/PUBCOMP)
        developer.log('QoS 2 message stored for $clientId with ID $messageId');
        break;
    }
  }

  /// Queues a message for an offline client with delivery guarantees
  void _queueMessage(String clientId, String topic, Uint8List payload, int qos) {
    _queuedMessages.putIfAbsent(clientId, () => <MqttMessage>[]);
    final message = MqttMessage(payload, qos, false, DateTime.now());
    _queuedMessages[clientId]!.add(message);

    // Log message queueing based on QoS level
    switch (qos) {
      case 0:
        // QoS 0 messages might be lost if client is offline
        developer.log('QoS 0 message queued for offline client $clientId (best effort)');
        break;
      case 1:
      case 2:
        // QoS 1 and 2 messages are guaranteed to be delivered
        developer.log('QoS $qos message queued for offline client $clientId with delivery guarantee');
        break;
    }

    // Limit queue size to prevent memory issues
    final maxQueueSize = _broker.config.maxQueueSize;
    if (_queuedMessages[clientId]!.length > maxQueueSize) {
      // Remove oldest messages when queue is full, but preserve QoS 1 and 2 messages
      _queuedMessages[clientId]!.removeWhere((msg) => msg.qos == 0);
      if (_queuedMessages[clientId]!.length > maxQueueSize) {
        // If still over limit, remove oldest messages regardless of QoS
        _queuedMessages[clientId]!.removeRange(0, _queuedMessages[clientId]!.length - maxQueueSize);
      }
      developer.log('Queue size limited for client $clientId');
    }

    developer.log('Queued message for offline client $clientId');
  }

  /// Finds topics that match the given topic (including wildcards)
  Set<String> _findMatchingTopics(String topic) {
    final result = <String>[];

    // Exact match
    if (topicSubscriptions.containsKey(topic)) {
      result.add(topic);
    }

    // Handle wildcards
    final topicLevels = topic.split('/');

    for (final subscription in topicSubscriptions.keys) {
      if (_topicMatches(topicLevels, subscription.split('/'))) {
        result.add(subscription);
      }
    }

    return result.toSet();
  }

  /// Checks if a topic matches a subscription (handling wildcards)
  bool _topicMatches(List<String> topicLevels, List<String> subscriptionLevels) {
    if (subscriptionLevels.length == 1 && subscriptionLevels[0] == '#') {
      return true; // Multi-level wildcard matches everything
    }

    if (topicLevels.length < subscriptionLevels.length) {
      // Check if the last level is a multi-level wildcard
      return subscriptionLevels.isNotEmpty &&
          subscriptionLevels.last == '#' &&
          _levelsMatch(topicLevels, subscriptionLevels.sublist(0, subscriptionLevels.length - 1));
    }

    if (topicLevels.length > subscriptionLevels.length) {
      // Only match if the last subscription level is a multi-level wildcard
      return subscriptionLevels.isNotEmpty && subscriptionLevels.last == '#';
    }

    // Same length, check each level
    return _levelsMatch(topicLevels, subscriptionLevels);
  }

  /// Checks if topic levels match subscription levels
  bool _levelsMatch(List<String> topicLevels, List<String> subscriptionLevels) {
    if (topicLevels.length != subscriptionLevels.length) return false;

    for (var i = 0; i < topicLevels.length; i++) {
      if (subscriptionLevels[i] != '+' && subscriptionLevels[i] != topicLevels[i]) {
        return false;
      }
    }

    return true;
  }

  /// Adds a user credential to the broker
  void addUser(String username, String password) {
    _credentials[username] = MqttCredentials(username, password);
  }

  /// Authenticates a user
  bool authenticate(String? username, String? password) {
    if (_broker.config.allowAnonymous) return true;
    if (username == null || password == null) return false;

    final credential = _credentials[username];
    if (credential == null) return false;

    return credential.password == password;
  }

  /// Performs maintenance tasks like cleaning up expired sessions
  void performMaintenance() {
    final now = DateTime.now();

    // Clean up expired sessions
    final expiredSessions = <String>[];
    sessions.forEach((clientId, session) {
      if (now.difference(session.lastActivity) > _broker.config.sessionExpiryInterval) {
        expiredSessions.add(clientId);
      }
    });

    for (final clientId in expiredSessions) {
      if (clientConnections.containsKey(clientId)) {
        disconnectClient(clientId);
      } else {
        sessions.remove(clientId);
        clientSubscriptions.remove(clientId);
        _inFlightMessages.remove(clientId);
        _queuedMessages.remove(clientId);
      }
    }

    // Clean up expired in-flight messages
    _inFlightMessages.forEach((clientId, messages) {
      final expiredMessageIds = <int>[];
      messages.forEach((messageId, message) {
        if (now.difference(message.timestamp) > _broker.config.messageExpiryInterval) {
          expiredMessageIds.add(messageId);
        }
      });

      for (final messageId in expiredMessageIds) {
        messages.remove(messageId);
      }
    });
  }

  /// Saves persistent sessions to disk
  Future<void> savePersistentSessions() async {
    try {
      if (!_broker.config.enablePersistence) return;

      final file = File(_broker.config.persistencePath);
      final persistentSessions = <String, Map<String, dynamic>>{};

      // Only save persistent sessions
      sessions.forEach((clientId, session) {
        if (!session.cleanSession) {
          persistentSessions[clientId] = session.toPersistentData();

          // Add subscriptions
          if (clientSubscriptions.containsKey(clientId)) {
            persistentSessions[clientId]!['subscriptions'] = clientSubscriptions[clientId];
          }

          // Add queued messages
          if (_queuedMessages.containsKey(clientId)) {
            persistentSessions[clientId]!['queuedMessages'] = _queuedMessages[clientId]!.map((msg) => msg.toPersistentData()).toList();
          }
        }
      });

      final data = jsonEncode(persistentSessions);
      await file.writeAsString(data);

      developer.log('Saved ${persistentSessions.length} persistent sessions');
    } catch (e) {
      developer.log('Error saving persistent sessions: $e');
    }
  }

  /// Loads persistent sessions from disk
  Future<void> loadPersistentSessions() async {
    try {
      if (!_broker.config.enablePersistence) return;

      final file = File(_broker.config.persistencePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;

        data.forEach((clientId, sessionData) {
          // Create session
          final session = MqttSession.fromPersistentData(sessionData as Map<String, dynamic>);
          sessions[clientId] = session;

          // Restore subscriptions
          if (sessionData.containsKey('subscriptions')) {
            final subscriptions = sessionData['subscriptions'] as Map<String, dynamic>;
            clientSubscriptions[clientId] = Map<String, int>.from(subscriptions.map((topic, qos) => MapEntry(topic, qos as int)));

            // Add to topic subscriptions
            clientSubscriptions[clientId]!.forEach((topic, qos) {
              topicSubscriptions.putIfAbsent(topic, () => <String>{}).add(clientId);
            });
          }

          // Restore queued messages
          if (sessionData.containsKey('queuedMessages')) {
            final messages = sessionData['queuedMessages'] as List<dynamic>;
            _queuedMessages[clientId] = messages.map((msg) => MqttMessage.fromPersistentData(msg as Map<String, dynamic>)).toList();
          }
        });

        developer.log('Loaded ${sessions.length} persistent sessions');
      }
    } catch (e) {
      developer.log('Error loading persistent sessions: $e');
    }
  }

  /// Cleans up resources when the broker is shutting down
  Future<void> dispose() async {
    // Disconnect all clients
    final clientIds = List<String>.from(clientConnections.keys);
    for (final clientId in clientIds) {
      disconnectClient(clientId);
    }

    // Save persistent sessions
    await savePersistentSessions();

    // Close event controllers
    await _connectionEventController.close();

    developer.log('Broker state manager disposed');
  }

  // HandlerDependencies interface implementation
  void removeSession(String clientId) {
    _connectionsManager.removeSession(clientId);
  }

  void addSession(String clientId, MqttSession session) {
    _connectionsManager.addSession(clientId, session);
  }

  Map<String, MqttCredentials> getCredentials() {
    return _credentials;
  }

  void queueMessage(String clientId, String topic, List<int> payload, int qos) {
    _queueMessage(clientId, topic, Uint8List.fromList(payload), qos);
  }
}

/// Represents a connection event type
enum ConnectionEventType {
  connected,
  disconnected,
  authenticated,
  authenticationFailed,
}

/// Represents a connection event
class ConnectionEvent {
  final String clientId;
  final ConnectionEventType type;
  final DateTime timestamp;

  ConnectionEvent({
    required this.clientId,
    required this.type,
    required this.timestamp,
  });
}
