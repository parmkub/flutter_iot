part of 'client.dart';

class BrokerConfig {
  String broker = '167.71.223.60';
  int port = 1883;
  String username = 'training';
  String passwd = '7315b750';
  String clientIdentifier = '';

  BrokerConfig() {
    var uuid = const Uuid();
    clientIdentifier = uuid.v4();
    debugPrint('[MQTT Client] client id: $clientIdentifier');
  }
}
