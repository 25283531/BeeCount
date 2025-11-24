import 'dart:convert';
import 'package:flutter_ai_kit/flutter_ai_kit.dart';
import 'package:flutter_ai_kit_zhipu/flutter_ai_kit_zhipu.dart';
import '../tasks/bill_extraction_task.dart';
import '../../services/logger_service.dart';

/// 账单提取GLM Provider基类
///
/// 封装公共逻辑，供文本和视觉Provider继承
abstract class BillExtractionGLMBaseProvider implements AIProvider<String, BillInfo> {
  final ZhipuGLMProvider baseProvider;
  final List<String>? expenseCategories;
  final List<String>? incomeCategories;
  final List<String>? accounts;

  BillExtractionGLMBaseProvider({
    required this.baseProvider,
    this.expenseCategories,
    this.incomeCategories,
    this.accounts,
  });

  @override
  AIProviderType get type => baseProvider.type;

  @override
  bool get requiresNetwork => baseProvider.requiresNetwork;

  @override
  bool supportsTask(String taskType) => taskType == 'bill_extraction';

  @override
  Future<bool> isReady() => baseProvider.isReady();

  @override
  Future<AIResult<BillInfo>> execute(AITask<String, BillInfo> task) async {
    // 1. 构建账单提取Prompt（由子类实现）
    final prompt = buildPrompt(task.input);

    // 2. 调用底层GLM Provider
    final textTask = _TextTask(prompt);
    final result = await baseProvider.execute(textTask);

    if (!result.success) {
      return AIResult.failure(
        result.error!,
        result.duration,
        metadata: result.metadata,
      );
    }

    // 3. 打印AI原始返回结果
    logger.debug('AI', '[原始返回] ${result.data}');

    // 4. 解析业务结果
    try {
      final billInfo = parseResponse(result.data!);
      return AIResult.success(
        billInfo,
        result.duration,
        metadata: result.metadata,
      );
    } catch (e) {
      return AIResult.failure(
        '解析账单信息失败: $e',
        result.duration,
        metadata: result.metadata,
      );
    }
  }

  @override
  Future<double> estimateCost(AITask<String, BillInfo> task) =>
      baseProvider.estimateCost(_TextTask(task.input));

  /// 构建Prompt（由子类实现）
  String buildPrompt(String ocrText);

  /// 构建分类提示（公共方法）
  String buildCategoryHint() {
    if ((expenseCategories != null && expenseCategories!.isNotEmpty) ||
        (incomeCategories != null && incomeCategories!.isNotEmpty)) {
      final expenseHint = expenseCategories != null && expenseCategories!.isNotEmpty
          ? '支出分类：${expenseCategories!.join('、')}'
          : '';
      final incomeHint = incomeCategories != null && incomeCategories!.isNotEmpty
          ? '收入分类：${incomeCategories!.join('、')}'
          : '';

      return [expenseHint, incomeHint].where((s) => s.isNotEmpty).join('\n');
    } else {
      return '''
支出分类：餐饮、交通、购物、娱乐、居家、通讯、水电、医疗、教育等
收入分类：工资、理财、红包、奖金、报销、兼职等''';
    }
  }

  /// 构建账户提示（公共方法）
  String buildAccountHint() {
    if (accounts != null && accounts!.isNotEmpty) {
      return '\n用户的账户列表：\n${accounts!.join('、')}';
    }
    return '';
  }

  /// 解析GLM响应（公共方法）
  BillInfo parseResponse(String response) {
    // 提取JSON（可能包含```json包裹）
    final jsonMatch = RegExp(r'\{[\s\S]*?\}').firstMatch(response);
    if (jsonMatch == null) {
      throw Exception('响应中没有找到JSON: $response');
    }

    final jsonStr = jsonMatch.group(0)!;
    final json = jsonDecode(jsonStr) as Map<String, dynamic>;

    return BillInfo.fromJson(json);
  }
}

/// 内部文本任务（用于调用ZhipuGLMProvider）
class _TextTask extends AITask<String, String> {
  @override
  String get taskType => 'text_extraction';

  @override
  final String input;

  _TextTask(this.input);

  @override
  Map<String, dynamic> toJson() => {'input': input};
}
