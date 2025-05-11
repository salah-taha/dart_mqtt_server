import '../mqtt_connection.dart';
import '../mqtt_session.dart';
import '../models/mqtt_message.dart';

/// Interface for providing dependencies to packet handlers
abstract class HandlerDependencies {
  /// Get session for a client
  MqttSession? getSession(MqttConnection client);

  /// Get retained messages
  Map<String, MqttMessage> get retainedMessages;

  /// Get topic subscriptions
  Map<String, Set<MqttConnection>> get topicSubscriptions;

  /// Get in-flight messages
  Map<String, Map<int, MqttMessage>> get inFlightMessages;

  /// Remove session for a client
  void removeSession(MqttConnection client);
}
