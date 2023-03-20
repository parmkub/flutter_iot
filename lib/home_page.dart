import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_iot/mqtt/client.dart';
import 'package:flutter_iot/widgets/progress_dialog.dart';
import 'package:intl/intl.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // static String deviceId = '10f075d82240';
  static String deviceId = '1c975f1b5ae0';
  DeviceClient client = DeviceClient();

  final List<bool> _ioState = [false, false, false, false];
  final StreamController<List<bool>> _streamIo =
      StreamController<List<bool>>.broadcast();

  late ProgressDialog pr;
  Timer? timer;

  @override
  void initState() {
    // debugPrint("1. Start initState");
    // client.connect().then((value) {
    //   debugPrint("2. connected");
    //   if (value) {
    //     client.subscribe('device/$deviceId/notify');
    //     debugPrint("3. subscribe");
    //   }
    //   client.status.listen((event) {
    //     debugPrint(event.deviceId);
    //     debugPrint(event.json.toString());
    //   });
    //   debugPrint("4. listen");
    // });

    // client.status.listen((event) {
    //   debugPrint(event.deviceId);
    //   debugPrint(event.json.toString());
    // });
    _updateProgressDialog();
    _streamIo.add(_ioState);
    client.gpioNotify.listen((event) {
      debugPrint(event.json.toString());
      _cancelTimout();
      // io = {index: 0, state: 0}
      for (var io in event.json!['gpios']) {
        // [false, false, false, false]
        _ioState[io['index']] = io['state'] == 1;
      }
      _streamIo.add(_ioState);
      if (pr.isShowing()) {
        pr.hide();
      }
    });
    super.initState();
    // debugPrint("5. End initState");
  }

  void _timeout(int value) {
    timer = Timer(Duration(seconds: value), () {
      if (pr.isShowing()) {
        pr.hide();
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('มีบางอย่างผิดปกติ'),
          ),
        );
    });
  }

  void _cancelTimout() {
    if (timer != null) {
      if (timer!.isActive) {
        timer!.cancel();
      }
    }
  }

  void _updateProgressDialog() {
    pr = ProgressDialog(context, isDismissible: false);
  }

  void sendMessage(int index, bool value) {
    // gpio/1c975f1b5ae0/on
    // gpio/1c975f1b5ae0/off
    pr.show();
    String topic = 'gpio/$deviceId/${value ? 'on' : 'off'}';
    Map<String, dynamic> msg = {'index': index};
    debugPrint(json.encode(msg));
    client.publishMessage(topic, json.encode(msg));
    _timeout(3);
  }

  void doSubscribe() {
    client.subscribe('device/$deviceId/notify');
    client.subscribe('device/$deviceId/will');
    client.subscribe('device/$deviceId/checkin');
    client.subscribe('gpio/$deviceId/read/result');
    client.subscribe('gpio/$deviceId/on/result');
    client.subscribe('gpio/$deviceId/off/result');

    Future.delayed(const Duration(milliseconds: 500), () {
      client.publishMessage('gpio/$deviceId/read', '{}');
      client.publishMessage('device/$deviceId/notify/read', '{}');
    });
  }

  @override
  Widget build(BuildContext context) {
    TextStyle style = const TextStyle(fontSize: 24);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workshop IoT'),
      ),
      body: FutureBuilder(
        future: client.connect(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            doSubscribe();
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                StreamBuilder<Event>(
                  stream: client.status,
                  builder: (context, snapshot) {
                    Event? notify = snapshot.data;
                    if (snapshot.hasData) {
                      if (notify is DeviceWillEvent) {
                        return const Center(
                          child: Text('Device offline'),
                        );
                      }
                      if (notify is DeviceCheckinEvent) {
                        return const Center(
                          child: Text('Device online'),
                        );
                      }
                      if (notify is DeviceNotifyEvent) {
                        return const Center(
                          child: Text('Device online'),
                        );
                      }
                    }
                    return Container();
                  },
                ),
                const SizedBox(
                  height: 20,
                ),
                StreamBuilder<Event>(
                  stream: client.status,
                  builder: (context, snapshot) {
                    Event? notify = snapshot.data;
                    if (snapshot.hasData) {
                      if (notify is DeviceNotifyEvent) {
                        num temperature = notify.json!["temperature"];
                        num humidity = notify.json!["humidity"];
                        num light = notify.json!["light"];
                        num soil = notify.json!["soil"];
                        return sensorWidget(
                          style,
                          temperature,
                          humidity,
                          light,
                          soil,
                        );
                      } else {
                        return Center(
                          child: Text(
                            "กำลังรอข้อมูล",
                            style: style,
                          ),
                        );
                      }
                    } else {
                      return Center(
                        child: Text(
                          "กำลังรอข้อมูล",
                          style: style,
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(
                  height: 20,
                ),
                StreamBuilder(
                  stream: _streamIo.stream,
                  builder: (context, snapshot) {
                    int len = _ioState.length;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: List.generate(len, (index) {
                        return CupertinoSwitch(
                          value: _ioState[index],
                          onChanged: (value) {
                            debugPrint(value.toString());
                            sendMessage(index, value);
                          },
                        );
                      }),
                    );
                  },
                ),
              ],
            );
          }
          return const Center(
            child: CircularProgressIndicator(),
          );
        },
      ),
    );
  }

  Center sensorWidget(
      TextStyle style, num temperature, num humidity, num light, num soil) {
    var f = NumberFormat('#,###', "en_US");
    var n = NumberFormat('#,###.0', "en_US");
    return Center(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Text(
                'อุณหภูมิ:',
                style: style,
              ),
              Text(
                '${n.format(temperature)} °C',
                style: style,
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Text(
                'ความชื้น:',
                style: style,
              ),
              Text(
                '${n.format(humidity)} %',
                style: style,
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Text(
                'แสง:',
                style: style,
              ),
              Text(
                '${f.format(light)} Lux',
                style: style,
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Text(
                'ความชื้นดิน:',
                style: style,
              ),
              Text(
                '${n.format(soil)} %',
                style: style,
              ),
            ],
          )
        ],
      ),
    );
  }
}
