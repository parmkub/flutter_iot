import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
part 'config.dart';
part 'notify.dart';

class PublishMessage {
  final String? topic;
  final String? payload;
  PublishMessage({this.topic, this.payload});
}

class DeviceClient extends Object {
  final BrokerConfig? config;
  MqttServerClient? _client;
  bool _connected = false;
  final List<String> _subLists = [];
  final List<PublishMessage> _pubLists = [];

  final StreamController<Event> _stream = StreamController<Event>.broadcast();
  final StreamController<GpioReadResultEvent> _gpioNotify =
      StreamController<GpioReadResultEvent>.broadcast();

  static final DeviceClient _singleton =
      DeviceClient._internal(config: BrokerConfig());
  factory DeviceClient() => _singleton;

  DeviceClient._internal({this.config}) {
    _connected = false;
    _client = MqttServerClient(config!.broker, config!.clientIdentifier);
    _client!.autoReconnect = true;
    _client!.port = config!.port;
    _client!.logging(on: false);
    _client!.keepAlivePeriod = 10;
    _client!.onDisconnected = onDisconnected;
    _client!.onConnected = onConnected;
    _client!.onSubscribed = onSubscribed;
  }

  Stream<Event> get status => _stream.stream;
  Stream<GpioReadResultEvent> get gpioNotify => _gpioNotify.stream;

  void subscribe(String topic) {
    if (_client!.connectionStatus!.state != MqttConnectionState.connected) {
      _subLists.add(topic);
    } else {
      _subLists.add(topic);
      _client!.subscribe(topic, MqttQos.atMostOnce);
    }
  }

  void publishMessage(String topic, String payload) async {
    if (_connected) {
      debugPrint('MqttClient::client publishMessage - $topic');
      MqttClientPayloadBuilder payloadBbuilder = MqttClientPayloadBuilder();
      payloadBbuilder.addString(payload);
      _client!
          .publishMessage(topic, MqttQos.atMostOnce, payloadBbuilder.payload!);
    } else {
      _pubLists.add(PublishMessage(topic: topic, payload: payload));
    }
  }

  Future<bool> connect() async {
    return await _connect();
  }

  void _onMessage(MqttReceivedMessage<MqttMessage?> event) {
    final recMess = event.payload as MqttPublishMessage;
    final String message =
        MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
    // device/10f075d82240/notify
    // ['device', '10f075d82240', 'notify']
    // gpio/10f075d82240/{on, off, read}
    // ['gpio', '10f075d82240', {on, off, read}]
    var topics = event.topic.split('/'); 
    debugPrint(event.topic); 
    if (topics[2] == 'notify') {
      if (topics.length == 3) {
        try {
          _stream.add(DeviceNotifyEvent(
              deviceId: topics[1], json: json.decode(message)));
        } catch (e) {}
      }
    }
    if (topics[2] == 'will') {
      _stream.add(DeviceWillEvent(deviceId: topics[1]));
    }
    if (topics[2] == 'checkin') {
      _stream.add(
          DeviceCheckinEvent(deviceId: topics[1], json: json.decode(message)));
    }
    if (topics[0] == 'gpio') {
      if (topics[2] == 'read') {
        _gpioNotify.add(GpioReadResultEvent(
            deviceId: topics[1], json: json.decode(message)));
      }
      if (topics[2] == 'on') {
        _gpioNotify.add(GpioReadResultEvent(deviceId: topics[1], json: {
          'gpios': [json.decode(message)]
        }));
      }
      if (topics[2] == 'off') {
        _gpioNotify.add(GpioReadResultEvent(deviceId: topics[1], json: {
          'gpios': [json.decode(message)]
        }));
      }
    }
  }

  Future<bool> _connect() async {
    _client!.autoReconnect = true;
    final MqttConnectMessage connMess = MqttConnectMessage()
        .withClientIdentifier(config!.clientIdentifier)
        .startClean() // Non persistent session for testing
        .withWillQos(MqttQos.atMostOnce);
    // print('[MQTT client] MQTT client connecting....');
    _client!.connectionMessage = connMess;

    try {
      await _client!.connect(config!.username, config!.passwd);
    } on NoConnectionException catch (e) {
      // Raised by the client when connection fails.
      debugPrint('MqttClient::client exception - $e');
      _client!.disconnect();
      return false;
    } on SocketException catch (e) {
      // Raised by the socket layer
      debugPrint('MqttClient::socket exception - $e');
      _client!.disconnect();
      return false;
    }

    /// Check we are connected
    if (_client!.connectionStatus!.state == MqttConnectionState.connected) {
      debugPrint('MqttClient::Mqtt client connected');
    } else {
      /// Use status here rather than state if you also want the broker return code.
      debugPrint(
          'MqttClient::ERROR Mqtt client connection failed - disconnecting, status is ${_client!.connectionStatus}');
      _client!.disconnect();
      return false;
    }

    /// The client has a change notifier object(see the Observable class) which we then listen to to get
    /// notifications of published updates to each subscribed topic.
    _client!.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
      if (c!.isNotEmpty) {
        _onMessage(c[0]);
      }
    });

    return true;
  }

  /// The subscribed callback
  void onSubscribed(String topic) {
    // print('EXAMPLE::Subscription confirmed for topic $topic');
  }

  /// The unsolicited disconnect callback
  void onDisconnected() {
    _connected = false;
    debugPrint(
        'MqttClient::OnDisconnected client callback - Client disconnection');
    if (_client!.connectionStatus!.disconnectionOrigin ==
        MqttDisconnectionOrigin.solicited) {
      debugPrint(
          'MqttClient::OnDisconnected callback is solicited, this is correct');
    }
  }

  /// The successful connect callback
  void onConnected() {
    _stream.add(DeviceConnectedEvent());
    _connected = true;
    Timer(const Duration(seconds: 1), () {
      for (var topic in _subLists) {
        _client!.subscribe(topic, MqttQos.atMostOnce);
      }
      if (_pubLists.isNotEmpty) {
        for (var e in _pubLists) {
          publishMessage(e.topic!, e.payload!);
        }
        _pubLists.clear();
      }
    });

    debugPrint(
        'MqttClient::OnConnected client callback - Client connection was sucessful');
  }

  /// Pong callback
  void pong() {
    // print('EXAMPLE::Ping response client callback invoked');
  }

  void close() {
    _connected = false;
    _client!.autoReconnect = false;
    _client!.disconnect();
  }

  void dispose() {
    close();
    _stream.close();
    //_notify.close();
    _gpioNotify.close();
  }

  bool get isConnected => _connected;
}
