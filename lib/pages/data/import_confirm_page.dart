import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:drift/drift.dart' as d;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers.dart';
import '../../widgets/ui/ui.dart';
import '../../data/db.dart' as schema;
import '../../l10n/app_localizations.dart';
import '../../services/import/csv_parser.dart';
import '../../utils/category_utils.dart';
import '../../services/import/bill_parser.dart';
import '../../services/import/parsers/generic_parser.dart';
import '../../services/import/parsers/alipay_parser.dart';
import '../../services/import/parsers/wechat_parser.dart';
import '../../utils/date_parser.dart';
import '../../styles/tokens.dart';
import 'import_page.dart';

class ImportConfirmPage extends ConsumerStatefulWidget {
  final String csvText;
  final bool hasHeader;
  final BillSourceType billType;
  const ImportConfirmPage({
    super.key,
    required this.csvText,
    required this.hasHeader,
    required this.billType,
  });

  @override
  ConsumerState<ImportConfirmPage> createState() => _ImportConfirmPageState();
}

class _ImportConfirmPageState extends ConsumerState<ImportConfirmPage> {
  List<List<String>> rows = const [];
  bool parsing = true;
  // 自动识别到的表头所在行（仅当 hasHeader 为 true 时使用）
  int headerRow = 0;
  final Map<String, int?> mapping = {
    'date': null,
    'type': null,
    'amount': null,
    'category': null,
    'sub_category': null,       // 二级分类
    'category_icon': null,       // 分类图标
    'sub_category_icon': null,   // 二级分类图标
    'account': null,
    'from_account': null,
    'to_account': null,
    'note': null,
  };
  bool importing = false;
  int ok = 0, fail = 0, skipped = 0; // skipped: 跳过的非收支类型记录
  int step = 0; // 0: 字段映射, 1: 分类映射
  bool _cancelled = false;
  List<String> distinctCategories = [];
  Map<String, int?> categoryMapping = {}; // 源分类名 -> 目标分类ID（null表示保持原名）
  Future<List<schema.Category>>? allCategoriesFuture;
  late final BillParser _billParser;

  @override
  void initState() {
    super.initState();
    // 根据账单类型选择解析器
    _billParser = _getParser(widget.billType);

    // 解析在后台 isolate 完成，避免主线程卡顿
    () async {
      final parsed = await compute(_parseRowsIsolate, widget.csvText);
      if (!mounted) return;
      setState(() {
        rows = parsed;
        parsing = false;
      });
      // 解析完成
      // 使用解析器查找表头
      if (widget.hasHeader && rows.isNotEmpty) {
        headerRow = _billParser.findHeaderRow(rows);
        if (headerRow < 0) headerRow = 0; // 兜底
      }
      _autoDetectMapping();
      // 预取分类列表供第二步选择
      allCategoriesFuture = _loadAllCategories(ref);
    }();
  }

  /// 根据账单类型获取解析器
  BillParser _getParser(BillSourceType type) {
    switch (type) {
      case BillSourceType.generic:
        return GenericBillParser();
      case BillSourceType.alipay:
        return AlipayBillParser();
      case BillSourceType.wechat:
        return WechatBillParser();
    }
  }

  void _autoDetectMapping() {
    if (rows.isEmpty || !widget.hasHeader) return;
    final headers = rows[headerRow].map((e) => e.toString().trim()).toList();

    // 使用解析器的列映射功能
    final detectedMapping = _billParser.mapColumns(headers);

    // 更新 mapping
    detectedMapping.forEach((key, index) {
      if (mapping.containsKey(key)) {
        mapping[key] = index;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (parsing) {
      return Scaffold(
        body: Column(
          children: [
            PrimaryHeader(
                title: AppLocalizations.of(context).importPreparing,
                showBack: true),
            Expanded(
              child: Center(
                child: CircularProgressIndicator(),
              ),
            )
          ],
        ),
      );
    }
    final columnCount =
        rows.isNotEmpty ? rows[widget.hasHeader ? headerRow : 0].length : 0;
    List<DropdownMenuItem<int>> items() => List.generate(columnCount, (i) {
          final header = widget.hasHeader
              ? rows[headerRow]
              : (rows.isNotEmpty ? rows.first : const <String>[]);
          final label = (widget.hasHeader &&
                  i < header.length &&
                  header[i].trim().isNotEmpty)
              ? header[i].trim()
              : AppLocalizations.of(context).importColumnNumber(i + 1);
          return DropdownMenuItem(
              value: i, child: Text(label, overflow: TextOverflow.ellipsis));
        });

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PrimaryHeader(
              title: step == 0
                  ? AppLocalizations.of(context).importConfirmMapping
                  : AppLocalizations.of(context).importCategoryMapping,
              showBack: true),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                if (step == 0) ...[
                  if (rows.isEmpty)
                    Text(AppLocalizations.of(context).importNoDataParsed),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _mapRow(AppLocalizations.of(context).importFieldDate,
                          'date', items()),
                      _mapRow(AppLocalizations.of(context).importFieldType,
                          'type', items()),
                      _mapRow(AppLocalizations.of(context).importFieldAmount,
                          'amount', items()),
                      _mapRow(AppLocalizations.of(context).importFieldCategory,
                          'category', items()),
                      _mapRow(AppLocalizations.of(context).exportCsvHeaderSubCategory,
                          'sub_category', items()),
                      _mapRow(AppLocalizations.of(context).exportCsvHeaderCategoryIcon,
                          'category_icon', items()),
                      _mapRow(AppLocalizations.of(context).exportCsvHeaderSubCategoryIcon,
                          'sub_category_icon', items()),
                      _mapRow(AppLocalizations.of(context).importFieldAccount,
                          'account', items()),
                      _mapRow(AppLocalizations.of(context).exportCsvHeaderFromAccount,
                          'from_account', items()),
                      _mapRow(AppLocalizations.of(context).exportCsvHeaderToAccount,
                          'to_account', items()),
                      _mapRow(AppLocalizations.of(context).importFieldNote,
                          'note', items()),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 预览仅展示前 N 行，避免大文件一次性渲染导致卡顿
                  Text(AppLocalizations.of(context).importPreview,
                      style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 6),
                  SizedBox(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Builder(builder: (_) {
                        const int maxPreview = 10; // 预览最多 100 行
                        final totalRows = rows.length;
                        final dataStart =
                            widget.hasHeader ? (headerRow + 1) : 0;
                        // 保证包含表头行 + 最多 maxPreview-1 行数据
                        final header = widget.hasHeader
                            ? [rows[headerRow]]
                            : <List<String>>[];
                        final body = totalRows > dataStart
                            ? () {
                                final take = (maxPreview - header.length);
                                final end = (dataStart + take <= totalRows)
                                    ? dataStart + take
                                    : totalRows;
                                return rows.sublist(dataStart, end);
                              }()
                            : const <List<String>>[];
                        final limited = [...header, ...body];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _PreviewTable(rows: limited),
                            if (totalRows > limited.length)
                              Padding(
                                padding: const EdgeInsets.only(top: 6.0),
                                child: Text(
                                  AppLocalizations.of(context)
                                      .importPreviewLimit(
                                          limited.length, totalRows),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: BeeTokens.textTertiary(context)),
                                ),
                              ),
                          ],
                        );
                      }),
                    ),
                  ),
                ] else ...[
                  if (mapping['category'] == null)
                    Text(AppLocalizations.of(context)
                        .importCategoryNotSelected),
                  Text(AppLocalizations.of(context)
                      .importCategoryMappingDescription),
                  const SizedBox(height: 8),
                  FutureBuilder<List<schema.Category>>(
                    future: allCategoriesFuture,
                    builder: (context, snap) {
                      final cats = snap.data ?? [];
                      final l10n = AppLocalizations.of(context);
                      final items = <DropdownMenuItem<int?>>[
                        DropdownMenuItem(
                            value: null,
                            child: Text(l10n.importKeepOriginalName)),
                        ...cats.map((c) => DropdownMenuItem<int?>(
                              value: c.id,
                              child: Text(
                                  '${CategoryUtils.getDisplayName(c.name, context, kind: c.kind)} (${c.kind == 'income' ? l10n.categoryIncome : l10n.categoryExpense})'),
                            )),
                      ];
                      // 为每个源分类预设自动匹配（仅在首次加载时执行）
                      if (categoryMapping.values.every((v) => v == null) &&
                          cats.isNotEmpty) {
                        bool hasMatch = false;
                        for (final sourceName in distinctCategories) {
                          // 直接使用源分类名称查找匹配
                          try {
                            final matchingCategory = cats.firstWhere(
                              (c) => c.name == sourceName,
                            );
                            categoryMapping[sourceName] = matchingCategory.id;
                            hasMatch = true;
                          } catch (e) {
                            // 没有找到匹配的分类，保持为null
                          }
                        }
                        // 如果有自动匹配，触发重建以显示预设的匹配
                        if (hasMatch) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) setState(() {});
                          });
                        }
                      }

                      return Column(
                        children: [
                          for (final name in distinctCategories)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  Expanded(
                                      child: Text(name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis)),
                                  const SizedBox(width: 12),
                                  DropdownButton<int?>(
                                    value: categoryMapping[name],
                                    items: items,
                                    onChanged: (v) => setState(
                                        () => categoryMapping[name] = v),
                                  ),
                                ],
                              ),
                            )
                        ],
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  if (importing)
                    Text(
                        AppLocalizations.of(context).importProgress(ok, fail)),
                  const Spacer(),
                  if (step == 0)
                    FilledButton(
                      onPressed: () {
                        // 检查是否有分类列映射
                        // 如果没有分类列，说明可能只有转账记录，跳过分类映射步骤，直接开始导入
                        if (mapping['category'] == null) {
                          // 如果没有分类列但有转账相关列，则直接开始导入
                          if (mapping['from_account'] != null || mapping['to_account'] != null) {
                            _startImport();
                          } else {
                            showToast(
                                context,
                                AppLocalizations.of(context)
                                    .importSelectCategoryFirst);
                          }
                          return;
                        }
                        _buildDistinctCategories();
                        setState(() => step = 1);
                      },
                      child: Text(AppLocalizations.of(context).importNextStep),
                    )
                  else ...[
                    OutlinedButton(
                      onPressed:
                          importing ? null : () => setState(() => step = 0),
                      child: Text(
                          AppLocalizations.of(context).importPreviousStep),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: importing ? null : _startImport,
                      child:
                          Text(AppLocalizations.of(context).importStartImport),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapRow(String label, String key, List<DropdownMenuItem<int>> items) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 64, child: Text(label)),
        const SizedBox(width: 8),
        SizedBox(
          width: 220,
          child: DropdownButton<int>(
            isExpanded: true,
            value: mapping[key],
            hint: Text(AppLocalizations.of(context).importAutoDetect),
            items: items,
            onChanged: (v) => setState(() => mapping[key] = v),
          ),
        ),
      ],
    );
  }

  Future<void> _startImport() async {
    // 使用根容器，保证页面被销毁后仍可更新全局进度供"我的"页展示
    final container = ProviderScope.containerOf(context, listen: false);
    final currentContext = context;
    setState(() {
      importing = true;
      ok = 0;
      fail = 0;
    });
    final repo = ref.read(repositoryProvider);
    final ledgerId = ref.read(currentLedgerIdProvider);

    // v1.15.0: 获取当前账本的币种信息
    final currentLedger = await (repo.db.select(repo.db.ledgers)
          ..where((l) => l.id.equals(ledgerId)))
        .getSingleOrNull();
    final ledgerCurrency = currentLedger?.currency ?? 'CNY';

    final dataStart = widget.hasHeader ? (headerRow + 1) : 0;
    final total = rows.length - dataStart;
    // 初始化全局进度
    container.read(importProgressProvider.notifier).state = ImportProgress(
      running: true,
      total: total,
      done: 0,
      ok: 0,
      fail: 0,
    );

    bool dialogOpen = true;
    // 进度弹窗（可转后台）
    showDialog(
      context: currentContext,
      barrierDismissible: false,
      builder: (dctx) {
        return Consumer(builder: (dctx, r, _) {
          final p = r.watch(importProgressProvider);
          final percent =
              p.total == 0 ? 0.0 : (p.done / p.total).clamp(0.0, 1.0);
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Text(AppLocalizations.of(context).importInProgress),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                    value: percent > 0 && percent < 1 ? percent : null),
                const SizedBox(height: 8),
                // 实时进度文案（每50条更新一次，足够流畅）
                Text(
                    AppLocalizations.of(context)
                        .importProgressDetail(p.done, p.fail, p.ok, p.total),
                    style: Theme.of(dctx)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: BeeTokens.textTertiary(context))),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  dialogOpen = false;
                  Navigator.of(dctx).pop();
                  // 返回到数据管理页面继续后台导入
                  if (mounted) {
                    // Pop回DataManagementPage: ImportConfirmPage -> ImportPage
                    Navigator.of(currentContext).pop(); // Close ImportConfirmPage
                    Navigator.of(currentContext).pop(); // Close ImportPage, back to DataManagementPage
                  }
                },
                child:
                    Text(AppLocalizations.of(context).importBackgroundImport),
              ),
              TextButton(
                onPressed: () {
                  _cancelled = true;
                  dialogOpen = false;
                  Navigator.of(dctx).pop();
                },
                child: Text(AppLocalizations.of(context).importCancelImport),
              ),
            ],
          );
        });
      },
    );

    // 第一步：提取所有唯一账户名并批量创建账户（在事务中）
    final accountIdx = mapping['account'];
    final fromAccountIdx = mapping['from_account'];
    final toAccountIdx = mapping['to_account'];
    final Set<String> uniqueAccountNames = {};

    // 收集普通账户名
    if (accountIdx != null) {
      for (int i = dataStart; i < rows.length; i++) {
        final r = rows[i];
        if (accountIdx < r.length) {
          final accountName = r[accountIdx].toString().trim();
          if (accountName.isNotEmpty) {
            uniqueAccountNames.add(accountName);
          }
        }
      }
    }

    // 收集转出账户名
    if (fromAccountIdx != null) {
      for (int i = dataStart; i < rows.length; i++) {
        final r = rows[i];
        if (fromAccountIdx < r.length) {
          final accountName = r[fromAccountIdx].toString().trim();
          if (accountName.isNotEmpty) {
            uniqueAccountNames.add(accountName);
          }
        }
      }
    }

    // 收集转入账户名
    if (toAccountIdx != null) {
      for (int i = dataStart; i < rows.length; i++) {
        final r = rows[i];
        if (toAccountIdx < r.length) {
          final accountName = r[toAccountIdx].toString().trim();
          if (accountName.isNotEmpty) {
            uniqueAccountNames.add(accountName);
          }
        }
      }
    }

    // 账户名到ID的映射
    final Map<String, int> accountNameToId = {};

    // 定义进度变量（需要在事务外部，以便后续访问）
    int done = 0;

    // 收集跳过的类型（用于提示用户）
    final Map<String, int> skippedTypes = {};

    try {
      // 使用事务确保账户创建和记录导入的原子性
      await repo.db.transaction(() async {
        // 步骤1：批量创建账户
        if (uniqueAccountNames.isNotEmpty) {
          for (final accountName in uniqueAccountNames) {
            if (_cancelled) break;
            try {
              // v1.15.0: 全局按名称去重检查（不限定账本）
              final existing = await (repo.db.select(repo.db.accounts)
                    ..where((a) => a.name.equals(accountName)))
                  .getSingleOrNull();

              if (existing != null) {
                accountNameToId[accountName] = existing.id;
              } else {
                // v1.15.0: 创建新账户（继承账本币种，不绑定账本ID）
                final accountId = await repo.db.into(repo.db.accounts).insert(
                      schema.AccountsCompanion.insert(
                        ledgerId: 0, // v1.15.0: 账户独立，不绑定账本
                        name: accountName,
                        currency: d.Value(ledgerCurrency), // v1.15.0: 从账本继承币种
                        initialBalance: const d.Value(0.0), // 初始余额为0
                      ),
                    );
                accountNameToId[accountName] = accountId;
              }
            } catch (e) {
              // 账户创建失败，继续处理其他账户
              print('Failed to create account: $accountName, $e');
            }
          }
        }

        // 步骤2：批量创建分类
        // 收集所有需要创建的分类信息（一级和二级）
        final Map<String, ({String kind, String? icon, String? parentName})> categoriesToCreate = {};

        for (int i = dataStart; i < rows.length; i++) {
          if (_cancelled) break;
          final r = rows[i];
          try {
            String? getBy(String key) {
              final userIdx = mapping[key];
              if (userIdx != null && userIdx >= 0 && userIdx < r.length) {
                final val = r[userIdx].toString().trim();
                return val.isNotEmpty ? val : null;
              }
              return null;
            }

            var typeRaw = getBy('type') ?? 'expense';
            final typeStr = typeRaw.trim().toLowerCase();

            String? type;
            if (typeStr == '收入' || typeStr == '收' || typeStr == '入账' || typeStr == '进账' ||
                typeStr == 'income' || typeStr == 'revenue' || typeStr == 'earning') {
              type = 'income';
            } else if (typeStr == '支出' || typeStr == '支' || typeStr == '出账' ||
                       typeStr == '消费' || typeStr == '花费' ||
                       typeStr == 'expense' || typeStr == 'spending' || typeStr == 'expenditure') {
              type = 'expense';
            } else if (typeStr == '转账' || typeStr == 'transfer') {
              continue; // 转账没有分类
            } else {
              continue; // 未识别类型
            }

            final categoryName = getBy('category');
            final subCategoryName = getBy('sub_category');
            final categoryIcon = getBy('category_icon');
            final subCategoryIcon = getBy('sub_category_icon');

            // 如果有二级分类，说明分类列是一级分类名称
            if (subCategoryName != null && categoryName != null) {
              // 记录一级分类（如果还没记录）
              final parentKey = '$categoryName:$type';
              if (!categoriesToCreate.containsKey(parentKey)) {
                categoriesToCreate[parentKey] = (
                  kind: type,
                  icon: categoryIcon,
                  parentName: null,
                );
              }

              // 记录二级分类
              final subKey = '$subCategoryName:$type:$categoryName';
              if (!categoriesToCreate.containsKey(subKey)) {
                categoriesToCreate[subKey] = (
                  kind: type,
                  icon: subCategoryIcon,
                  parentName: categoryName,
                );
              }
            } else if (categoryName != null) {
              // 只有一级分类
              final key = '$categoryName:$type';
              if (!categoriesToCreate.containsKey(key)) {
                categoriesToCreate[key] = (
                  kind: type,
                  icon: categoryIcon,
                  parentName: null,
                );
              }
            }
          } catch (_) {}
        }

        // 批量创建分类（先创建一级，再创建二级）
        final Map<String, int> categoryCache = {}; // (name:kind) -> id 或 (name:kind:parent) -> id

        // 第一遍：创建所有一级分类
        for (final entry in categoriesToCreate.entries) {
          if (_cancelled) break;
          final info = entry.value;
          if (info.parentName == null) {
            // 一级分类
            final key = entry.key;
            final parts = key.split(':');
            final name = parts[0];
            final kind = parts[1];

            try {
              // 检查是否已存在
              final existing = await (repo.db.select(repo.db.categories)
                    ..where((c) => c.name.equals(name) & c.kind.equals(kind) & c.level.equals(1)))
                  .getSingleOrNull();

              if (existing != null) {
                categoryCache[key] = existing.id;
              } else {
                // 创建新的一级分类
                final id = await repo.db.into(repo.db.categories).insert(
                  schema.CategoriesCompanion.insert(
                    name: name,
                    kind: kind,
                    level: const d.Value(1),
                    icon: d.Value(info.icon),
                  ),
                );
                categoryCache[key] = id;
              }
            } catch (e) {
              print('Failed to create category: $name, $e');
            }
          }
        }

        // 第二遍：创建所有二级分类
        for (final entry in categoriesToCreate.entries) {
          if (_cancelled) break;
          final info = entry.value;
          if (info.parentName != null) {
            // 二级分类
            final key = entry.key;
            final parts = key.split(':');
            final name = parts[0];
            final kind = parts[1];
            final parentName = parts[2];

            // 查找父分类ID
            final parentKey = '$parentName:$kind';
            final parentId = categoryCache[parentKey];

            if (parentId == null) {
              print('Parent category not found: $parentName');
              continue;
            }

            try {
              // 检查是否已存在
              final existing = await (repo.db.select(repo.db.categories)
                    ..where((c) =>
                      c.name.equals(name) &
                      c.kind.equals(kind) &
                      c.level.equals(2) &
                      c.parentId.equals(parentId)))
                  .getSingleOrNull();

              if (existing != null) {
                categoryCache[key] = existing.id;
              } else {
                // 创建新的二级分类
                final id = await repo.db.into(repo.db.categories).insert(
                  schema.CategoriesCompanion.insert(
                    name: name,
                    kind: kind,
                    level: const d.Value(2),
                    parentId: d.Value(parentId),
                    icon: d.Value(info.icon),
                  ),
                );
                categoryCache[key] = id;
              }
            } catch (e) {
              print('Failed to create subcategory: $name, $e');
            }
          }
        }

        // 步骤3：批量导入记录
        // 分类缓存：当选择"保持原名"时，按 (name, kind) 维度缓存 upsert 结果，避免重复查询
        final Map<String, int> incomeCatCache = {};
        final Map<String, int> expenseCatCache = {};
        // 批量缓冲
        const int batchSize = 500;
        final List<schema.TransactionsCompanion> batch = [];

        Future<void> flushBatch() async {
          if (batch.isEmpty) return;
          try {
            final inserted = await repo.insertTransactionsBatch(batch);
            ok += inserted;
          } catch (_) {
            // 回退到逐条插入，尽可能保留成功数
            for (final item in batch) {
              if (_cancelled) break;
              try {
                await repo.db.into(repo.db.transactions).insert(item);
                ok++;
              } catch (_) {
                fail++;
              }
            }
          } finally {
            batch.clear();
            // 批次完成后更新一次进度
            container.read(importProgressProvider.notifier).state =
                ImportProgress(
                    running: true, total: total, done: done, ok: ok, fail: fail);
            await Future<void>.delayed(Duration.zero);
            if (mounted) setState(() {});
          }
        }

    for (int i = dataStart; i < rows.length; i++) {
      if (_cancelled) break;
      final r = rows[i];
      try {
        String? getBy(String key, int fallback) {
          final userIdx = mapping[key];
          if (userIdx != null && userIdx >= 0 && userIdx < r.length) {
            return r[userIdx].toString();
          }
          return fallback < r.length ? r[fallback].toString() : null;
        }

        final dateStr = getBy('date', 0);
        var typeRaw = getBy('type', 1) ?? 'expense';
        final amountStr = getBy('amount', 2);
        final categoryName = getBy('category', 3);
        final subCategoryName = getBy('sub_category', 999);
        final accountName = getBy('account', 999); // 使用不存在的fallback，确保只从映射列获取
        final fromAccountName = getBy('from_account', 999); // 转出账户
        final toAccountName = getBy('to_account', 999); // 转入账户
        final note = getBy('note', 4);

        // 类型识别：精准匹配收入/支出/转账，其他类型跳过
        final typeStr = typeRaw.trim();
        final lower = typeStr.toLowerCase();

        String? type;

        // 精准匹配收入
        if (lower == '收入' || lower == '收' || lower == '入账' || lower == '进账' ||
            lower == 'income' || lower == 'revenue' || lower == 'earning') {
          type = 'income';
        }
        // 精准匹配支出
        else if (lower == '支出' || lower == '支' || lower == '出账' ||
                 lower == '消费' || lower == '花费' ||
                 lower == 'expense' || lower == 'spending' || lower == 'expenditure') {
          type = 'expense';
        }
        // 精准匹配转账
        else if (lower == '转账' || lower == 'transfer') {
          type = 'transfer';
        }
        // 未识别的类型：跳过（债务等非收支记录）
        else {
          skipped++;
          skippedTypes[typeStr] = (skippedTypes[typeStr] ?? 0) + 1;
          continue;
        }

        // 金额解析（过滤正负号，统一使用绝对值）
        final amountClean =
            (amountStr ?? '0').toString().replaceAll(RegExp(r'[¥$,+-]'), '');
        final amount = double.parse(amountClean).abs();

        // 日期解析 - 使用通用日期解析工具
        final date = DateParser.parse(dateStr);

        int? categoryId;
        // 优先使用二级分类，如果没有则使用一级分类
        if (subCategoryName != null && subCategoryName.trim().isNotEmpty &&
            categoryName != null && categoryName.trim().isNotEmpty) {
          // 有二级分类：从缓存中查找
          final key = '${subCategoryName.trim()}:$type:${categoryName.trim()}';
          categoryId = categoryCache[key];
        } else if (categoryName != null && categoryName.trim().isNotEmpty) {
          // 只有一级分类
          final originalName = categoryName.trim();
          final chosen = categoryMapping[originalName];
          if (chosen != null) {
            categoryId = chosen;
          } else {
            // 先从缓存查找
            final key = '$originalName:$type';
            categoryId = categoryCache[key];

            if (categoryId == null) {
              // 缓存中没有，使用原有的 upsertCategory 逻辑
              final name = originalName;

              if (type == 'income') {
                final cached = incomeCatCache[name];
                if (cached != null) {
                  categoryId = cached;
                } else {
                  final id = await repo.upsertCategory(name: name, kind: 'income');
                  incomeCatCache[name] = id;
                  categoryId = id;
                }
              } else {
                final cached = expenseCatCache[name];
                if (cached != null) {
                  categoryId = cached;
                } else {
                  final id = await repo.upsertCategory(name: name, kind: 'expense');
                  expenseCatCache[name] = id;
                  categoryId = id;
                }
              }
            }
          }
        }

        // 处理账户ID和转账逻辑
        int? accountId;
        int? toAccountId;

        if (type == 'transfer') {
          // 转账类型：使用 from_account 和 to_account
          if (fromAccountName != null && fromAccountName.trim().isNotEmpty) {
            accountId = accountNameToId[fromAccountName.trim()];
          }
          if (toAccountName != null && toAccountName.trim().isNotEmpty) {
            toAccountId = accountNameToId[toAccountName.trim()];
          }

          // 转账必须有转出和转入账户，否则跳过此记录
          if (accountId == null || toAccountId == null) {
            fail++;
            continue;
          }
        } else {
          // 收入或支出：使用普通 account 字段
          if (accountName != null && accountName.trim().isNotEmpty) {
            accountId = accountNameToId[accountName.trim()];
          }
          toAccountId = null;
        }

        // 构造行
        final item = schema.TransactionsCompanion.insert(
          ledgerId: ledgerId,
          type: type,
          amount: amount,
          categoryId: d.Value(type == 'transfer' ? null : categoryId), // 转账没有分类
          accountId: d.Value(accountId),
          toAccountId: d.Value(toAccountId),
          happenedAt: d.Value(date),
          note: d.Value(note),
        );
        batch.add(item);
      } catch (_) {
        fail++;
      }
      done++;

      // 达到批量阈值则落库一次
      if (batch.length >= batchSize) {
        await flushBatch();
        // 当文件巨大时，主动让出一帧，避免 UI 卡顿
        await Future<void>.delayed(Duration.zero);
      }
      // 降低频率的进度更新（不依赖落库）
      if (done % 50 == 0 || done == total || _cancelled) {
        container.read(importProgressProvider.notifier).state = ImportProgress(
            running: true, total: total, done: done, ok: ok, fail: fail);
        await Future<void>.delayed(Duration.zero);
        if (mounted) setState(() {});
      }
    }

        // 刷新剩余缓冲
        await flushBatch();
      }); // 结束事务
    } catch (e) {
      // 事务失败，全部回滚
      if (mounted) {
        showToast(context, AppLocalizations.of(context).importTransactionFailed('$e'));
      }
      fail = total - ok; // 更新失败数
    }

    // 即使页面已被关闭（mounted=false），也要继续更新全局进度供"我的"页展示
    // 先切换为"完成"以驱动 UI 展示成功动画/提示（不等待云上传）
    try {
      container.read(importProgressProvider.notifier).state = ImportProgress(
        running: false,
        total: total,
        done: done,
        ok: ok,
        fail: fail,
        ledgerId: ledgerId, // 设置账本ID，用于触发账本列表页面刷新
        skipped: skipped, // 跳过的记录数
        skippedTypes: skippedTypes, // 跳过的类型及数量
      );
    } catch (e) {}

    // 延迟清空和刷新（不依赖页面状态，即使页面销毁也要执行）
    if (!_cancelled) {
      Future<void>.delayed(const Duration(seconds: 5), () {
        // 延长到5秒，让用户看到动画
        try {
          container.read(importProgressProvider.notifier).state =
              ImportProgress.empty;
          // 刷新"我的"页统计（笔数/天数）
          container.invalidate(countsForLedgerProvider(ledgerId));
          // 触发全局统计刷新（用于"我的"页顶部聚合信息）
          container.read(statsRefreshProvider.notifier).state++;
          // 触发一次同步状态刷新（UI 端会复用缓存避免闪烁）
          container.read(syncStatusRefreshProvider.notifier).state++;
        } catch (e) {}
      });
    }

    // Check if context is still mounted for UI operations
    if (!currentContext.mounted) {
      return;
    }

    // 显示导入完成提示
    final cancelledText =
        _cancelled ? AppLocalizations.of(currentContext).importCancelled : '';
    final l10nToast = AppLocalizations.of(currentContext);

    // 构建提示信息
    String message = l10nToast.importCompleted(cancelledText, fail, ok);
    bool hasSkipped = skipped > 0;

    if (hasSkipped) {
      // 构建跳过类型列表
      final skippedList = skippedTypes.entries
          .map((e) => '${e.key}(${e.value})')
          .join('、');
      message += '\n${l10nToast.importSkippedNonTransactionTypes(skipped)}\n$skippedList';
    }

    // Handle UI operations before cloud upload
    if (dialogOpen) {
      Navigator.of(currentContext).pop();
    }

    // 判断显示方式: 完全成功用toast,有失败或跳过用弹窗
    if (fail == 0 && !hasSkipped) {
      // 完全成功: 使用toast,然后关闭页面
      showToast(currentContext, message);
      // 关闭确认页 -> 返回到数据管理页面
      // Pop回DataManagementPage: ImportConfirmPage -> ImportPage
      Navigator.of(currentContext).pop(); // Close ImportConfirmPage
      Navigator.of(currentContext).pop(); // Close ImportPage, back to DataManagementPage
    } else {
      // 有失败或跳过: 使用弹窗显示详细信息,等待用户确认后再关闭页面
      await showDialog(
        context: currentContext,
        builder: (ctx) => AlertDialog(
          title: Text(l10nToast.importCompleteTitle),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10nToast.commonConfirm),
            ),
          ],
        ),
      );

      // 用户确认后再关闭页面
      Navigator.of(currentContext).pop(); // Close ImportConfirmPage
      Navigator.of(currentContext).pop(); // Close ImportPage, back to DataManagementPage
    }
    // 返回后再显式刷新一次全局统计，确保顶部汇总即时更新
    try {
      container.read(statsRefreshProvider.notifier).state++;
    } catch (_) {}

    // 导入完成后，账本列表页面会通过监听 importProgressProvider 自动刷新
    // ledgerId 已经在上面的 importProgressProvider 中设置
  }

  void _buildDistinctCategories() {
    final catIdx = mapping['category'];
    if (catIdx == null) {
      distinctCategories = [];
      categoryMapping = {};
      return;
    }
    final set = <String>{};
    final dataStart = widget.hasHeader ? (headerRow + 1) : 0;
    for (int i = dataStart; i < rows.length; i++) {
      if (catIdx < rows[i].length) {
        final name = rows[i][catIdx].trim();
        if (name.isNotEmpty) set.add(name);
      }
    }
    distinctCategories = set.toList()..sort();

    // 初始化分类映射为null，后续在FutureBuilder中进行自动匹配
    categoryMapping = {for (final n in distinctCategories) n: null};
  }
}

// isolate 入口函数：在后台解析 CSV 文本
List<List<String>> _parseRowsIsolate(String input) {
  return CsvParser.parse(input);
}

Future<List<schema.Category>> _loadAllCategories(WidgetRef ref) async {
  final db = ref.read(databaseProvider);
  final expense = await (db.select(db.categories)
        ..where((c) => c.kind.equals('expense')))
      .get();
  final income = await (db.select(db.categories)
        ..where((c) => c.kind.equals('income')))
      .get();
  return [...expense, ...income];
}

class _PreviewTable extends StatelessWidget {
  final List<List<String>> rows;
  // 预览表格: 固定单元格宽度，避免在横向滚动环境中使用 Expanded 触发布局错误
  const _PreviewTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    const double cellWidth = 140;
    final isDark = BeeTokens.isDark(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: BeeTokens.border(context)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            for (int r = 0; r < rows.length; r++)
              Container(
                color: r == 0
                    ? (isDark ? Colors.grey.shade800 : Colors.grey.shade100)
                    : BeeTokens.surfaceElevated(context),
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                child: Row(
                  children: [
                    for (final cell in rows[r])
                      SizedBox(
                        width: cellWidth,
                        child: Text(
                          cell,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: BeeTokens.textPrimary(context),
                            fontWeight: r == 0 ? FontWeight.w600 : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
