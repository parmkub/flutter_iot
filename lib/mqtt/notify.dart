part of 'client.dart';

abstract class Event {
  final String? deviceId;
  final Map<String, dynamic>? json;
  Event({this.deviceId, this.json});
}

class DeviceNotifyEvent extends Event {
  DeviceNotifyEvent(
      {required String? deviceId, required Map<String, dynamic>? json})
      : super(deviceId: deviceId, json: json);
}

class GpioReadResultEvent extends Event {
  GpioReadResultEvent(
      {required String? deviceId, required Map<String, dynamic>? json})
      : super(deviceId: deviceId, json: json);
}

class DeviceConnectedEvent extends Event {}

class DeviceDisconnectedEvent extends Event {}

class GpioOffEvent extends Event {
  GpioOffEvent(
      {required String? deviceId, required Map<String, dynamic>? json});
}

class GpioOnEvent extends Event {
  GpioOnEvent({required String? deviceId, required Map<String, dynamic>? json})
      : super(deviceId: deviceId, json: json);
}

class DeviceWillEvent extends Event {
  DeviceWillEvent({required String? deviceId}) : super(deviceId: deviceId);
}

class DeviceCheckinEvent extends Event {
  DeviceCheckinEvent(
      {required String? deviceId, required Map<String, dynamic>? json})
      : super(deviceId: deviceId, json: json);
}
