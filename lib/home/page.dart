import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:esense_flutter/esense.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:one_up/home/center.dart';
import 'package:one_up/home/footer.dart';
import 'package:one_up/home/header.dart';
import 'package:one_up/model/summary.dart';
import 'package:one_up/utils/stream.dart';
import 'package:one_up/vars/constants.dart';

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Key key;

  // connection
  FlutterBlue flutterBlue = FlutterBlue.instance;
  String _deviceName = 'eSense-0151';
  double _voltage = -1;
  String _button = 'not pressed';
  bool _isConnected = false;
  bool _tryingToConnect = false;
  Timer batteryTimer;

  // data
  StreamSubscription _summarySubscription;
  List<Summary> _summaries = new List();
  Summary _currentSummary;

  // workout
  ActivitySubscription _activitySubscription;
  bool _workoutInProgress = false;
  String _currentActivity;
  int currentActivityRepCount = 0;

  // TTS
  FlutterTts textToSpeech;
  bool textToSpeechEnabled = true;

  @override
  void initState() {
    key = UniqueKey();
    _fetchSummaries();
    _initTextToSpeech();
    _connectESense();
    super.initState();
  }

  @override
  void dispose() {
    _activitySubscription?.cancel();
    _summarySubscription?.cancel();
    ESenseManager.disconnect();
    super.dispose();
  }

  void _fetchSummaries() {
    _summarySubscription?.cancel();
    _summarySubscription =
        Summary.collection.snapshots().listen((QuerySnapshot snapshot) {
      var summaries = snapshot.documents
          .map((DocumentSnapshot doc) => new Summary.fromDocument(doc))
          .where((summary) =>
              summary.isFromToday ||
              summary.counters.values.reduce((a, b) => a + b) > 0)
          .toList();
      setSummaries(summaries);
    });
  }

  void setSummaries(List<Summary> summaries) async {
    // add an empty summary for today if there is none
    var latestSummary = summaries.first;
    var currentSummary = latestSummary.isFromToday
        ? latestSummary
        : await Summary.create().add();

    setState(() {
      _currentSummary = currentSummary;
      _summaries = summaries.reversed.toList();
    });
  }

  void _initTextToSpeech() {
    textToSpeech = FlutterTts();
    textToSpeech.setSpeechRate(0.5);
    textToSpeech.setPitch(0.1);
  }

  void enableTextToSpeech([bool value]) {
    // add an empty summary for today if there is none
    setState(() {
      textToSpeechEnabled = value ?? !textToSpeechEnabled;
    });
  }

  Future<void> _connectESense() async {
    // if you want to get the connection events when connecting, set up the listener BEFORE connecting...
    ESenseManager.connectionEvents.listen((event) {
      print('CONNECTION event: $event');
      if (event.type == ConnectionType.connected) {
        setState(() {
          _isConnected = true;
        });
        _listenToESenseEvents();
      } else {
        setState(() {
          _isConnected = false;
        });
      }
    });

    if (await flutterBlue.isOn) {
      setState(() {
        _tryingToConnect = true;
      });

      await ESenseManager.connect(_deviceName);

      setState(() {
        _tryingToConnect = false;
      });
    }
  }

  void _listenToESenseEvents() async {
    batteryTimer?.cancel();
    batteryTimer = Timer.periodic(Duration(seconds: 10), (_) {
      if (ESenseManager.connected) ESenseManager.getBatteryVoltage();
    });

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
            if ((event as ButtonEventChanged).pressed) {
              if (_button != 'pressed') {
                _button = 'pressed';
                _workoutInProgress ? _finishWorkout() : _startWorkout();
              }
            } else {
              _button = 'not pressed';
            }
            break;
          case AccelerometerOffsetRead:
            break;
          case AdvertisementAndConnectionIntervalRead:
            break;
          case SensorConfigRead:
            break;
        }
      });
    });
  }

  void setESenseName(String name) {
    setState(() {
      _deviceName = name;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: colorBg,
      body: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          HeaderPanel(_deviceName, setESenseName, _connectESense,
              _tryingToConnect, _isConnected, _voltage),
          SummaryCarousel(
            key,
            _summaries,
            onPageChange,
            _currentActivity,
          ),
          ActionsPanel(
              _isConnected,
              _connectESense,
              _startWorkout,
              _finishWorkout,
              _workoutInProgress,
              _currentSummary,
              _resetActivities,
              textToSpeechEnabled,
              enableTextToSpeech),
        ],
      ),
    );
  }

  void onPageChange(int page) {
//    setState(() {
//
//    });
  }

  void _resetActivities() {
    _currentSummary.reset().submit().whenComplete(_fetchSummaries);
  }

  void handleActivity(String activity) {
    print('Activity: $activity');
    bool newActivity = _currentActivity != activity;
    setState(() {
      _currentActivity = activity;
      if (activity != null) _currentSummary.counters[activity] += 1;
    });
    if (textToSpeechEnabled) {
      if (activity != null) {
        currentActivityRepCount += 1;
        if (newActivity) {
          currentActivityRepCount = 1;
          textToSpeech.speak('$activity');
        } else {
          textToSpeech.speak('$currentActivityRepCount');
        }
      } else {
        textToSpeech.speak('Resting');
      }
    }
  }

  // delay just enough to avoid native beep from earable button press
  Future<void> speakDelayed(String text) async {
    Timer.periodic(Duration(milliseconds: 1000), (timer) {
      timer.cancel();
      textToSpeech.speak(text);
    });
  }

  void _startWorkout() {
    print('recording workout');
    if (textToSpeechEnabled) speakDelayed('Recording workout');
    if (!_workoutInProgress) {
      setState(() {
        _workoutInProgress = true;
      });

      if (_activitySubscription == null) {
        _activitySubscription = ActivitySubscription(handleActivity);
      } else {
        _activitySubscription.resume();
      }
    }
  }

  void _finishWorkout() {
    print('saving workout');
    if (textToSpeechEnabled)
      speakDelayed(
          'Saving workout. Today, you have done ${_currentSummary.toAccessibleString()}');
    if (_workoutInProgress) {
      setState(() {
        _workoutInProgress = false;
      });
      _activitySubscription?.pause();

      // submit results to database
      _currentSummary.submit().whenComplete(_fetchSummaries);
    }
  }
}
