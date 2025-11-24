import 'package:flutter_ai_kit_zhipu/flutter_ai_kit_zhipu.dart';
import 'bill_extraction_glm_base_provider.dart';

/// 账单提取专用GLM Provider（文本模型）
///
/// 使用GLM-4.6文本模型进行账单信息提取
class BillExtractionGLMProvider extends BillExtractionGLMBaseProvider {
  BillExtractionGLMProvider(
    String apiKey, {
    super.expenseCategories,
    super.incomeCategories,
    super.accounts,
  }) : super(
          baseProvider: ZhipuGLMProvider(
            apiKey: apiKey,
            model: 'glm-4.6', // 使用GLM-4.6模型
          ),
        );

  @override
  String get id => 'bill_extraction_glm';

  @override
  String get name => '智谱GLM-账单提取';

  @override
  String buildPrompt(String ocrText) {
    final categoryHint = buildCategoryHint();
    final accountHint = buildAccountHint();

    return '''
从以下支付账单文本中提取信息，返回JSON格式。

账单文本：
$ocrText

用户的分类列表：
$categoryHint$accountHint

要求：
1. amount: 实际支付金额（数字，支出为负数，收入为正数）
   - 优先选择带负号的金额（如-14.93）
   - 如果有"订单金额"和"实付款"，选择实付款
   - 忽略优惠券、红包等金额
2. time: 支付时间（ISO8601格式，如"2025-11-08T14:30:00"）
   - 查找"支付时间"、"交易时间"、"付款时间"等字段
   - 重要：如果文本中没有明确的时间信息，必须设置为null，绝对不要编造时间
3. merchant: 收款方全称或商家名称
   - 优先使用"收款方全称"字段
   - 避免使用优惠券名称（如"晚餐到店红包"）
4. category: 从上述分类列表中选择最匹配的一个（必须完全匹配用户的分类名称）
   - 根据商家名称和交易描述判断
   - 例如：停车场→停车，餐厅→餐饮，超市→购物
5. type: 类型（income 或 expense）
6. account: 支付账户名称（可选）
   - 识别"支付方式"、"付款方式"、"账户"等字段
   - 如果用户有账户列表，必须从列表中选择最匹配的一个（完全匹配账户名称）
   - 如果没有账户列表或无法匹配，可以识别常见账户：微信支付、支付宝、银行卡、现金、信用卡等
   - 提取实际账户名称，不要包含多余描述

示例输出：
{
  "amount": -14.93,
  "time": "2025-11-05T17:05:39",
  "merchant": "杭州西溪湿地运营管理有限公司",
  "category": "停车",
  "type": "expense",
  "account": "支付宝"
}

注意：
- 只返回JSON，不要其他文字
- 如果无法提取某个字段，设置为null
- category必须从上述分类列表中选择，支出选支出分类，收入选收入分类
- 支出金额为负数，收入金额为正数
- 优先使用准确的字段名称（如"收款方全称"），而不是模糊的描述
- account字段提取支付账户名称，如"支付宝"、"微信支付"、"招商银行卡"等
''';
  }
}
