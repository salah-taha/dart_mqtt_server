import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mqtt_server/src/mqtt_session.dart';

class MqttConnection {
  final Socket _socket;
  MqttSession? session;
  bool _isConnected = true;
  StreamSubscription? _subscription;

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
    if (!_isConnected) return;

    try {
      // Instead of adding to controller, notify broker directly
      if (_onData != null) {
        _onData!(data);
      }
    } catch (e, stackTrace) {
      print('Error handling data: $e');
      print('Stack trace: $stackTrace');
    }
  }

  void _handleError(error, StackTrace stackTrace) {
    print('Socket Error: $error');
    print('Stack trace: $stackTrace');
    _cleanupConnection();
  }

  void _handleDone() {
    print('Socket Done - Normal closure');
    _cleanupConnection();
  }

  void _cleanupConnection() {
    if (!_isConnected) return; // Already cleaned up

    _isConnected = false;
    _subscription?.cancel();

    try {
      _socket.flush();
      _socket.close();
    } catch (e) {
      print('Error during cleanup: $e');
    }

    // Notify broker of disconnection if callback is set
    if (_onDisconnect != null) {
      _onDisconnect!();
    }
  }

  // Callback setters for broker communication
  void Function(List<int>)? _onData;
  void Function()? _onDisconnect;

  void setCallbacks({
    required void Function(List<int>) onData,
    required void Function() onDisconnect,
  }) {
    _onData = onData;
    _onDisconnect = onDisconnect;
  }

  bool get isConnected => _isConnected;

  Future<void> send(Uint8List data) async {
    if (!_isConnected) {
      print('Attempting to send data when not connected');
      return;
    }

    try {
      _socket.add(data);
      // await _socket.flush(); // Ensure data is sent immediately
    } catch (e, stackTrace) {
      print('Error sending data: $e');
      print('Stack trace: $stackTrace');
      _cleanupConnection();
    }
  }

  Future<void> disconnect() async {
    _cleanupConnection();
  }
}
