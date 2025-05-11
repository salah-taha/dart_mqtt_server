class MqttCredentials {
  final String username;
  final String hashedPassword;

  MqttCredentials(this.username, this.hashedPassword);

  bool validatePassword(String? password) {
    if (password == null) return false;
    return hashedPassword == password; // In a real implementation, use proper password hashing
  }
}
