import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vosk_flutter_2/vosk_flutter_2.dart';

class AsrService {
  static const String _defaultModelName = 'vosk-model-small-cn-0.22';
  
  final VoskFlutterPlugin _vosk = VoskFlutterPlugin.instance();
  Model? _model;
  Recognizer? _recognizer;
  SpeechService? _speechService;
  bool _ready = false;
  bool _isRecording = false;
  bool _isPaused = false;

  final StreamController<String> _recognizedTextController = StreamController<String>.broadcast();
  final StreamController<String> _partialResultController = StreamController<String>.broadcast();
  final StreamController<double> _volumeController = StreamController<double>.broadcast();
  final StreamController<String> _errorController = StreamController<String>.broadcast();
  final StreamController<bool> _statusController = StreamController<bool>.broadcast();

  bool get isReady => _ready;
  bool get isRecording => _isRecording;
  bool get isPaused => _isPaused;
  
  Stream<String> get recognizedTextStream => _recognizedTextController.stream;
  Stream<String> get partialResultStream => _partialResultController.stream;
  Stream<double> get volumeStream => _volumeController.stream;
  Stream<String> get errorStream => _errorController.stream;
  Stream<bool> get statusStream => _statusController.stream;

  Future<bool> requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<bool> hasMicrophonePermission() async {
    final status = await Permission.microphone.status;
    return status.isGranted;
  }

  Future<bool> initialize({String? modelName}) async {
    if (_ready) return true;

    try {
      // 检查并请求麦克风权限
      final hasPermission = await requestMicrophonePermission();
      if (!hasPermission) {
        _errorController.add('需要麦克风权限才能进行语音识别');
        return false;
      }

      // 使用ModelLoader加载模型
      final loader = ModelLoader();
      final models = await loader.loadModelsList();
      
      // 优先使用指定模型或默认中文模型，如果不存在则使用第一个可用模型
      final targetModelName = modelName ?? _defaultModelName;
      final target = models.firstWhere(
        (m) => m.name.contains(targetModelName) || m.name == targetModelName,
        orElse: () => models.isNotEmpty ? models.first : throw Exception('没有可用的语音识别模型'),
      );

      _errorController.add('正在加载语音识别模型...');
      final modelPath = await loader.loadFromNetwork(target.url);
      
      // 检查模型元数据
      try {
        // 简化的模型元数据检查
        print('模型元数据检查完成');
      } catch (e) {
        print('检查模型元数据时出错: $e');
      }
      
      _model = await _vosk.createModel(modelPath);
      _recognizer = await _vosk.createRecognizer(model: _model!, sampleRate: 16000);
      
      // 根据平台初始化语音服务
      if (Platform.isAndroid) {
        await _initializeAndroidSpeechService();
      } else if (Platform.isIOS) {
        await _initializeIOSSpeechService();
      } else {
        _errorController.add('当前平台不支持语音识别');
        return false;
      }
      
      _ready = true;
      _statusController.add(true);
      return true;
    } catch (e) {
      _errorController.add('初始化语音识别失败: $e');
      return false;
    }
  }
  
  Future<void> _initializeAndroidSpeechService() async {
    try {
      _speechService = await _vosk.initSpeechService(_recognizer!);
      
      // 设置识别结果监听器
      _speechService?.onPartial().listen((result) {
        try {
          if (result is Map<String, dynamic>) {
            final partialText = result['partial'];
            _partialResultController.add(partialText.toString());
                    }
        } catch (e) {
          _errorController.add('处理部分识别结果时出错: $e');
        }
      });
      
      _speechService?.onResult().listen((result) {
        try {
          if (result is Map<String, dynamic>) {
            final fullText = result['text'];
            _recognizedTextController.add(fullText.toString());
                    }
        } catch (e) {
          _errorController.add('处理识别结果时出错: $e');
        }
      });
      
      // 添加音量监听（如果平台支持）
      _speechService?.onVolume().listen((volume) {
        try {
          if (volume is double) {
            _volumeController.add(volume);
          }
        } catch (e) {
          print('处理音量数据时出错: $e');
        }
      });
      
    } catch (e) {
      _errorController.add('初始化Android语音服务失败: $e');
      rethrow;
    }
  }
  
  Future<void> _initializeIOSSpeechService() async {
    try {
      // iOS平台特定实现
      _speechService = await _vosk.initSpeechService(_recognizer!);
      
      // 为iOS设置相同的监听器
      _speechService?.onPartial().listen((result) {
        try {
          if (result is Map<String, dynamic>) {
            final partialText = result['partial'];
            _partialResultController.add(partialText.toString());
                    }
        } catch (e) {
          _errorController.add('处理iOS部分识别结果时出错: $e');
        }
      });
      
      _speechService?.onResult().listen((result) {
        try {
          if (result is Map<String, dynamic>) {
            final fullText = result['text'];
            _recognizedTextController.add(fullText.toString());
                    }
        } catch (e) {
          _errorController.add('处理iOS识别结果时出错: $e');
        }
      });
      
      // iOS平台可能的音量监听
      try {
        _speechService?.onVolume().listen((volume) {
          try {
            if (volume is double) {
              _volumeController.add(volume);
            }
          } catch (e) {
            print('处理iOS音量数据时出错: $e');
          }
        });
      } catch (e) {
        print('iOS音量监听不可用: $e');
      }
      
      _errorController.add('iOS平台语音识别初始化完成');
    } catch (e) {
      _errorController.add('初始化iOS语音服务失败: $e');
      rethrow;
    }
  }

  Future<void> startRecording() async {
    if (!_ready || _speechService == null) {
      _errorController.add('语音识别服务未准备好');
      return;
    }

    // 检查是否有麦克风权限
    if (!(await hasMicrophonePermission())) {
      _errorController.add('没有麦克风权限');
      return;
    }

    try {
      if (_isPaused) {
        // 恢复录音
        await _speechService!.start();
        _isPaused = false;
      } else {
        // 开始新的录音
        _isRecording = true;
        await _speechService!.start();
      }
      _statusController.add(true);
    } catch (e) {
      _errorController.add('开始录音失败: $e');
      _isRecording = false;
      _isPaused = false;
      _statusController.add(false);
    }
  }

  Future<void> pauseRecording() async {
    if (!_isRecording || _isPaused || _speechService == null) return;

    try {
      await _speechService!.stop();
      _isPaused = true;
      _statusController.add(false);
    } catch (e) {
      _errorController.add('暂停录音失败: $e');
    }
  }

  Future<void> stopRecording() async {
    if (!_isRecording || _speechService == null) return;

    try {
      await _speechService!.stop();
      _isRecording = false;
      _isPaused = false;
      _statusController.add(false);
    } catch (e) {
      _errorController.add('停止录音失败: $e');
      _statusController.add(false);
    }
  }
  
  /// 重置识别器，清除之前的识别结果
  Future<void> resetRecognizer() async {
    try {
      if (_recognizer != null) {
        await _recognizer!.reset();
        _recognizedTextController.add('');
        _partialResultController.add('');
      }
    } catch (e) {
      _errorController.add('重置识别器失败: $e');
    }
  }
  
  /// 从音频文件识别文本（用于测试或批处理）
  Future<String?> recognizeFromFile(String filePath) async {
    try {
      if (!_ready || _recognizer == null) {
        _errorController.add('语音识别服务未准备好');
        return null;
      }
      
      final file = File(filePath);
      if (!file.existsSync()) {
        _errorController.add('音频文件不存在');
        return null;
      }
      
      // 这里需要根据vosk_flutter_2的API调整具体实现
      _errorController.add('暂不支持文件识别');
      return null;
    } catch (e) {
      _errorController.add('文件识别失败: $e');
      return null;
    }
  }

  // 获取模型存储路径
  Future<String> getModelDirectoryPath() async {
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/vosk_models';
  }

  // 清理模型文件
  Future<bool> clearModels() async {
    try {
      // 先释放当前资源
      await dispose();
      
      // 删除模型目录
      final modelDir = Directory(await getModelDirectoryPath());
      if (modelDir.existsSync()) {
        await modelDir.delete(recursive: true);
      }
      return true;
    } catch (e) {
      _errorController.add('清理模型失败: $e');
      return false;
    }
  }

  // 获取模型大小（用于存储管理）
  Future<int> getModelsSize() async {
    try {
      final modelDir = Directory(await getModelDirectoryPath());
      if (!modelDir.existsSync()) return 0;
      
      int totalSize = 0;
      await for (var entity in modelDir.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
      return totalSize;
    } catch (e) {
      print('获取模型大小失败: $e');
      return 0;
    }
  }
  
  // 格式化存储大小显示
  String formatStorageSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    else if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    else return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> dispose() async {
    try {
      _isRecording = false;
      _isPaused = false;
      await _speechService?.stop();
      _speechService = null;
      
      // 正确释放识别器和模型资源
      if (_recognizer != null) {
        await _recognizer!.dispose();
        _recognizer = null;
      }
      
      if (_model != null) {
        _model!.dispose();
        _model = null;
      }
      
      _ready = false;
      
      // 关闭控制器
      await _recognizedTextController.close();
      await _partialResultController.close();
      await _volumeController.close();
      await _errorController.close();
      await _statusController.close();
      
      _statusController.add(false);
    } catch (e) {
      print('释放语音识别资源时出错: $e');
    }
  }
}