import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:async/async.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // new
import 'package:firebase_core/firebase_core.dart'; // new
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock/wakelock.dart';

import 'word_processing.dart';

CollectionReference nodeDatabase =
FirebaseFirestore.instance.collection('thoughtnodes');
DocumentReference configDatabase =
FirebaseFirestore.instance.collection('config').doc('progress');

AudioPlayer musicPlayer = AudioPlayer();
var battery = Battery();
Timer nonfictionTimer = Timer(const Duration(seconds: 30), () => {});
final wakeTimer = RestartableTimer(const Duration(minutes: 10), () {
  Wakelock.disable();
});

const directory = "storage/emulated/0/Download/";
final bookDir = RegExp(r'[^0-9.]');
int lastKeyTime = DateTime.now().millisecondsSinceEpoch-3000;
int lastActionTime = DateTime.now().millisecondsSinceEpoch;

Map localFlashcards = {'place_holder': {}};

var questionID = '';
List flashPanes = ['', '', ''];
var relations = {
  "parents_empty": false,
  "children_empty": false,
  "current_relation": "",
  "answerIDs": ['']
};
String displayState = "none";
int previewTime = 0;

var config = {};
int playLength = 50;
Map audioState = {
  'promptMode': 'noplay',
  'audioMode': 'novel',
  'novelProgress': -1,
  'nonfictionProgress': -1,
  'flashcardCount': 0,
};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSpeechEngine();
  await Firebase.initializeApp();
  await FirebaseAuth.instance.signInWithEmailAndPassword(
    email: 'englishexpress@126.com',
    password: '45ydk10',
  );
  await initConfig();
  runApp(const FireStoreApp());
  Wakelock.enable();
}

class FireStoreApp extends StatefulWidget {
  const FireStoreApp({Key? key}) : super(key: key);

  @override
  State<FireStoreApp> createState() => _FireStoreAppState();
}

class _FireStoreAppState extends State<FireStoreApp> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    speak('initialized', 'GB');
    super.initState();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {

    return KeyboardListener(
      autofocus: true,
      focusNode: _focusNode,
      onKeyEvent: (event) {
        var bluetoothKey = event.logicalKey.keyLabel.toString();
        if (DateTime.now().millisecondsSinceEpoch - lastKeyTime > 1000) {
          lastKeyTime = DateTime.now().millisecondsSinceEpoch;
          if (bluetoothKey == 'Arrow Left') {
            if (audioState['novelProgress'] != -1) {
              AudioOperation.rewind(-3);
            }
          } else if (bluetoothKey == 'Arrow Right') {
            if (audioState['novelProgress'] != -1) {
              AudioOperation.rewind(3);
            }
          } else if (bluetoothKey == 'Game Button Start') {
            audioState['promptMode'] = 'clicktoplay';
            AudioOperation.stop();
            speak('shake mode', 'GB');
          } else if (bluetoothKey == 'Game Button X') {
            audioState['promptMode'] = 'flashcard';
            AudioOperation.stop();
            playLength = 50;
            speak('flashcard mode', 'GB');
          } else if (bluetoothKey == 'Game Button Y') {
            audioState['promptMode'] = 'noplay';
            AudioOperation.stop();
            speak('no play mode', 'GB');
          } else if (bluetoothKey == 'Game Button Select') {
            if (audioState['audioMode'] == 'novel') {
              audioState['audioMode'] = 'nonfiction';
              AudioOperation.stop();
              speak('playing nonfiction', 'GB');
            } else if (audioState['audioMode'] == 'nonfiction') {
              audioState['audioMode'] = 'music';
              AudioOperation.stop();
              speak('playing music', 'GB');
            } else if (audioState['audioMode'] == 'music') {
              audioState['audioMode'] = 'novel';
              AudioOperation.stop();
              speak('playing novel', 'GB');
            }
          } else if (bluetoothKey == 'Arrow Up') {
            FlashcardOperation.upperClick();
          } else if (bluetoothKey == 'Arrow Down' ||
              bluetoothKey == 'Game Button A') {
            FlashcardOperation.lowerClick();
          }
        }
        lastKeyTime = DateTime.now().millisecondsSinceEpoch;
      },
      child: Container(),
    );
  }
}

initConfig() async {
  await configDatabase.get().then((DocumentSnapshot documentSnapshot) {
    config = documentSnapshot.data() as Map;
  });
}

class FlashcardOperation {
  static upperClick() {
    final currentTime = DateTime.now().millisecondsSinceEpoch;
    lastActionTime = currentTime;
    if (audioState['promptMode'] == 'clicktoplay') {
      if (audioState['audioMode'] == 'novel') {
        audioState['novelProgress'] -= playLength;
      } else if (audioState['audioMode'] == 'nonfiction') {
        audioState['nonfictionProgress'] -= 30000;
      }
      AudioOperation.startPlay();
      return;
    }

    if (displayState == "none") {
      readLatestQuestion();
    }
    if (displayState == "upper") {
      readAnswers();
    }
    if (displayState == "lower") {
      if (audioState['promptMode'] == 'flashcard') {
        playLength += 100;
      }
      if (relations['current_relation'] == 'parents') {
        nodeDatabase.doc(questionID).update({
          'parents_review': lastActionTime + 1000,
          'parents_wait': 1000,
        });
      } else {
        nodeDatabase.doc(questionID).update({
          'review_time': lastActionTime + 1000,
          'wait_time': 1000,
        });
      }
      displayState = "none";
      flashPanes = ['', '', ''];
      lowerClick();
    }

  }

  static lowerClick() {
    Wakelock.enable();
    wakeTimer.reset();
    final currentTime = DateTime.now().millisecondsSinceEpoch;
    if (currentTime - lastActionTime < 600000) {
      playLength += 10;
    } else {
      playLength = 50;
    }
    playLength = min(playLength, 1000);
    lastActionTime = currentTime;
    if (['clicktoplay', 'longplay'].contains(audioState['promptMode'])) {
      AudioOperation.startPlay();
      return;
    }

    if (displayState == "none") {
      readLatestQuestion();
    }
    if (displayState == "upper") {
      readAnswers();
    }
    if (displayState == "lower") {
      if (relations['current_relation'] == 'parents') {
        final lastTime = localFlashcards[questionID]['parents_review'] -
            localFlashcards[questionID]['parents_wait'];
        final newWait =
            (currentTime - lastTime) * (1.2 + Random().nextDouble());
        final newReview = currentTime + newWait;
        nodeDatabase.doc(questionID).update({
          'parents_review': newReview.round(),
          'parents_wait': newWait.round(),
        });
      } else {
        final lastTime = localFlashcards[questionID]['review_time'] -
            localFlashcards[questionID]['wait_time'];
        final newWait =
            (currentTime - lastTime) * (1.2 + Random().nextDouble());
        final newReview = currentTime + newWait;
        nodeDatabase.doc(questionID).update({
          'review_time': newReview.round(),
          'wait_time': newWait.round(),
        });
      }
      displayState = "none";
      flashPanes = ['', '', ''];
      if (audioState['promptMode'] == 'flashcard') {
        if (audioState['audioMode'] == 'music' &&
            audioState['flashcardCount'] < 10) {
          audioState['flashcardCount']++;
          lowerClick();
        } else {
          audioState['flashcardCount'] = 0;
          waitToPlay();
        }
      } else {
        audioState['flashcardCount'] = 0;
        lowerClick();
      }
    }
    lastActionTime = currentTime;

  }

  static waitToPlay() async {
    final startTimer = lastActionTime;
    while (DateTime.now().millisecondsSinceEpoch - startTimer < 2000) {
      await Future.delayed(const Duration(seconds: 1));
      if (startTimer != lastActionTime) {
        return;
      }
    }
    AudioOperation.startPlay();
  }

  static queryChildren() async {
    if (relations['children_empty'] == true) {
      return '';
    }
    var nodeID = '';
    QuerySnapshot snapshot = await nodeDatabase
        .where('review_time',
        isLessThan: DateTime.now().millisecondsSinceEpoch + previewTime)
        .orderBy('review_time', descending: true)
        .limit(1)
        .get();
    if (snapshot.size == 0) {
      relations['children_empty'] = true;
      return 'all finished';
    } else {
      relations['children_empty'] = false;
    }
    snapshot.docs.forEach((x) {
      nodeID = x.id;
      localFlashcards[x.id] = x.data();
    });
    relations['current_relation'] = 'children';
    return nodeID;
  }

  static queryParents() async {
    if (relations['parents_empty'] == true) {
      return '';
    }
    var nodeID = '';
    QuerySnapshot snapshot = await nodeDatabase
        .where('parents_review',
        isLessThan: DateTime.now().millisecondsSinceEpoch + previewTime)
        .orderBy('parents_review', descending: true)
        .limit(1)
        .get();
    if (snapshot.size == 0) {
      relations['parents_empty'] = true;
      return 'all finished';
    } else {
      relations['parents_empty'] = false;
    }
    snapshot.docs.forEach((x) {
      nodeID = x.id;
      localFlashcards[x.id] = x.data();
    });
    relations['current_relation'] = 'parents';
    return nodeID;
  }

  static readLatestQuestion() async {
    questionID = '';
    while (questionID == '') {
      if (relations['parents_empty'] == true &&
          relations['children_empty'] == true) {
        speak('congratulations! your study is all finished!', 'GB');
        if (previewTime == 0) {
          previewTime += 86400000;
        } else {
          previewTime *= 2;
        }
        return '';
      }
      var relatives = Random().nextInt(2);
      if (relatives == 0) {
        questionID = await queryParents();
        if (questionID == 'all finished') {
          relations['parents_empty'] = true;
        } else if (localFlashcards[questionID]['parents'].length < 1) {
          nodeDatabase.doc(questionID).update({
            'parents_review': 9999999999999,
          });
          questionID = '';
        }
      } else {
        questionID = await queryChildren();
        if (questionID == 'all finished') {
          relations['children_empty'] = true;
        } else if (localFlashcards[questionID]['children'].length < 1) {
          nodeDatabase.doc(questionID).update({
            'review_time': 9999999999999,
          });
          questionID = '';
        }
      }
    }

    if (questionID == 'all finished') {
      speak('congratulations! all finished!', 'GB');
      return;
    }

    speak(localFlashcards[questionID]['text']);
    flashPanes[0] = localFlashcards[questionID]['text'];
    var r = await relations['current_relation'] as String;
    //await Future.delayed(const Duration(seconds: 2));
    speak(r, 'GB');
    flashPanes[0] += '\n' + r;
    relations['answerIDs'] = localFlashcards[questionID][r];
    displayState = "upper";
  }

  static readAnswers() async {
    var answerIDs = relations['answerIDs'] as List;
    QuerySnapshot snapshot = await nodeDatabase
        .where(FieldPath.documentId, whereIn: answerIDs)
        .get();
    var answerNodes = snapshot.docs.map((x) => x);
    var answersMapped = {for (var x in answerNodes) x.id: x['text']};
    var displayedText = "";

    answerIDs.forEach((x) {
      var text = answersMapped[x];
      speak(text);
      displayedText += "\n" + text;
    });


    flashPanes[1] = displayedText;
    //await Future.delayed(const Duration(seconds: 1));
    speak(DateTime.now().toString().substring(11, 16), 'GB');
    displayState = "lower";
  }
}

class AudioOperation {
  static rewind(distance) {
    final currentTime = DateTime.now().millisecondsSinceEpoch;
    if (currentTime - lastActionTime < 2000) {
      return;
    }
    lastActionTime = currentTime;
    if (audioState['audioMode'] == 'novel') {
      audioState['novelProgress'] += distance * 240;
      if (ttsState == 'playing') {
        //var playLength=240;
        if (audioState['promptMode'] == 'longplay') {
          playLength = 15 * 240;
        }
        audioState['novelProgress'] -= 240;
        startPlay();
      }
    } else if (audioState['audioMode'] == 'nonfiction') {
      audioState['nonfictionProgress'] += distance * 30000;
      if (musicPlayer.state == PlayerState.playing) {
        startPlay();
      }
    }
  }

  static stop() {
    if (ttsState == 'playing') {
      speak('');
    }
    musicPlayer.stop();
  }

  static nonfictionStop(title) async {
    if (['clicktoplay', 'longplay'].contains(audioState['promptMode'])) {
      speak(DateTime.now().toString().substring(11, 16), 'GB');
    }
    if (musicPlayer.state == PlayerState.completed) {
      audioState['nonfictionProgress'] = 0;
      speak('This is the end of $title', 'GB');
    } else if (musicPlayer.state == PlayerState.playing) {
      int p = await musicPlayer.getCurrentPosition() as int;
      audioState['nonfictionProgress'] = p - 5000;
      musicPlayer.stop();
    }
    if ((config[title][1] - audioState['nonfictionProgress']).abs() > 60000) {
      int l = await musicPlayer.getDuration() as int;
      config[title][1] = audioState['nonfictionProgress'];
      if (l > 0) {
        config[title][2] = l;
      }
      configDatabase.update(config as Map<String, Object?>);
    }
  }

  static startPlay() async {
    await stop();
    if (audioState['audioMode'] == 'novel') {
      final title = config['currentNovel'];
      //final pathConverted=config[title][0].replaceAll('/data/user/0/com.example.gtk_flutter/cache/file_picker','/sdcard/audiobooks/txt');
      final originalPath=config[title][0];
      final i=originalPath.lastIndexOf('/');
      final convertedPath='/sdcard/audiobooks/txt/'+originalPath.substring(i+1);
      await Permission.storage.request();
      final file = File(convertedPath);
      //final file = File(config[title][0]);


      if (audioState['novelProgress'] == -1) {
        audioState['novelProgress'] = config[title][1];
      }
      final response = await file.readAsString();
      if (audioState['promptMode'] == 'longplay') {
        playLength = 15 * 240;
      } else if (audioState['promptMode'] == 'clicktoplay') {
        playLength = 240;
      }
      final text = response.substring(audioState['novelProgress'],
          audioState['novelProgress'] + playLength);
      audioState['novelProgress'] += playLength - 20;
      if ((config[title][1] - audioState['novelProgress']).abs() > 500) {
        config[title][1] = audioState['novelProgress'];
        configDatabase.update(config as Map<String, Object?>);
        speak('Chapter${audioState['novelProgress'] ~/ 10000}:');
      }
      //Timer(const Duration(seconds: 1), () => speak(text));

      speak(text);
      if (['clicktoplay', 'longplay'].contains(audioState['promptMode'])) {
        speak(DateTime.now().toString().substring(11, 16), 'GB');
      } else if (audioState['promptMode'] == 'flashcard' &&
          playLength >= 1000) {
        speak('Milestone accomplished', 'GB');
      }
    } else if (audioState['audioMode'] == 'nonfiction') {
      final title = config['currentNonfiction'];
      final originalPath=config[title][0];
      final i=originalPath.lastIndexOf('/');
      final file='/sdcard/audiobooks/txt/'+originalPath.substring(i+1);

      await musicPlayer.play(DeviceFileSource(file));
      if (config[title][2] == 0) {
        config[title][1] = 0;
        var l = await musicPlayer.getDuration();
        config[title][2] = l;
      } else {
        if (audioState['nonfictionProgress'] == -1) {
          audioState['nonfictionProgress'] = config[title][1];
        }
        var p = max(0, audioState['nonfictionProgress'] as int);
        audioState['nonfictionProgress'] = p;
        await musicPlayer.seek(Duration(milliseconds: p));
      }
      configDatabase.update(config as Map<String, Object?>);
      if (nonfictionTimer.isActive) {
        print('timer canceled');
        nonfictionTimer.cancel();
      }
      nonfictionTimer =
          Timer(const Duration(seconds: 30), () => nonfictionStop(title));
    } else if (audioState['audioMode'] == 'music') {
      final title = config['currentMusic'];
      final file = config[title][0].replaceAll('com.example.gtk_flutter','com.example.mem_pad');
      //await musicPlayer.play(file, isLocal: true, volume: 0.5);
      await musicPlayer.play(DeviceFileSource(file));
      await musicPlayer.setVolume(0.5);
    }
  }

  static initBook(file, [source = '']) {
    final titleComplete = file.name.split('.');
    final title = titleComplete[0];
    if (titleComplete[1] == 'txt') {
      var response = utf8.decode(file.bytes, allowMalformed: true);
      config['currentNovel'] = title;
      if (!config.keys.contains(title)) {
        config[title] = [file.path, 0, response.length];
      }
      audioState['novelProgress'] = config[title][1];
    } else if (titleComplete[1] == 'mp3') {
      if (source == '') {
        config['currentMusic'] = title;
        config[title] = [file.path];
      } else {
        config['currentNonfiction'] = title;
        config[title] = [file.path, 0, 0];
      }
    }
    configDatabase.update(config as Map<String, Object?>);
  }

  static playClipboard(text) {
    speak(text);
  }
}

