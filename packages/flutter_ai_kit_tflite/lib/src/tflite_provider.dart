import 'dart:io';
import 'package:flutter_ai_kit/flutter_ai_kit.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'model_manager.dart';

/// TFLite Provider基类
///
/// 提供TensorFlow Lite模型推理的通用能力
///
/// 示例:
/// ```dart
/// class MyTFLiteProvider extends TFLiteProvider<String, Map<String, dynamic>> {
///   MyTFLiteProvider({required super.modelId})
///       : super(
///           supportedTaskType: 'my_task',
///           inputPreprocessor: (input) => _preprocess(input),
///           outputParser: (output) => _parse(output),
///         );
/// }
/// ```
abstract class TFLiteProvider<TInput, TOutput>
    implements AIProvider<TInput, TOutput> {
  @override
  String get id => 'tflite_$modelId';

  @override
  AIProviderType get type => AIProviderType.local;

  @override
  bool get requiresNetwork => false;

  /// 模型ID
  final String modelId;

  /// 支持的任务类型
  final String supportedTaskType;

  /// 输入预处理函数
  final List<Object> Function(TInput input) inputPreprocessor;

  /// 输出解析函数
  final TOutput Function(List<Object?> output) outputParser;

  /// 模型管理器
  final ModelManager _modelManager;

  /// TFLite解释器（懒加载）
  Interpreter? _interpreter;

  TFLiteProvider({
    required this.modelId,
    required this.supportedTaskType,
    required this.inputPreprocessor,
    required this.outputParser,
    ModelManager? modelManager,
  }) : _modelManager = modelManager ?? ModelManager();

  @override
  bool supportsTask(String taskType) => taskType == supportedTaskType;

  @override
  Future<bool> isReady() async {
    return await _modelManager.isModelDownloaded(modelId);
  }

  @override
  Future<AIResult<TOutput>> execute(AITask<TInput, TOutput> task) async {
    final startTime = DateTime.now();

    try {
      // 1. 检查模型是否存在
      if (!await isReady()) {
        return AIResult.failure(
          '模型未下载: $modelId',
          DateTime.now().difference(startTime),
          metadata: AIResultMetadata(providerName: name),
        );
      }

      // 2. 懒加载模型
      if (_interpreter == null) {
        await _loadModel();
      }

      // 3. 预处理输入
      final input = inputPreprocessor(task.input);

      // 4. 推理
      final output = await _runInference(input);

      // 5. 解析输出
      final result = outputParser(output);

      return AIResult.success(
        result,
        DateTime.now().difference(startTime),
        metadata: AIResultMetadata(
          providerName: name,
          modelName: modelId,
        ),
      );
    } catch (e) {
      return AIResult.failure(
        e.toString(),
        DateTime.now().difference(startTime),
        metadata: AIResultMetadata(providerName: name),
      );
    }
  }

  @override
  Future<double> estimateCost(AITask<TInput, TOutput> task) async => 0.0;

  /// 加载模型
  Future<void> _loadModel() async {
    final modelPath = await _modelManager.getModelPath(modelId);
    print('📦 [TFLiteProvider] 加载模型: $modelPath');

    _interpreter = Interpreter.fromFile(File(modelPath));

    print('✅ [TFLiteProvider] 模型已加载');
    print('   输入形状: ${_interpreter!.getInputTensors().map((t) => t.shape)}');
    print('   输出形状: ${_interpreter!.getOutputTensors().map((t) => t.shape)}');
  }

  /// 运行推理
  Future<List<Object?>> _runInference(List<Object> input) async {
    if (_interpreter == null) {
      throw Exception('Interpreter not initialized');
    }

    // 创建输出缓冲区
    final outputTensors = _interpreter!.getOutputTensors();
    final outputs = List<Object?>.filled(outputTensors.length, null);

    for (int i = 0; i < outputTensors.length; i++) {
      final shape = outputTensors[i].shape;
      final type = outputTensors[i].type;

      // 根据类型创建输出缓冲区
      // 简化处理：直接创建空列表，让推理引擎填充
      final size = shape.reduce((a, b) => a * b);
      outputs[i] = List.filled(size, 0.0);
    }

    // 运行推理
    _interpreter!.run(input, outputs);

    return outputs;
  }

  /// 释放资源
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}
