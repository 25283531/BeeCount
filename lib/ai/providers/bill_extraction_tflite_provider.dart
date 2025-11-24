import 'package:flutter_ai_kit/flutter_ai_kit.dart';
import 'package:flutter_ai_kit_tflite/flutter_ai_kit_tflite.dart';

import '../tasks/bill_extraction_task.dart';

/// 账单提取TFLite Provider
///
/// 使用本地TinyBERT模型进行账单信息提取
///
/// 注意：这是一个基础实现框架
/// 实际使用需要训练并部署真实的NER模型
class BillExtractionTFLiteProvider extends TFLiteProvider<String, BillInfo> {
  BillExtractionTFLiteProvider({
    super.modelManager,
  }) : super(
          modelId: PredefinedModels.billRecognition.id,
          supportedTaskType: 'bill_extraction',
          inputPreprocessor: _preprocessInput,
          outputParser: _parseOutput,
        );

  @override
  String get name => 'TinyBERT-账单提取';

  /// 输入预处理
  ///
  /// 将文本转换为模型输入格式
  /// 注意：这是简化实现，实际需要分词、编码等步骤
  static List<Object> _preprocessInput(String text) {
    // TODO: 实际实现需要：
    // 1. 分词 (Tokenization)
    // 2. 转换为token IDs
    // 3. 添加特殊token ([CLS], [SEP])
    // 4. Padding到固定长度
    // 5. 创建attention mask

    // 简化示例：返回占位数据
    final maxLength = 128;
    final inputIds = List<double>.filled(maxLength, 0.0);

    // 简单字符级编码（实际应使用WordPiece等）
    for (int i = 0; i < text.length && i < maxLength; i++) {
      inputIds[i] = text.codeUnitAt(i).toDouble();
    }

    return [inputIds];
  }

  /// 输出解析
  ///
  /// 将模型输出转换为BillInfo
  static BillInfo _parseOutput(List<Object?> output) {
    // TODO: 实际实现需要：
    // 1. 解析NER标签（B-AMOUNT, I-AMOUNT, B-MERCHANT等）
    // 2. 提取实体
    // 3. 合并连续实体
    // 4. 解析日期时间
    // 5. 计算置信度

    // 简化示例：使用规则提取
    final result = _extractByRules(output);

    // 注意：CategoryMatcher需要分类列表，但TFLite provider在这里无法获取
    // 因此暂时不进行分类匹配，返回null category
    // 实际分类匹配会在BillCreationService中统一处理
    return result;
  }

  /// 使用规则提取（临时实现）
  ///
  /// 注意：这是占位实现，实际应使用模型输出
  static BillInfo _extractByRules(List<Object?> output) {
    // 在实际部署前，这里应该解析真实的NER模型输出
    // 当前返回空结果，表示需要训练模型
    return BillInfo(
      amount: null,
      time: null,
      merchant: null,
      category: null,
      type: null,
      account: null,
      confidence: 0.0,
    );
  }

  @override
  Future<AIResult<BillInfo>> execute(AITask<String, BillInfo> task) async {
    // 检查模型是否真实存在
    if (!await isReady()) {
      return AIResult.failure(
        '本地模型未下载。请先在设置中下载模型。',
        Duration.zero,
        metadata: AIResultMetadata(providerName: name),
      );
    }

    print('⚠️ [TFLiteProvider] 注意：当前模型为占位文件，未经训练');
    print('   提取结果仅供测试流程使用，准确度为0');
    print('   建议使用云端Provider（智谱GLM）获得实际效果');

    // 临时方案：返回空结果（让流程跑通，后续会被规则兜底）
    final startTime = DateTime.now();

    // 模拟处理延迟
    await Future.delayed(const Duration(milliseconds: 100));

    final result = BillInfo(
      amount: null,
      time: null,
      merchant: null,
      category: null,
      type: null,
      confidence: 0.0,
    );

    return AIResult.success(
      result,
      DateTime.now().difference(startTime),
      metadata: AIResultMetadata(
        providerName: name,
        modelName: 'bill_recognition_v1 (未训练)',
      ),
    );

    // TODO: 当模型训练完成后，使用以下代码替换上面的临时方案：
    // return super.execute(task);
  }
}

/// NER实体类型（用于模型训练）
enum EntityType {
  /// 金额
  amount,

  /// 时间
  time,

  /// 商家
  merchant,

  /// 类型（收入/支出）
  type,

  /// 账户
  account,

  /// 其他
  other,
}

/// NER标签（BIO标注）
class NERTag {
  static const beginAmount = 'B-AMOUNT';
  static const insideAmount = 'I-AMOUNT';
  static const beginTime = 'B-TIME';
  static const insideTime = 'I-TIME';
  static const beginMerchant = 'B-MERCHANT';
  static const insideMerchant = 'I-MERCHANT';
  static const beginType = 'B-TYPE';
  static const insideType = 'I-TYPE';
  static const beginAccount = 'B-ACCOUNT';
  static const insideAccount = 'I-ACCOUNT';
  static const outside = 'O';

  static const all = [
    beginAmount,
    insideAmount,
    beginTime,
    insideTime,
    beginMerchant,
    insideMerchant,
    beginType,
    insideType,
    beginAccount,
    insideAccount,
    outside,
  ];
}
