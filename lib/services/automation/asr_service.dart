import 'dart:io';
import 'package:vosk_flutter_2/vosk_flutter.dart';

class AsrService {
  final VoskFlutterPlugin _vosk = VoskFlutterPlugin.instance();
  Model? _model;
  Recognizer? _recognizer;
  SpeechService? _speechService;
  bool _ready = false;

  bool get isReady => _ready;

  Future<void> initialize({String? modelName}) async {
    if (_ready) return;
    final loader = ModelLoader();
    final models = await loader.loadModelsList();
    final target = modelName != null
        ? models.firstWhere((m) => m.name == modelName, orElse: () => models.first)
        : models.first;
    final modelPath = await loader.loadFromNetwork(target.url);
    _model = await _vosk.createModel(modelPath);
    _recognizer = await _vosk.createRecognizer(model: _model!, sampleRate: 16000);
    if (Platform.isAndroid) {
      _speechService = await _vosk.initSpeechService(_recognizer!);
    }
    _ready = true;
  }

  Stream<dynamic>? onPartial() => _speechService?.onPartial();
  Stream<dynamic>? onResult() => _speechService?.onResult();

  Future<void> start() async {
    if (!_ready || _speechService == null) return;
    await _speechService!.start();
  }

  Future<void> stop() async {
    if (_speechService == null) return;
    await _speechService!.stop();
  }

  Future<void> dispose() async {
    await _speechService?.stop();
    _speechService = null;
    _recognizer = null;
    _model = null;
    _ready = false;
  }
}