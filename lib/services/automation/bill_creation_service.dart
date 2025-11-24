import 'package:shared_preferences/shared_preferences.dart';
import '../../data/db.dart';
import '../../data/repository.dart';
import '../../data/category_node.dart';
import '../logger_service.dart';
import 'category_matcher.dart';
import 'ocr_service.dart';

/// 账单创建服务
///
/// 提供统一的账单创建接口，供OCR手动扫描和自动记账使用
class BillCreationService {
  final BeeDatabase db;
  static const _tag = 'BillCreation';

  BillCreationService(this.db);

  /// 匹配分类
  ///
  /// 优先使用AI识别的分类名称，失败则降级到规则匹配
  /// 返回匹配的分类ID，如果都失败则返回null
  Future<int?> matchCategory(
    OcrResult result,
    List<Category> categories,
  ) async {
    // 1. 优先使用AI识别的分类
    if (result.aiCategoryName != null &&
        result.aiCategoryName!.isNotEmpty &&
        categories.isNotEmpty) {
      try {
        final matchedCategory = categories.firstWhere(
          (cat) => cat.name == result.aiCategoryName,
        );
        final transactionType = result.aiType ?? 'expense';
        logger.debug(_tag, '[分类匹配] AI分类"${result.aiCategoryName}"($transactionType) → ID:${matchedCategory.id}');
        return matchedCategory.id;
      } catch (_) {
        logger.debug(_tag, '[分类匹配] AI分类"${result.aiCategoryName}"未找到，降级使用规则匹配');
      }
    }

    // 2. 降级使用规则匹配
    if (categories.isNotEmpty) {
      return CategoryMatcher.smartMatch(
        merchant: result.merchant,
        fullText: result.rawText,
        categories: categories,
      );
    }

    return null;
  }

  /// 匹配账户
  ///
  /// 在账户功能启用的前提下，根据AI识别的账户名称匹配账户ID
  /// 只匹配与当前账本币种相同的账户
  /// [transactionType] 交易类型：'income' 或 'expense'，用于在未匹配时使用默认账户
  Future<int?> matchAccount(
    OcrResult result,
    int ledgerId, {
    String transactionType = 'expense',
  }) async {
    // 1. 检查账户功能是否启用
    final prefs = await SharedPreferences.getInstance();
    final accountFeatureEnabled = prefs.getBool('account_feature_enabled') ?? true;

    if (!accountFeatureEnabled) {
      logger.debug(_tag, '[账户匹配] 账户功能未启用，跳过匹配');
      return null;
    }

    // 2. 检查是否有AI识别的账户名称，如果没有则尝试使用默认账户
    if (result.aiAccountName == null || result.aiAccountName!.isEmpty) {
      logger.debug(_tag, '[账户匹配] AI未识别账户，尝试使用默认账户');
      return await _getDefaultAccountId(transactionType, ledgerId, prefs);
    }

    // 3. 获取账本信息以确定币种
    final ledger = await (db.select(db.ledgers)
          ..where((t) => t.id.equals(ledgerId)))
        .getSingleOrNull();

    if (ledger == null) {
      logger.debug(_tag, '[账户匹配] 账本不存在，跳过匹配');
      return null;
    }

    // 4. 查询与账本币种相同的所有账户
    final repository = BeeRepository(db);
    final allAccounts = await repository.getAllAccounts();
    final matchingAccounts = allAccounts
        .where((a) => a.currency == ledger.currency)
        .toList();

    // 5. 根据账户名称匹配（多级优先级匹配）
    final aiAccountName = result.aiAccountName!.toLowerCase().trim();

    // 第一优先级：名称完全相等（忽略大小写和空格）
    for (final account in matchingAccounts) {
      final accountNameLower = account.name.toLowerCase().trim();
      if (accountNameLower == aiAccountName) {
        logger.debug(_tag, '[账户匹配-完全] "${result.aiAccountName}" → ${account.name}(ID:${account.id})');
        return account.id;
      }
    }

    // 第二优先级：名称包含关系（模糊匹配）
    for (final account in matchingAccounts) {
      final accountNameLower = account.name.toLowerCase().trim();
      if (accountNameLower.contains(aiAccountName) ||
          aiAccountName.contains(accountNameLower)) {
        logger.debug(_tag, '[账户匹配-模糊] "${result.aiAccountName}" → ${account.name}(ID:${account.id})');
        return account.id;
      }
    }

    // 第三优先级：账户类型匹配
    final accountTypeMap = {
      '余额宝': ['支付宝', 'alipay'],
      '花呗': ['支付宝', 'alipay'],
      '微信支付': ['微信', 'wechat'],
      '微信钱包': ['微信', 'wechat'],
      '零钱': ['微信', 'wechat'],
      '零钱通': ['微信', 'wechat'],
    };

    final relatedTypes = accountTypeMap[aiAccountName] ?? [];
    if (relatedTypes.isNotEmpty) {
      for (final account in matchingAccounts) {
        final accountNameLower = account.name.toLowerCase().trim();
        for (final type in relatedTypes) {
          if (accountNameLower.contains(type.toLowerCase())) {
            logger.debug(_tag, '[账户匹配-类型] "${result.aiAccountName}" → ${account.name}(ID:${account.id})');
            return account.id;
          }
        }
      }
    }

    logger.debug(_tag, '[账户匹配] "${result.aiAccountName}"未匹配，尝试默认账户');
    return await _getDefaultAccountId(transactionType, ledgerId, prefs);
  }

  /// 获取默认账户ID（验证币种匹配）
  Future<int?> _getDefaultAccountId(String transactionType, int ledgerId, SharedPreferences prefs) async {
    try {
      // 1. 根据类型获取默认账户ID
      final defaultAccountId = transactionType == 'income'
          ? prefs.getInt('default_income_account_id')
          : prefs.getInt('default_expense_account_id');

      if (defaultAccountId == null) {
        logger.debug(_tag, '[默认账户] 未设置默认${transactionType == 'income' ? '收入' : '支出'}账户');
        return null;
      }

      // 2. 获取账本币种
      final ledger = await (db.select(db.ledgers)
            ..where((t) => t.id.equals(ledgerId)))
          .getSingleOrNull();
      if (ledger == null) return null;

      // 3. 获取默认账户信息
      final repository = BeeRepository(db);
      final account = await repository.getAccount(defaultAccountId);
      if (account == null) {
        logger.debug(_tag, '[默认账户] 账户不存在');
        return null;
      }

      // 4. 验证币种匹配
      if (account.currency != ledger.currency) {
        logger.debug(_tag, '[默认账户] 币种不匹配: ${account.currency} vs ${ledger.currency}');
        return null;
      }

      logger.debug(_tag, '[默认账户] 使用${transactionType == 'income' ? '收入' : '支出'}账户 → ${account.name}(ID:${account.id})');
      return defaultAccountId;
    } catch (e) {
      logger.error(_tag, '[默认账户] 获取失败', e);
      return null;
    }
  }

  /// 创建账单交易
  ///
  /// [result] OCR识别结果（包含AI增强）
  /// [ledgerId] 账本ID
  /// [note] 备注（可选）
  /// 返回创建的交易ID，如果创建失败则返回null
  Future<int?> createBillTransaction({
    required OcrResult result,
    required int ledgerId,
    String? note,
  }) async {
    // 1. 验证金额
    if (result.amount == null || result.amount!.abs() <= 0) {
      return null;
    }

    // 2. 确定交易类型
    // 优先级：AI识别类型 > 金额正负推断 > 默认支出
    String transactionType;
    if (result.aiType != null && result.aiType!.isNotEmpty) {
      transactionType = result.aiType!;
    } else if (result.amount! > 0) {
      transactionType = 'income';
    } else {
      transactionType = 'expense';
    }

    // 3. 查询对应类型的所有分类
    final allCategories = await (db.select(db.categories)
          ..where((t) => t.kind.equals(transactionType)))
        .get();

    // 3.1 过滤出可用于记账的分类（排除有子分类的父分类）
    final categories = CategoryHierarchy.getUsableCategories(allCategories);

    // 4. 匹配分类
    int? categoryId = await matchCategory(result, categories);

    // 4.1 如果没有匹配到分类，尝试使用"其他"分类作为兜底
    if (categoryId == null && categories.isNotEmpty) {
      categoryId = await _getFallbackCategoryId(categories, transactionType);
    }

    // 5. 匹配账户（在账户功能启用的前提下，未匹配时使用默认账户）
    final accountId = await matchAccount(result, ledgerId, transactionType: transactionType);

    // 6. 确定交易时间（优先使用识别的时间，否则使用当前时间）
    final DateTime happenedAt = result.time ?? DateTime.now();

    // 7. 获取分类和账户名称（用于日志）
    String? categoryName;
    String? accountName;
    if (categoryId != null) {
      final category = categories.where((c) => c.id == categoryId).firstOrNull;
      categoryName = category?.name;
    }
    if (accountId != null) {
      final repository = BeeRepository(db);
      final account = await repository.getAccount(accountId);
      accountName = account?.name;
    }

    // 8. 使用Repository创建交易
    final repository = BeeRepository(db);
    final finalAmount = result.amount!.abs();
    final transactionId = await repository.addTransaction(
      ledgerId: ledgerId,
      type: transactionType,
      amount: finalAmount,
      categoryId: categoryId,
      accountId: accountId,
      happenedAt: happenedAt,
      note: note,
    );

    // 9. 打印最终交易信息汇总（一行）
    final typeStr = transactionType == 'income' ? '收入' : '支出';
    final timeStr = _formatDateTime(happenedAt);
    final categoryStr = categoryName ?? '未设置';
    final accountStr = accountName ?? '未设置';
    final noteStr = note ?? '无';

    logger.info(_tag, '[自动记账] 成功 | ID:$transactionId | $finalAmount元 | $typeStr | 分类:$categoryStr | 账户:$accountStr | 时间:$timeStr | 备注:$noteStr');

    return transactionId;
  }

  /// 格式化日期时间
  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
           '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  /// 获取兜底分类ID
  /// 优先使用"其他"分类，如果没有则使用第一个分类
  Future<int?> _getFallbackCategoryId(List<Category> categories, String transactionType) async {
    if (categories.isEmpty) return null;

    // 尝试查找"其他"分类（支持多种命名方式）
    final otherKeywords = ['其他', 'other', '其它', '杂项', 'misc'];
    for (final keyword in otherKeywords) {
      final otherCategory = categories.where(
        (c) => c.name.toLowerCase().contains(keyword.toLowerCase())
      ).firstOrNull;
      if (otherCategory != null) {
        logger.debug(_tag, '[分类兜底] 使用"${otherCategory.name}"(ID:${otherCategory.id})');
        return otherCategory.id;
      }
    }

    // 如果没有"其他"分类，使用排序最后的分类
    final lastCategory = categories.last;
    logger.debug(_tag, '[分类兜底] 使用"${lastCategory.name}"(ID:${lastCategory.id})');
    return lastCategory.id;
  }

  /// 获取分类列表（按类型）
  ///
  /// [type] 'income' 或 'expense'
  Future<List<Category>> getCategoriesByType(String type) async {
    return await (db.select(db.categories)..where((t) => t.kind.equals(type)))
        .get();
  }
}
