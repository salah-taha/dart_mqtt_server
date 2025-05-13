import 'dart:async';
import 'dart:developer' as developer;

import 'package:mqtt_server/mqtt_server.dart';
import 'package:mqtt_server/src/models/mqtt_credentials.dart';

/// Manages the state of the MQTT broker, including connections, sessions, and subscriptions.
/// This class centralizes all state management to make it easier to maintain and extend.
class BrokerStateManager {
  final MqttBroker _broker;

  BrokerStateManager(this._broker);


  // All message-related functionality is now handled by MessageManager

  // Authentication
  final Map<String, MqttCredentials> _credentials = {};

  Map<String, MqttCredentials> get credentials => _credentials;

  bool get allowAnonymousConnections => _broker.config.allowAnonymous;





  


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
    // final now = DateTime.now();

    // Clean up expired sessions
    // final expiredSessions = <String>[];
    //TODO: Clean up expired sessions
    // sessions.forEach((clientId, session) {
    //   if (now.difference(session.lastActivity) > _broker.config.sessionExpiryInterval) {
    //     expiredSessions.add(clientId);
    //   }
    // });

    // for (final clientId in expiredSessions) {
    //   if (clientConnections.containsKey(clientId)) {
    //     disconnectClient(clientId);
    //   } else {
    //     sessions.remove(clientId);
    //     clientSubscriptions.remove(clientId);
    //     //TODO: Clean up all messages for this client
    //     // messageManager.messageStore.remove(clientId);
    //   }
    // }

    //TODO: Clean up expired messages using MessageManager
    // messageManager.cleanupExpiredMessages(_broker.config.messageExpiryInterval);
  }

  /// Saves persistent sessions to disk
  Future<void> savePersistentSessions() async {
    try {
      if (!_broker.config.enablePersistence) return;

      // final file = File(_broker.config.persistencePath);
      // final persistentSessions = <String, Map<String, dynamic>>{};

      // // Only save persistent sessions
      // sessions.forEach((clientId, session) {
      //   if (!session.cleanSession) {
      //     persistentSessions[clientId] = session.toPersistentData();

      //     // Add subscriptions
      //     if (clientSubscriptions.containsKey(clientId)) {
      //       persistentSessions[clientId]!['subscriptions'] = clientSubscriptions[clientId];
      //     }

      //     // Add messages (both in-flight and queued)
      //     if (messageManager.messageStore.containsKey(clientId)) {
      //       // Save in-flight messages (positive IDs)
      //       final inFlightMessages = messageManager.messageStore[clientId]!.entries
      //           .where((entry) => entry.key > 0)
      //           .map((entry) => {'id': entry.key, 'message': entry.value.toPersistentData()})
      //           .toList();
      //       if (inFlightMessages.isNotEmpty) {
      //         persistentSessions[clientId]!['inFlightMessages'] = inFlightMessages;
      //       }

      //       // Save queued messages (negative IDs)
      //       final queuedMessages = messageManager.messageStore[clientId]!.entries
      //           .where((entry) => entry.key <= 0)
      //           .map((entry) => entry.value.toPersistentData())
      //           .toList();
      //       if (queuedMessages.isNotEmpty) {
      //         persistentSessions[clientId]!['queuedMessages'] = queuedMessages;
      //       }
      //     }
      //   }
      // });

      // final data = jsonEncode(persistentSessions);
      // await file.writeAsString(data);


      // developer.log('Saved ${persistentSessions.length} persistent sessions');

      //TODO: Save persistent sessions to disk
    } catch (e) {
      developer.log('Error saving persistent sessions: $e');
    }
  }

  /// Loads persistent sessions from disk
  Future<void> loadPersistentSessions() async {
    try {
      if (!_broker.config.enablePersistence) return;

      // final file = File(_broker.config.persistencePath);
      // if (await file.exists()) {
      //   final content = await file.readAsString();
      //   final data = jsonDecode(content) as Map<String, dynamic>;

      //   data.forEach((clientId, sessionData) {
      //     // Create session
      //     final session = MqttSession.fromPersistentData(sessionData as Map<String, dynamic>);
      //     sessions[clientId] = session;

      //     // Restore subscriptions
      //     if (sessionData.containsKey('subscriptions')) {
      //       final subscriptions = sessionData['subscriptions'] as Map<String, dynamic>;
      //       clientSubscriptions[clientId] = Map<String, int>.from(subscriptions.map((topic, qos) => MapEntry(topic, qos as int)));

      //       // Add to topic subscriptions
      //       clientSubscriptions[clientId]!.forEach((topic, qos) {
      //         topicSubscriptions.putIfAbsent(topic, () => <String>{}).add(clientId);
      //       });
      //     }

      //     // Restore messages (both in-flight and queued)
      //     messageManager.messageStore.putIfAbsent(clientId, () => <int, MqttMessage>{});

      //     // Restore in-flight messages with their IDs
      //     if (sessionData.containsKey('inFlightMessages')) {
      //       final inFlightMessages = sessionData['inFlightMessages'] as List<dynamic>;
      //       for (final item in inFlightMessages) {
      //         final messageData = item as Map<String, dynamic>;
      //         final id = messageData['id'] as int;
      //         final message = MqttMessage.fromPersistentData(messageData['message'] as Map<String, dynamic>);
      //         messageManager.messageStore[clientId]![id] = message;
      //       }
      //     }

      //     // Restore queued messages with negative IDs
      //     if (sessionData.containsKey('queuedMessages')) {
      //       final messages = sessionData['queuedMessages'] as List<dynamic>;
      //       int tempId = -1;
      //       for (final msgData in messages) {
      //         // Find next available negative ID
      //         while (messageManager.messageStore[clientId]!.containsKey(tempId)) {
      //           tempId--;
      //         }
      //         final message = MqttMessage.fromPersistentData(msgData as Map<String, dynamic>);
      //         messageManager.messageStore[clientId]![tempId] = message;
      //       }
      //     }
      //   });

      //   developer.log('Loaded ${sessions.length} persistent sessions');


      // }

      //TODO: Load persistent sessions from disk
    } catch (e) {
      developer.log('Error loading persistent sessions: $e');
    }
  }

  /// Cleans up resources when the broker is shutting down
  Future<void> dispose() async {
    //TODO: Disconnect all clients
    // final clientIds = List<String>.from(clientConnections.keys);
    // for (final clientId in clientIds) {
    //   disconnectClient(clientId);
    // }

    // Save persistent sessions
    await savePersistentSessions();

    developer.log('Broker state manager disposed');
  }




  Map<String, MqttCredentials> getCredentials() {
    return _credentials;
  }
}
