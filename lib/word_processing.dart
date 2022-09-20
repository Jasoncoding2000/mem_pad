import 'package:flutter_tts/flutter_tts.dart';

final patternChinese = RegExp(
    '[\\u4e00-\\u9fa5]');
final patternNumber = RegExp(r'[^0-9.]');
FlutterTts tts = FlutterTts();
var ttsState='stopped';
var speechEngineInitiated= false;

initSpeechEngine() async {
  tts.setQueueMode(1);
  tts.setStartHandler(() {ttsState='playing';});
  tts.setCompletionHandler(() {ttsState='stopped';});
  speechEngineInitiated= true;
}

speak(text, [accent = 'US']){
  if (text==''){
    tts.stop();
  }
  if (patternChinese.hasMatch(text))  {
    tts.setLanguage('zh-CN');
    tts.setVolume(0.9);
  } else {
    tts.setLanguage('en-' + accent);
    tts.setVolume(1);
  }
  tts.speak(text);
}
