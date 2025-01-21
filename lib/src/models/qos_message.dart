import 'dart:async';

import 'package:mqtt_server/src/enums/qos_message_state.dart';
import 'package:mqtt_server/src/models/mqtt_message.dart';

class QosMessage {
  final String topic;
  final MqttMessage message;
  final int messageId;
  final String clientId;
  QosMessageState state;
  int retryCount;
  Timer? retryTimer;
  final Completer<void> completer;

  QosMessage({
    required this.topic,
    required this.message,
    required this.messageId,
    required this.clientId,
  })  : state = QosMessageState.published,
        retryCount = 0,
        completer = Completer<void>();
}
