import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift show Value;
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../data/db.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/biz/amount_editor_sheet.dart';
import '../../widgets/category/category_selector.dart';
import '../../widgets/transaction/transfer_form.dart';
import '../../styles/tokens.dart';
import '../../utils/sync_helpers.dart';

/// 交易编辑器页面
/// 支持创建/编辑收入、支出和转账记录
class TransactionEditorPage extends ConsumerStatefulWidget {
  final String initialKind; // 'expense', 'income', or 'transfer'
  // quickAdd: 点击分类后在当前弹窗上叠加金额输入，保存成功后依次关闭两个弹窗
  final bool quickAdd;
  final int? initialCategoryId;
  final String? initialNote; // 用于金额输入弹窗回填备注
  final double? initialAmount;
  final DateTime? initialDate;
  final int? editingTransactionId;
  final int? initialAccountId;
  final int? initialToAccountId; // 转账时的目标账户

  const TransactionEditorPage({
    super.key,
    required this.initialKind,
    this.quickAdd = false,
    this.initialCategoryId,
    this.initialNote,
    this.initialAmount,
    this.initialDate,
    this.editingTransactionId,
    this.initialAccountId,
    this.initialToAccountId,
  });

  @override
  ConsumerState<TransactionEditorPage> createState() => _TransactionEditorPageState();
}

class _TransactionEditorPageState extends ConsumerState<TransactionEditorPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _autoOpened = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    // 设置初始tab: 0=支出, 1=收入, 2=转账
    if (widget.initialKind == 'income') {
      _tab.index = 1;
    } else if (widget.initialKind == 'transfer') {
      _tab.index = 2;
    } else {
      _tab.index = 0;
    }

    // 若需要自动打开金额输入，则在首帧后查询分类并触发
    // 注意：转账类型不走这个逻辑
    if (widget.quickAdd && widget.initialCategoryId != null && widget.initialKind != 'transfer') {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || _autoOpened) return;
        final db = ref.read(databaseProvider);
        final c = await (db.select(db.categories)
              ..where((t) => t.id.equals(widget.initialCategoryId!)))
            .getSingleOrNull();
        if (c != null && mounted) {
          // 切换到对应的 tab
          final idx = c.kind == 'income' ? 1 : 0;
          if (_tab.index != idx) _tab.animateTo(idx);
          _autoOpened = true;
          // 直接调用 onPick 逻辑，打开金额输入
          // ignore: use_build_context_synchronously
          await _onCategorySelected(context, c, c.kind);
        }
      });
    }
    // 注意：转账编辑模式不需要在这里做任何操作，让 TransferForm 自己处理
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // 紧凑顶部：去除多余留白 + 选中下划线
          PrimaryHeader(
            title: '',
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            bottom: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      Expanded(
                        child: Center(
                          child: TabBar(
                            controller: _tab,
                            isScrollable: false,
                            labelColor: BeeTokens.textPrimary(context),
                            unselectedLabelColor: BeeTokens.textSecondary(context),
                            indicator: UnderlineTabIndicator(
                              borderSide:
                                  BorderSide(width: 2, color: BeeTokens.textPrimary(context)),
                              insets: const EdgeInsets.symmetric(horizontal: 0),
                            ),
                            tabs: [
                              Tab(text: AppLocalizations.of(context)!.categoryExpense),
                              Tab(text: AppLocalizations.of(context)!.categoryIncome),
                              Tab(text: AppLocalizations.of(context)!.transferTitle),
                            ],
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(AppLocalizations.of(context)!.commonCancel,
                            style: TextStyle(color: BeeTokens.textPrimary(context))),
                      )
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                CategorySelector(
                  kind: 'expense',
                  onCategorySelected: (c) => _onCategorySelected(context, c, 'expense'),
                  initialCategoryId: widget.initialCategoryId,
                ),
                CategorySelector(
                  kind: 'income',
                  onCategorySelected: (c) => _onCategorySelected(context, c, 'income'),
                  initialCategoryId: widget.initialCategoryId,
                ),
                TransferForm(
                  onTransferComplete: () {
                    // 关闭交易编辑器
                    Navigator.pop(context);
                  },
                  initialFromAccountId: widget.initialAccountId,
                  initialToAccountId: widget.initialToAccountId,
                  editingTransactionId: widget.editingTransactionId,
                  initialAmount: widget.initialAmount,
                  initialNote: widget.initialNote,
                  initialDate: widget.initialDate,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 获取默认账户ID（验证币种匹配）
  Future<int?> _getDefaultAccountId(String kind, int ledgerId) async {
    try {
      // 1. 根据类型获取默认账户ID
      final defaultAccountId = kind == 'income'
          ? await ref.read(defaultIncomeAccountIdProvider.future)
          : await ref.read(defaultExpenseAccountIdProvider.future);

      if (defaultAccountId == null) return null;

      // 2. 获取账本币种
      final ledger = await ref.read(ledgerByIdProvider(ledgerId).future);
      if (ledger == null) return null;

      // 3. 获取默认账户信息
      final account = await ref.read(accountByIdProvider(defaultAccountId).future);
      if (account == null) return null;

      // 4. 验证币种匹配
      if (account.currency != ledger.currency) return null;

      return defaultAccountId;
    } catch (e) {
      return null;
    }
  }

  Future<void> _onCategorySelected(BuildContext context, Category c, String kind) async {
    if (!widget.quickAdd) {
      Navigator.pop(context, c);
      return;
    }
    final db = ref.read(databaseProvider);
    final ledgerId = ref.read(currentLedgerIdProvider);

    // 确定初始账户ID（新建时使用默认账户，编辑时保持原值）
    int? initialAccountId = widget.initialAccountId;
    if (widget.editingTransactionId == null && widget.initialAccountId == null) {
      // 新建模式：尝试获取默认账户
      initialAccountId = await _getDefaultAccountId(kind, ledgerId);
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: BeeTokens.surfaceSheet(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => AmountEditorSheet(
        categoryName: c.name,
        initialDate: widget.initialDate ?? DateTime.now(),
        initialAmount: widget.initialAmount,
        initialNote: widget.initialNote,
        initialAccountId: initialAccountId,
        showAccountPicker: true,
        db: db,
        ledgerId: ledgerId,
        onSubmit: (res) async {
          final repo = ref.read(repositoryProvider);
          if (widget.editingTransactionId != null) {
            // 编辑模式：从转账切换到收入/支出时，清空转账相关字段
            await (db.update(db.transactions)
                  ..where((t) => t.id.equals(widget.editingTransactionId!)))
                .write(
              TransactionsCompanion(
                type: drift.Value(kind),
                amount: drift.Value(res.amount),
                categoryId: drift.Value(c.id),
                note: drift.Value(res.note),
                happenedAt: drift.Value(res.date),
                accountId: drift.Value(res.accountId),
                toAccountId: drift.Value(null), // 清空转账目标账户
              ),
            );
          } else {
            await repo.addTransaction(
              ledgerId: ledgerId,
              type: kind,
              amount: res.amount,
              categoryId: c.id,
              happenedAt: res.date,
              note: res.note,
              accountId: res.accountId,
            );
          }
          // 统一处理：自动/手动同步与状态刷新（后台静默）
          await handleLocalChange(ref, ledgerId: ledgerId, background: true);
          // 刷新：账本笔数与全局统计
          ref.invalidate(countsForLedgerProvider(ledgerId));
          ref.read(statsRefreshProvider.notifier).state++;
          // 更新小组件数据
          if (!mounted) return;
          await updateAppWidget(ref, context);
          if (!mounted) return;
          if (ctx.mounted && Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
          if (context.mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
          // 反馈：轻微触感 + 系统点击音
          HapticFeedback.lightImpact();
          SystemSound.play(SystemSoundType.click);
        },
      ),
    );
  }
}
