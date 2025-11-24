import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as d;
import '../../data/db.dart';
import '../../providers.dart';
import '../../widgets/biz/biz.dart';
import '../../widgets/ui/ui.dart';
import '../../styles/tokens.dart';
import '../../utils/category_utils.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/transaction_edit_utils.dart';
import '../../widgets/category_icon.dart';
import 'category_detail_page.dart';

/// 搜索页面
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _minAmountController = TextEditingController();
  final TextEditingController _maxAmountController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  List<({Transaction t, Category? category})> _searchResults = [];
  List<({Transaction t, Category? category})> _allTransactions = [];
  bool _isSearching = false;
  String _searchText = '';
  double? _minAmount;
  double? _maxAmount;
  bool _showAmountFilter = false;
  bool _hasInitializedAmountFilter = false;
  bool _hasScheduledSearch = false; // 防止重复调度搜索

  // 批量操作相关
  bool _isBatchMode = false;
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _minAmountController.dispose();
    _maxAmountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchText = _searchController.text.trim();
    });
    _performSearch();
  }

  void _onAmountFilterChanged() {
    setState(() {
      _minAmount = double.tryParse(_minAmountController.text.trim());
      _maxAmount = double.tryParse(_maxAmountController.text.trim());
    });
    _performSearch();
  }

  /// 执行搜索
  void _performSearch() {
    if (_searchText.isEmpty && _minAmount == null && _maxAmount == null) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
        _hasScheduledSearch = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _hasScheduledSearch = false;
    });

    final results = _allTransactions.where((item) {
      final transaction = item.t;
      final category = item.category;

      // 文本搜索
      bool textMatch = true;
      if (_searchText.isNotEmpty) {
        final searchLower = _searchText.toLowerCase();
        final note = transaction.note?.toLowerCase() ?? '';
        final categoryName =
            CategoryUtils.getDisplayName(category?.name, context).toLowerCase();
        final amountStr = transaction.amount.toString();

        textMatch = note.contains(searchLower) ||
            categoryName.contains(searchLower) ||
            amountStr.contains(searchLower);
      }

      // 金额范围搜索
      bool amountMatch = true;
      if (_minAmount != null || _maxAmount != null) {
        final amount = transaction.amount;
        if (_minAmount != null && amount < _minAmount!) {
          amountMatch = false;
        }
        if (_maxAmount != null && amount > _maxAmount!) {
          amountMatch = false;
        }
      }

      return textMatch && amountMatch;
    }).toList();

    setState(() {
      _searchResults = results;
      _isSearching = false;
    });
  }

  /// 从数据库重新加载并执行搜索
  Future<void> _performSearchFromDb() async {
    if (!mounted) return;

    final repo = ref.read(repositoryProvider);
    final ledgerId = ref.read(currentLedgerIdProvider);

    setState(() {
      _isSearching = true;
    });

    // 从数据库重新获取所有交易
    final allTransactions =
        await repo.transactionsWithCategoryAll(ledgerId: ledgerId).first;

    if (!mounted) return;

    // 更新_allTransactions
    _allTransactions = allTransactions;

    // 执行搜索筛选
    _performSearch();
  }

  /// 切换批量操作模式
  void _toggleBatchMode() {
    setState(() {
      _isBatchMode = !_isBatchMode;
      if (!_isBatchMode) {
        _selectedIds.clear();
      }
    });
  }

  /// 切换选择
  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  /// 全选/取消全选
  void _toggleSelectAll() {
    setState(() {
      if (_selectedIds.length == _searchResults.length) {
        _selectedIds.clear();
      } else {
        _selectedIds.clear();
        _selectedIds.addAll(_searchResults.map((e) => e.t.id));
      }
    });
  }

  /// 检查选中的交易中是否包含转账类型
  bool _hasTransferInSelection() {
    return _searchResults
        .where((item) => _selectedIds.contains(item.t.id))
        .any((item) => item.t.type == 'transfer');
  }

  /// 批量操作完成后刷新
  Future<void> _refreshAfterBatchOperation(int count, String operation) async {
    if (mounted) {
      showToast(context, operation);
      setState(() {
        _selectedIds.clear();
        _isBatchMode = false;
      });
      // 从数据库重新加载最新数据并执行搜索
      await _performSearchFromDb();
    }
  }

  /// 批量删除对话框
  void _showBatchDeleteDialog() {
    final count = _selectedIds.length;
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.searchBatchDeleteConfirmTitle),
        content: Text(l10n.searchBatchDeleteConfirmMessage(count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _executeBatchDelete();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
  }

  /// 执行批量删除
  Future<void> _executeBatchDelete() async {
    final db = ref.read(databaseProvider);
    final count = _selectedIds.length;
    final l10n = AppLocalizations.of(context);

    try {
      // 使用数据库事务批量操作
      await db.transaction(() async {
        for (final id in _selectedIds) {
          await (db.delete(db.transactions)..where((t) => t.id.equals(id)))
              .go();
        }
      });
      await _refreshAfterBatchOperation(
          count, l10n.searchBatchDeleteSuccess(count));
    } catch (e) {
      if (mounted) {
        showToast(context, l10n.searchBatchDeleteFailed(e.toString()));
      }
    }
  }

  /// 批量设置备注对话框
  void _showBatchSetNoteDialog() {
    _noteController.clear();
    final count = _selectedIds.length;
    final l10n = AppLocalizations.of(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.searchBatchSetNoteTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.searchBatchSetNoteMessage(count)),
            const SizedBox(height: 16),
            TextField(
              controller: _noteController,
              decoration: InputDecoration(
                hintText: l10n.searchBatchSetNoteHint,
                border: const OutlineInputBorder(),
              ),
              maxLines: 3,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () async {
              final note = _noteController.text.trim();
              Navigator.pop(context);
              await _executeBatchSetNote(note);
            },
            child: Text(l10n.commonConfirm),
          ),
        ],
      ),
    );
  }

  /// 执行批量设置备注
  Future<void> _executeBatchSetNote(String note) async {
    final db = ref.read(databaseProvider);
    final count = _selectedIds.length;
    final l10n = AppLocalizations.of(context);

    try {
      // 使用数据库事务批量操作
      await db.transaction(() async {
        for (final id in _selectedIds) {
          await (db.update(db.transactions)..where((t) => t.id.equals(id)))
              .write(
            TransactionsCompanion(
              note: d.Value(note.isEmpty ? null : note),
            ),
          );
        }
      });
      await _refreshAfterBatchOperation(
          count, l10n.searchBatchSetNoteSuccess(count));
    } catch (e) {
      if (mounted) {
        showToast(context, l10n.searchBatchSetNoteFailed(e.toString()));
      }
    }
  }

  /// 批量调整分类对话框
  void _showBatchChangeCategoryDialog() {
    final count = _selectedIds.length;
    final db = ref.read(databaseProvider);
    final l10n = AppLocalizations.of(context);
    int? selectedCategoryId;

    showDialog(
      context: context,
      builder: (context) => StreamBuilder<List<Category>>(
        stream: (db.select(db.categories)
              ..orderBy([(c) => d.OrderingTerm(expression: c.sortOrder)]))
            .watch(),
        builder: (context, snapshot) {
          final categories = snapshot.data ?? [];

          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: Text(l10n.searchBatchChangeCategoryTitle),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.searchBatchChangeCategoryMessage(count)),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      initialValue: selectedCategoryId,
                      decoration: InputDecoration(
                        labelText: l10n.searchBatchChangeCategoryLabel,
                        border: const OutlineInputBorder(),
                      ),
                      items: categories.map((category) {
                        final iconData = getCategoryIconData(
                            category: category, categoryName: category.name);
                        return DropdownMenuItem(
                          value: category.id,
                          child: Row(
                            children: [
                              Icon(
                                iconData,
                                size: 24,
                                color: ref.watch(primaryColorProvider),
                              ),
                              const SizedBox(width: 12),
                              Text(CategoryUtils.getDisplayName(
                                  category.name, context)),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedCategoryId = value;
                        });
                      },
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l10n.commonCancel),
                  ),
                  TextButton(
                    onPressed: selectedCategoryId == null
                        ? null
                        : () async {
                            Navigator.pop(context);
                            await _executeBatchChangeCategory(
                                selectedCategoryId!);
                          },
                    child: Text(l10n.commonConfirm),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// 执行批量调整分类
  Future<void> _executeBatchChangeCategory(int categoryId) async {
    final db = ref.read(databaseProvider);
    final count = _selectedIds.length;
    final l10n = AppLocalizations.of(context);

    try {
      // 使用数据库事务批量操作
      await db.transaction(() async {
        for (final id in _selectedIds) {
          await (db.update(db.transactions)..where((t) => t.id.equals(id)))
              .write(
            TransactionsCompanion(
              categoryId: d.Value(categoryId),
            ),
          );
        }
      });
      await _refreshAfterBatchOperation(
          count, l10n.searchBatchChangeCategorySuccess(count));
    } catch (e) {
      if (mounted) {
        showToast(context, l10n.searchBatchChangeCategoryFailed(e.toString()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    final ledgerId = ref.watch(currentLedgerIdProvider);
    final hide = ref.watch(hideAmountsProvider);
    final l10n = AppLocalizations.of(context);

    // 监听金额筛选开关的持久化状态
    ref.listen<AsyncValue<bool>>(searchAmountFilterEnabledProvider,
        (previous, next) {
      next.whenData((enabled) {
        if (!_hasInitializedAmountFilter) {
          setState(() {
            _showAmountFilter = enabled;
            _hasInitializedAmountFilter = true;
          });
        }
      });
    });

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          // 使用PrimaryHeader
          PrimaryHeader(
            title: _isBatchMode
                ? l10n.searchBatchModeWithCount(
                    _selectedIds.length, _searchResults.length)
                : l10n.searchTitle,
            showBack: !_isBatchMode,
            actions: _isBatchMode && _searchResults.isNotEmpty
                ? [
                    TextButton(
                      onPressed: _toggleSelectAll,
                      child: Text(
                        _selectedIds.length == _searchResults.length
                            ? l10n.searchDeselectAll
                            : l10n.searchSelectAll,
                        style:
                            TextStyle(color: ref.watch(primaryColorProvider)),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _toggleBatchMode,
                      tooltip: l10n.searchExitBatchMode,
                    ),
                  ]
                : null,
          ),
          // 搜索框区域
          if (!_isBatchMode) // 批量模式下隐藏搜索框
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              decoration: BoxDecoration(
                color: BeeTokens.surfaceElevated(context),
                boxShadow: BeeTokens.isDark(context)
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.grey.withValues(alpha: 0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Column(
                children: [
                  // 文本搜索框
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: AppLocalizations.of(context).searchHint,
                      prefixIcon: Icon(Icons.search,
                          color: BeeTokens.textTertiary(context)),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              onPressed: () {
                                _searchController.clear();
                              },
                              icon: Icon(Icons.clear,
                                  color: BeeTokens.textTertiary(context)),
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                            color: Colors.grey.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.primary),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 16),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 金额筛选切换
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          AppLocalizations.of(context).searchAmountRange,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: BeeTokens.textPrimary(context),
                                  ),
                        ),
                      ),
                      Switch(
                        value: _showAmountFilter,
                        onChanged: (value) async {
                          setState(() {
                            _showAmountFilter = value;
                            if (!value) {
                              _minAmountController.clear();
                              _maxAmountController.clear();
                              _minAmount = null;
                              _maxAmount = null;
                              _performSearch();
                            }
                          });

                          final setter = ref.read(searchSettingsSetterProvider);
                          await setter.setAmountFilterEnabled(value);
                        },
                      ),
                    ],
                  ),
                  // 金额范围输入框
                  if (_showAmountFilter) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _minAmountController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: InputDecoration(
                              hintText:
                                  AppLocalizations.of(context).searchMinAmount,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                    color: Colors.grey.withValues(alpha: 0.3)),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 8, horizontal: 12),
                            ),
                            onChanged: (value) => _onAmountFilterChanged(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(AppLocalizations.of(context).searchTo,
                            style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _maxAmountController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: InputDecoration(
                              hintText:
                                  AppLocalizations.of(context).searchMaxAmount,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                    color: Colors.grey.withValues(alpha: 0.3)),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 8, horizontal: 12),
                            ),
                            onChanged: (value) => _onAmountFilterChanged(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          // 搜索结果
          Expanded(
            child: StreamBuilder<List<({Transaction t, Category? category})>>(
              stream: repo.transactionsWithCategoryAll(ledgerId: ledgerId),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  _allTransactions = snapshot.data!;
                  if ((_searchText.isNotEmpty ||
                          _minAmount != null ||
                          _maxAmount != null) &&
                      _searchResults.isEmpty &&
                      !_isSearching &&
                      !_hasScheduledSearch) {
                    _hasScheduledSearch = true;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        _performSearch();
                      }
                    });
                  }
                }

                if (_isSearching) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (_searchText.isEmpty &&
                    _minAmount == null &&
                    _maxAmount == null) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search,
                            size: 64, color: BeeTokens.textTertiary(context)),
                        const SizedBox(height: 16),
                        Text(
                          AppLocalizations.of(context).searchNoInput,
                          style: TextStyle(
                              color: BeeTokens.textTertiary(context),
                              fontSize: 16),
                        ),
                      ],
                    ),
                  );
                }

                if (_searchResults.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off,
                            size: 64, color: BeeTokens.textTertiary(context)),
                        const SizedBox(height: 16),
                        Text(
                          AppLocalizations.of(context).searchNoResults,
                          style: TextStyle(
                              color: BeeTokens.textTertiary(context),
                              fontSize: 16),
                        ),
                      ],
                    ),
                  );
                }

                // 显示搜索结果列表
                return Column(
                  children: [
                    // 批量操作入口 - 仅在非批量模式且有搜索结果时显示
                    if (!_isBatchMode)
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                        decoration: BoxDecoration(
                          color: BeeTokens.surfaceElevated(context),
                        ),
                        child: Row(
                          children: [
                            Text(
                              l10n.searchResultsCount(_searchResults.length),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: BeeTokens.textTertiary(context),
                                  ),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: _toggleBatchMode,
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.blue,
                              ),
                              child: Text(l10n.searchBatchMode),
                            ),
                          ],
                        ),
                      ),
                    // 批量模式下的操作栏
                    if (_isBatchMode)
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                        decoration: BoxDecoration(
                          color: BeeTokens.surfaceElevated(context),
                        ),
                        child: Column(
                          children: [
                            // 全选按钮
                            Row(
                              children: [
                                Text(
                                  l10n.searchSelectedCount(_selectedIds.length),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: BeeTokens.textTertiary(context),
                                      ),
                                ),
                                const Spacer(),
                                TextButton(
                                  onPressed: _toggleSelectAll,
                                  style: TextButton.styleFrom(
                                    foregroundColor:
                                        ref.watch(primaryColorProvider),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    minimumSize: const Size(0, 32),
                                  ),
                                  child: Text(
                                    _selectedIds.length == _searchResults.length
                                        ? l10n.searchDeselectAll
                                        : l10n.searchSelectAll,
                                  ),
                                ),
                              ],
                            ),
                            // 批量操作按钮 - 始终显示，未选择时禁用
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _selectedIds.isEmpty
                                        ? null
                                        : _showBatchSetNoteDialog,
                                    icon: const Icon(Icons.edit_note, size: 16),
                                    label: Text(l10n.searchBatchSetNote,
                                        style: const TextStyle(fontSize: 13)),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor:
                                          ref.watch(primaryColorProvider),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 6, horizontal: 8),
                                      minimumSize: const Size(0, 36),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _selectedIds.isEmpty ||
                                            _hasTransferInSelection()
                                        ? null
                                        : _showBatchChangeCategoryDialog,
                                    icon: const Icon(Icons.category, size: 16),
                                    label: Text(l10n.searchBatchChangeCategory,
                                        style: const TextStyle(fontSize: 13)),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor:
                                          ref.watch(primaryColorProvider),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 6, horizontal: 8),
                                      minimumSize: const Size(0, 36),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _selectedIds.isEmpty
                                        ? null
                                        : _showBatchDeleteDialog,
                                    icon: const Icon(Icons.delete_outline,
                                        size: 16),
                                    label: Text(l10n.commonDelete,
                                        style: const TextStyle(fontSize: 13)),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 6, horizontal: 8),
                                      minimumSize: const Size(0, 36),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    // 列表
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final item = _searchResults[index];
                          final isTransfer = item.t.type == 'transfer';
                          final isExpense = item.t.type == 'expense';

                          // 获取分类显示名称
                          final categoryName = CategoryUtils.getDisplayName(
                              item.category?.name, context);

                          final subtitle = item.t.note ?? '';
                          final isSelected = _selectedIds.contains(item.t.id);

                          final iconData = getCategoryIconData(
                              category: item.category,
                              categoryName: categoryName);

                          return Column(
                            children: [
                              TransactionListItem(
                                icon: iconData,
                                title: subtitle.isNotEmpty
                                    ? subtitle
                                    : categoryName,
                                categoryName:
                                    subtitle.isNotEmpty ? null : categoryName,
                                amount: item.t.amount,
                                isExpense: isExpense,
                                hide: hide,
                                happenedAt: item.t.happenedAt,
                                isSelectionMode: _isBatchMode,
                                isSelected: isSelected,
                                onSelectionChanged: () =>
                                    _toggleSelection(item.t.id),
                                onTap: _isBatchMode
                                    ? null
                                    : () async {
                                        await TransactionEditUtils
                                            .editTransaction(
                                          context,
                                          ref,
                                          item.t,
                                          item.category,
                                        );
                                      },
                                onCategoryTap: _isBatchMode ||
                                        isTransfer ||
                                        item.category?.id == null
                                    ? null
                                    : () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => CategoryDetailPage(
                                              categoryId: item.category!.id,
                                              categoryName: categoryName,
                                            ),
                                          ),
                                        );
                                      },
                              ),
                              if (index < _searchResults.length - 1)
                                BeeDivider.short(
                                    indent: 56 + 16, endIndent: 16),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
