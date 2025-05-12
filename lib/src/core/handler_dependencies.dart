import '../models/mqtt_session.dart';
import '../models/mqtt_message.dart';
import '../models/mqtt_connection.dart';
import '../models/mqtt_credentials.dart';

/// Interface for providing dependencies to packet handlers
abstract class HandlerDependencies {
  /// Get session for a client ID
  MqttSession? getSession(String? clientId);

  /// Get retained messages
  Map<String, MqttMessage> get retainedMessages;

  /// Get topic subscriptions
  Map<String, Set<String>> get topicSubscriptions;
  
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
}
