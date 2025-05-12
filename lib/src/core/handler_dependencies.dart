import 'package:mqtt_server/src/models/mqtt_session.dart';
import 'package:mqtt_server/src/models/mqtt_message.dart';
import 'package:mqtt_server/src/models/mqtt_connection.dart';
import 'package:mqtt_server/src/models/mqtt_credentials.dart';

/// Interface for providing dependencies to packet handlers
abstract class HandlerDependencies {
  /// Get session for a client ID
  MqttSession? getSession(String? clientId);

  /// Get retained messages
  Map<String, MqttMessage> get retainedMessages;

  /// Get topic subscriptions
  Map<String, Set<String>> get topicSubscriptions;

  /// Get client subscriptions
  Map<String, Map<String, int>> get clientSubscriptions;

  /// Subscribe a client to a topic with specified QoS
  void subscribe(String clientId, String topic, int qos);

  /// Unsubscribe a client from a topic
  void unsubscribe(String clientId, String topic);
  
  /// Get in-flight messages
  Map<String, Map<int, MqttMessage>> get inFlightMessages;
  
  /// Get client connections
  Map<String, MqttConnection> get clientConnections;

  /// Remove session for a client ID
  void removeSession(String clientId);
  
  /// Add a new session for a client ID
  void addSession(String clientId, MqttSession session);
  
  /// Get user credentials
  Map<String, MqttCredentials> getCredentials();
  
  /// Process any queued messages for a client
  void processQueuedMessages(String clientId);
  
  /// Get broker configuration
  bool get allowAnonymousConnections;

  /// Queue a message for an offline client
  void queueMessage(String clientId, String topic, List<int> payload, int qos);
}
