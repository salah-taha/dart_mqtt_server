class MqttSession {
  final String clientId;
  final bool cleanSession;
  final Map<String, int> qosLevels = {};
  int _nextMessageId = 1;

  MqttSession({
    required this.clientId,
    required this.cleanSession,
  });

  int getNextMessageId() {
    final id = _nextMessageId;
    _nextMessageId = (_nextMessageId + 1) % 65536;
    if (_nextMessageId == 0) _nextMessageId = 1;
    return id;
  }
}
