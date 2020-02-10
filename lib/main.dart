import 'dart:async';

import 'package:esense_flutter/esense.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

final colorBgMain = Color(0xFFEEEEEE);

final colorFgLight = Color(0xFF707070);
final colorFg = Color(0xFF1E1E1E);
final colorFgBold = Color(0xFF1A1A1A);

final colorAccent = Color(0xFF8E00CC);

final colorGradientBegin = Color(0xFFB143E0);
final colorGradientEnd = Color(0xFFF6009B);

final colorAccentBorder = Color(0x668E00CC);
final colorShadowDark = Color(0x33000000);
final colorShadowLight = Color(0x88FFFFFF);

final colorGood = Color(0xFF19C530);
final colorNeutral = Color(0xFFE6A100);
final colorDanger = Color(0xFFE1154B);

final textCalendarDayToday = TextStyle(
  fontFamily: "Jost*",fontWeight: FontWeight.w500,
  fontSize: 35,
  color: colorAccent,
);
final textCalendarDay = TextStyle(
  fontFamily: "Jost*",fontWeight: FontWeight.w500,
  fontSize: 35,
  color: colorFgBold,
);
final textCalendarMonth = TextStyle(
fontFamily: "Jost*",fontWeight: FontWeight.w300,
fontSize: 16,
color: colorFg,
);

final textActivityLabel = TextStyle(
  fontFamily: "Jost*",fontWeight: FontWeight.w500,
  fontSize: 28,
  color: colorFgBold,
);
final textActivityCounter = TextStyle(
  fontFamily: "Jost*",fontWeight: FontWeight.w500,
  fontSize: 35,
  color: colorAccent,
);

final textHeading = TextStyle(
fontFamily: "Jost*",fontWeight: FontWeight.w300,
fontSize: 26,
color: colorFg,
);
final textSubheading = TextStyle(
fontFamily: "Jost*",fontWeight: FontWeight.w300,
fontSize: 16,
color: colorFgLight,
);

void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class SensorDataDisplay extends StatelessWidget {
  final label;
  final value;

  const SensorDataDisplay({Key key, this.label, this.value}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // TODO: implement build
    return Padding(
        padding: EdgeInsets.only(top: 15),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            Text('$label',
                style: TextStyle(
                    fontSize: Theme.of(context).textTheme.title.fontSize)),
            Container(
              height: 5,
            ),
            Text('$value', overflow: TextOverflow.clip)
          ],
        ));
  }
}

class _MyAppState extends State<MyApp> {
  String _deviceName = 'Unknown';
  double _voltage = -1;
  String _deviceStatus = '';
  bool sampling = false;
  String _event = '';
  String _button = 'not pressed';
  final SpeechToText speech = SpeechToText();
  String lastWords = '';
  String lastError = '';
  String lastStatus = '';

  get darkTheme => ThemeData(
        brightness: Brightness.dark,
        primaryColorDark: Colors.red,
        accentColor: Colors.red,
//      floatingActionButtonTheme: FloatingActionButtonThemeData(
//          backgroundColor: Colors.deepOrange
//      )
      );

  @override
  void initState() {
    super.initState();
    _connectToESense();
    setupRecognition();
  }

  Future<void> _connectToESense() async {
    bool con = false;

    // if you want to get the connection events when connecting, set up the listener BEFORE connecting...
    ESenseManager.connectionEvents.listen((event) {
      print('CONNECTION event: $event');

      // when we're connected to the eSense device, we can start listening to events from it
      if (event.type == ConnectionType.connected) _listenToESenseEvents();

      setState(() {
        switch (event.type) {
          case ConnectionType.connected:
            _deviceStatus = 'connected';
            break;
          case ConnectionType.unknown:
            _deviceStatus = 'unknown';
            break;
          case ConnectionType.disconnected:
            _deviceStatus = 'disconnected';
            break;
          case ConnectionType.device_found:
            _deviceStatus = 'device_found';
            break;
          case ConnectionType.device_not_found:
            _deviceStatus = 'device_not_found';
            break;
        }
      });
    });

    // the name of the eSense device to connect to -- change this to your own device.
    String eSenseName = 'eSense-0151';
//    String eSenseName = 'eSense-1585';

    con = await ESenseManager.connect(eSenseName);

    setState(() {
      _deviceStatus = con ? 'connecting to $eSenseName' : 'connection failed';
    });
  }

  void _listenToESenseEvents() async {
    ESenseManager.eSenseEvents.listen((event) {
      print('ESENSE event: $event');

      setState(() {
        switch (event.runtimeType) {
          case DeviceNameRead:
            _deviceName = (event as DeviceNameRead).deviceName;
            break;
          case BatteryRead:
            _voltage = (event as BatteryRead).voltage;
            break;
          case ButtonEventChanged:
            _button = (event as ButtonEventChanged).pressed
                ? 'pressed'
                : 'not pressed';
            break;
          case AccelerometerOffsetRead:
            // TODO
            break;
          case AdvertisementAndConnectionIntervalRead:
            // TODO
            break;
          case SensorConfigRead:
            // TODO
            break;
        }
      });
    });

    _getESenseProperties();
  }

  void _getESenseProperties() async {
    // get the battery level every 10 secs
    Timer.periodic(Duration(seconds: 10),
        (timer) async => await ESenseManager.getBatteryVoltage());

    // wait 2, 3, 4, 5, ... secs before getting the name, offset, etc.
    // it seems like the eSense BTLE interface does NOT like to get called
    // several times in a row -- hence, delays are added in the following calls
    Timer(
        Duration(seconds: 2), () async => await ESenseManager.getDeviceName());
    Timer(Duration(seconds: 3),
        () async => await ESenseManager.getAccelerometerOffset());
    Timer(
        Duration(seconds: 4),
        () async =>
            await ESenseManager.getAdvertisementAndConnectionInterval());
    Timer(Duration(seconds: 5),
        () async => await ESenseManager.getSensorConfig());
  }

  StreamSubscription subscription;

  void _startListenToSensorEvents() async {
    // subscribe to sensor event from the eSense device
    subscription = ESenseManager.sensorEvents.listen((event) {
      print('SENSOR event: $event');
      setState(() {
        String summary = '';
        summary += '\nindex: ${event.packetIndex}';
        summary += '\ntimestamp: ${event.timestamp}';
        summary += '\naccel: ${event.accel}';
        summary += '\ngyro: ${event.gyro}';
        _event = summary;
      });
    });
    setState(() {
      sampling = true;
    });
  }

  void _pauseListenToSensorEvents() async {
    subscription.cancel();
    setState(() {
      sampling = false;
    });
  }

  void dispose() {
    _pauseListenToSensorEvents();
    ESenseManager.disconnect();
    super.dispose();
  }

  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.light(),
      darkTheme: darkTheme,
      themeMode: ThemeMode.system,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('eSense Demo App'),
        ),
        body: Column(
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: <Widget>[
                Card(
                    margin: EdgeInsets.all(25),
                    elevation: 10,
//                    shape: Border.all(color: Colors.red, width: 1),
                    color: Colors.black38,
                    child: Container(
                        width: 300,
                        child: Padding(
                        padding: EdgeInsets.all(25),
                        child: Column(children: <Widget>[
                          Icon(Icons.info_outline),
                          SensorDataDisplay(
                            label: 'Device Status:',
                            value: _deviceStatus,
                          ),
                          SensorDataDisplay(
                            label: 'Device Name:',
                            value: _deviceName,
                          ),
                          SensorDataDisplay(
                            label: 'Battery Level:',
                            value: _voltage,
                          ),
                          SensorDataDisplay(
                            label: 'Button Pressed:',
                            value: _button,
                          ),
                          SensorDataDisplay(
                            label: 'Event Type:',
                            value: _event,
                          ),
                          SensorDataDisplay(
                            label: 'Speech Input${speech.isListening ? ' - listening...' : ':'}',
                            value: lastWords,
                          ),
                        ]),
                    )
                  )
                )
              ],
            )
          ],
        ),
//
//        Align(
//          alignment: Alignment.center,
//          child: Column(
//            mainAxisAlignment: MainAxisAlignment.start,
//            crossAxisAlignment: CrossAxisAlignment.center,
//            children: [
//              Card(
//                child: Row(
//                  children: <Widget>[
//                    Text('eSense Device Status:'),
//                    Text('\t$_deviceStatus')
//                  ],
//                ),
//              ),
//
//            ],
//          ),
//        ),
        floatingActionButton: new FloatingActionButton(
          // a floating button that starts/stops listening to sensor events.
          // is disabled until we're connected to the device.
          onPressed: speech.isListening? stopListening : startListening,
//          (!ESenseManager.connected)
//              ? _connectToESense
//              : (!sampling)
//                  ? _startListenToSensorEvents
//                  : _pauseListenToSensorEvents,
          tooltip: 'Listen to eSense sensors',
          child: (!speech.isListening) ? Icon(Icons.hearing) : Icon(Icons.pause),
//          child: (!sampling) ? Icon(Icons.hearing) : Icon(Icons.pause),
        ),
      ),
    );
  }
  void startListening() {
    lastWords = "";
    lastError = "";
    speech.listen(onResult: resultListener );
    setState(() {

    });
  }

  void stopListening() {
    speech.stop( );
    setState(() {

    });
  }

  void cancelListening() {
    speech.cancel( );
    setState(() {

    });
  }

  void resultListener(SpeechRecognitionResult result) {
    if (result.finalResult) {
      setState(() {
        lastWords = "${result.recognizedWords} - ${result.confidence}";
      });
      print(lastWords);
    }
  }

  void errorListener(SpeechRecognitionError error ) {
    setState(() {
      lastError = "${error.errorMsg} - ${error.permanent}";
    });
    print(lastError);
  }
  void statusListener(String status ) {
    setState(() {
      lastStatus = "$status";
    });
//    print(lastStatus);
  }

  Future<void> setupRecognition() async {
    bool available = await speech.initialize( onStatus: statusListener, onError: errorListener );
    if ( available ) {
      print("Speech recognition ready.");
//      speech.listen( onResult: resultListener );
    }
    else {
      print("The user has denied the use of speech recognition.");
    }
  }
}
