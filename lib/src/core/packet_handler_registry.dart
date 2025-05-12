import 'dart:typed_data';
import 'package:mqtt_server/src/models/mqtt_connection.dart';
import 'package:mqtt_server/src/mqtt_broker.dart';
import 'packet_handler_base.dart';
import 'package:mqtt_server/src/packet_handlers/connect_handler.dart';
import 'package:mqtt_server/src/packet_handlers/disconnect_handler.dart';
import 'package:mqtt_server/src/packet_handlers/pingreq_handler.dart';
import 'package:mqtt_server/src/packet_handlers/pubcomp_handler.dart';
import 'package:mqtt_server/src/packet_handlers/publish_handler.dart';
import 'package:mqtt_server/src/packet_handlers/puback_handler.dart';
import 'package:mqtt_server/src/packet_handlers/pubrec_handler.dart';
import 'package:mqtt_server/src/packet_handlers/pubrel_handler.dart';
import 'package:mqtt_server/src/packet_handlers/subscribe_handler.dart';
import 'package:mqtt_server/src/packet_handlers/unsubscribe_handler.dart';

class PacketHandlerRegistry {
  final Map<int, PacketHandlerBase> _handlers = {};
  final MqttBroker _broker;

  PacketHandlerRegistry(this._broker) {
    _initializeHandlers();
  }

  void _initializeHandlers() {
    _handlers[1] = ConnectHandler(_broker); // CONNECT
    _handlers[3] = PublishHandler(_broker); // PUBLISH
    _handlers[4] = PubackHandler(_broker); // PUBACK
    _handlers[5] = PubrecHandler(_broker); // PUBREC
    _handlers[6] = PubrelHandler(_broker); // PUBREL
    _handlers[7] = PubcompHandler(_broker); // PUBCOMP
    _handlers[8] = SubscribeHandler(_broker); // SUBSCRIBE
    _handlers[10] = UnsubscribeHandler(_broker); // UNSUBSCRIBE
    _handlers[12] = PingreqHandler(_broker); // PINGREQ
    _handlers[14] = DisconnectHandler(_broker); // DISCONNECT
  }

  Future<void> handlePacket(Uint8List data, MqttConnection client) async {
    if (data.isEmpty) return;

    final packetType = (data[0] >> 4) & 0x0F;
    final qos = (data[0] >> 1) & 0x03;
    final retain = (data[0] & 0x01) == 0x01;

    final handler = _handlers[packetType];
    if (handler != null) {
      await handler.handle(data, client, qos: qos, retain: retain);
    }
  }
}
