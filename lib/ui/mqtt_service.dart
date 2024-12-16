import 'dart:async';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
// import 'package:geolocator/geolocator.dart';

class MqttService {
  late MqttServerClient mqttClient;
  final String broker;
  final int port;
  final String username;
  final String password;
  final String topic;

  MqttService({
    required this.broker,
    required this.port,
    required this.username,
    required this.password,
    required this.topic,
  });

  Future<void> connect(Function(String) onMessageReceived) async {
    mqttClient = MqttServerClient(broker, '');
    mqttClient.port = port;
    mqttClient.secure = true;
    mqttClient.logging(on: true);
    mqttClient.setProtocolV311();
    mqttClient.connectionMessage =
        MqttConnectMessage().authenticateAs(username, password).startClean();

    mqttClient.onConnected = () {
      print('MQTT Client đã kết nối');
    };

    mqttClient.onDisconnected = () {
      print('MQTT Client đã ngắt kết nối');
    };

    mqttClient.onSubscribed = (String topic) {
      print('Đã đăng ký chủ đề: $topic');
    };

    try {
      await mqttClient.connect();
      mqttClient.subscribe(topic, MqttQos.atLeastOnce);
      mqttClient.updates!.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
        final MqttPublishMessage message =
            messages[0].payload as MqttPublishMessage;
        final String payload =
            MqttPublishPayload.bytesToStringAsString(message.payload.message)
                .trim();
        print('Đã nhận Payload: $payload');
        onMessageReceived(payload);
      });
    } catch (e) {
      print('Lỗi MQTT: $e');
      mqttClient.disconnect();
    }
  }

  void disconnect() {
    mqttClient.disconnect();
  }
} 