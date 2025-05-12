import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:developer' as developer;

class MqttConnection {
  final Socket _socket;
  bool isConnected = false;
  StreamSubscription? _subscription;
  String? clientId;

  void Function(List<int>)? _onData;
  void Function()? _onDisconnect;

  MqttConnection(this._socket) {
    _socket.setOption(SocketOption.tcpNoDelay, true);

    // Handle the socket data directly without intermediate controller
    _subscription = _socket.listen(
      _handleData,
      onError: _handleError,
      onDone: _handleDone,
      // Add this to ensure we don't lose data
      cancelOnError: false,
    );
  }

  void _handleData(List<int> data) {
    try {
      // Instead of adding to controller, notify broker directly
      if (_onData != null) {
        _onData!(data);
      }
    } catch (e, stackTrace) {
      developer.log('Error handling data: $e');
      developer.log('Stack trace: $stackTrace');
    }
  }

  void _handleError(error, StackTrace stackTrace) {
    developer.log('Socket Error: $error');
    developer.log('Stack trace: $stackTrace');
    _cleanupConnection();
  }

  void _handleDone() {
    developer.log('Socket Done - Normal closure');
    _cleanupConnection();
  }

  void _cleanupConnection() {
    if (!isConnected) return; // Already cleaned up

    isConnected = false;
    _subscription?.cancel();

    try {
      _socket.flush();
      _socket.close();
    } catch (e) {
      developer.log('Error during cleanup: $e');
    }

    // Notify broker of disconnection if callback is set
    if (_onDisconnect != null) {
      _onDisconnect!();
    }
  }

  void setCallbacks({
    required void Function(List<int>) onData,
    required void Function() onDisconnect,
  }) {
    _onData = onData;
    _onDisconnect = onDisconnect;
  }

  Future<void> send(Uint8List data) async {
    try {
      _socket.add(data);
      await _socket.flush(); // Ensure data is sent immediately
    } catch (e, stackTrace) {
      developer.log('Error sending data: $e');
      developer.log('Stack trace: $stackTrace');
      _cleanupConnection();
    }
  }

  Future<void> disconnect() async {
    _cleanupConnection();
  }
}
