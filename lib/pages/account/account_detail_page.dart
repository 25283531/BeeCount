import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart' as db;
import '../../providers.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/biz/biz.dart';
import '../../styles/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../utils/transaction_edit_utils.dart';
import '../../services/category_service.dart';

/// 账户详情页面
/// 显示账户的统计信息和相关交易
class AccountDetailPage extends ConsumerWidget {
  final db.Account account;

  const AccountDetailPage({
    super.key,
    required this.account,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final primaryColor = ref.watch(primaryColorProvider);
    final statsAsync = ref.watch(accountStatsProvider(account.id));
    final transactionsAsync =
        ref.watch(accountTransactionsProvider(account.id));
    final currentLedgerAsync = ref.watch(currentLedgerProvider);
    final currencyCode = currentLedgerAsync.asData?.value?.currency ?? 'CNY';
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: account.name,
            subtitle: _getTypeLabel(context, account.type),
            showBack: true,
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(
                horizontal: 0,
                vertical: 16.0.scaled(context, ref),
              ),
              children: [
                // 统计卡片
                SectionCard(
                  child: statsAsync.when(
                    data: (stats) => Padding(
                      padding: EdgeInsets.all(12.0.scaled(context, ref)),
                      child: Row(
                        children: [
                          Expanded(
                            child: _StatCell(
                              label: l10n.accountBalance,
                              value: stats.balance,
                              currencyCode: currencyCode,
                              color: stats.balance >= 0
                                  ? BeeTokens.textPrimary(context)
                                  : BeeTokens.error(context),
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 40.0.scaled(context, ref),
                            color: BeeTokens.border(context),
                          ),
                          Expanded(
                            child: _StatCell(
                              label: l10n.homeIncome,
                              value: stats.income,
                              currencyCode: currencyCode,
                              color: BeeTokens.success(context),
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 40.0.scaled(context, ref),
                            color: BeeTokens.border(context),
                          ),
                          Expanded(
                            child: _StatCell(
                              label: l10n.homeExpense,
                              value: stats.expense,
                              currencyCode: currencyCode,
                              color: BeeTokens.error(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    loading: () => Center(
                      child: Padding(
                        padding: EdgeInsets.all(24.0.scaled(context, ref)),
                        child: const CircularProgressIndicator(),
                      ),
                    ),
                    error: (err, stack) => Padding(
                      padding: EdgeInsets.all(16.0.scaled(context, ref)),
                      child: Text(
                        '${l10n.commonError}: $err',
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 8.0.scaled(context, ref)),
                // 交易列表
                SectionCard(
                  child: transactionsAsync.when(
                    data: (transactions) {
                      if (transactions.isEmpty) {
                        return Padding(
                          padding: EdgeInsets.all(32.0.scaled(context, ref)),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(
                                  Icons.receipt_long_outlined,
                                  size: 48.0.scaled(context, ref),
                                  color: BeeTokens.textTertiary(context),
                                ),
                                SizedBox(height: 8.0.scaled(context, ref)),
                                Text(
                                  l10n.accountNoTransactions,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: BeeTokens.textSecondary(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: EdgeInsets.all(12.0.scaled(context, ref)),
                            child: Text(
                              l10n.accountTransactionHistory,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: BeeTokens.textPrimary(context),
                              ),
                            ),
                          ),
                          ...transactions.asMap().entries.map((entry) {
                            final index = entry.key;
                            final tx = entry.value;

                            return Column(
                              children: [
                                if (index > 0) BeeTokens.cardDivider(context),
                                _TransactionTile(
                                  transaction: tx,
                                  currencyCode: currencyCode,
                                  primaryColor: primaryColor,
                                  ledgers: ref
                                          .watch(ledgersStreamProvider)
                                          .asData
                                          ?.value ??
                                      [],
                                  categories:
                                      categoriesAsync.asData?.value ?? [],
                                  currentAccountId: account.id, // 传入当前账户ID
                                  onTap: () =>
                                      _editTransaction(context, ref, tx),
                                ),
                              ],
                            );
                          }),
                        ],
                      );
                    },
                    loading: () => Center(
                      child: Padding(
                        padding: EdgeInsets.all(24.0.scaled(context, ref)),
                        child: const CircularProgressIndicator(),
                      ),
                    ),
                    error: (err, stack) => Padding(
                      padding: EdgeInsets.all(16.0.scaled(context, ref)),
                      child: Text(
                        '${l10n.commonError}: $err',
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getTypeLabel(BuildContext context, String type) {
    final l10n = AppLocalizations.of(context);
    switch (type) {
      case 'cash':
        return l10n.accountTypeCash;
      case 'bank_card':
        return l10n.accountTypeBankCard;
      case 'credit_card':
        return l10n.accountTypeCreditCard;
      case 'alipay':
        return l10n.accountTypeAlipay;
      case 'wechat':
        return l10n.accountTypeWechat;
      case 'other':
        return l10n.accountTypeOther;
      default:
        return type;
    }
  }

  Future<void> _editTransaction(
      BuildContext context, WidgetRef ref, db.Transaction tx) async {
    // 先获取分类信息
    final categoryAsync = tx.categoryId != null
        ? await ref.read(categoriesProvider.future)
        : null;
    final category = categoryAsync?.cast<db.Category?>().firstWhere(
          (c) => c?.id == tx.categoryId,
          orElse: () => null,
        );

    if (!context.mounted) return;
    await TransactionEditUtils.editTransaction(context, ref, tx, category);

    // 刷新统计数据
    ref.invalidate(accountStatsProvider(account.id));
    ref.invalidate(accountTransactionsProvider(account.id));
  }
}

/// 统计单元格
class _StatCell extends ConsumerWidget {
  final String label;
  final double value;
  final String currencyCode;
  final Color color;

  const _StatCell({
    required this.label,
    required this.value,
    required this.currencyCode,
    required this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        AmountText(
          value: value,
          signed: false,
          showCurrency: true,
          useCompactFormat: ref.watch(compactAmountProvider),
          currencyCode: currencyCode,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        SizedBox(height: 4.0.scaled(context, ref)),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: BeeTokens.textSecondary(context),
          ),
        ),
      ],
    );
  }
}

/// 交易列表项
class _TransactionTile extends ConsumerWidget {
  final db.Transaction transaction;
  final String currencyCode;
  final Color primaryColor;
  final List<db.Ledger> ledgers;
  final List<db.Category> categories;
  final VoidCallback onTap;
  final int? currentAccountId; // 当前账户ID，用于判断转账方向

  const _TransactionTile({
    required this.transaction,
    required this.currencyCode,
    required this.primaryColor,
    required this.ledgers,
    required this.categories,
    required this.onTap,
    this.currentAccountId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 交易类型颜色
    Color amountColor;
    final l10n = AppLocalizations.of(context);

    // 判断转账方向（在账户详情页中）
    bool isTransferOut = false;
    bool isTransferIn = false;
    if (transaction.type == 'transfer' && currentAccountId != null) {
      isTransferOut = transaction.accountId == currentAccountId;
      isTransferIn = transaction.toAccountId == currentAccountId;
    }

    switch (transaction.type) {
      case 'income':
        amountColor = BeeTokens.success(context);
        break;
      case 'expense':
        amountColor = BeeTokens.error(context);
        break;
      case 'transfer':
        // 转出显示红色，转入显示绿色
        amountColor = isTransferOut
            ? BeeTokens.error(context)
            : BeeTokens.success(context);
        break;
      default:
        amountColor = BeeTokens.textPrimary(context);
    }

    // v1.15.0: 获取分类信息
    final category = transaction.categoryId != null
        ? categories.cast<db.Category?>().firstWhere(
              (c) => c?.id == transaction.categoryId,
              orElse: () => null,
            )
        : null;

    // v1.15.0: 标题显示逻辑
    String displayTitle;
    String? displaySubtitle; // 用于转账时显示对方账户

    if (transaction.type == 'transfer') {
      // 转账：优先显示备注，如果没有备注则显示"转账"
      if (transaction.note?.isNotEmpty == true) {
        displayTitle = transaction.note!;
      } else {
        displayTitle = l10n.transferTitle;
      }

      // 获取对方账户名称
      if (isTransferOut && transaction.toAccountId != null) {
        // 转出：显示目标账户
        final toAccountAsync =
            ref.watch(accountByIdProvider(transaction.toAccountId!));
        final toAccountName = toAccountAsync.value?.name;
        if (toAccountName != null) {
          displaySubtitle = '${l10n.transferToPrefix} $toAccountName';
        }
      } else if (isTransferIn && transaction.accountId != null) {
        // 转入：显示来源账户
        final fromAccountAsync =
            ref.watch(accountByIdProvider(transaction.accountId!));
        final fromAccountName = fromAccountAsync.value?.name;
        if (fromAccountName != null) {
          displaySubtitle = '${l10n.transferFromPrefix} $fromAccountName';
        }
      }
    } else {
      // 收入/支出：备注优先，否则显示分类名称
      if (transaction.note?.isNotEmpty == true) {
        displayTitle = transaction.note!;
      } else if (category != null) {
        displayTitle = category.name;
      } else {
        displayTitle =
            transaction.type == 'income' ? l10n.homeIncome : l10n.homeExpense;
      }
    }

    // v1.15.0: 获取账本名称（支持国际化）
    final ledger = ledgers.cast<db.Ledger?>().firstWhere(
          (l) => l?.id == transaction.ledgerId,
          orElse: () => null,
        );
    String ledgerName = ledger?.name ?? '';
    // 如果是默认账本，使用国际化名称
    if (ledgerName == 'Default Ledger') {
      ledgerName = l10n.ledgersDefaultLedgerName;
    }

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 12.0.scaled(context, ref),
          vertical: 12.0.scaled(context, ref),
        ),
        child: Row(
          children: [
            // v1.15.0: 显示分类图标（转账显示特殊图标）
            Container(
              width: 40.0.scaled(context, ref),
              height: 40.0.scaled(context, ref),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                transaction.type == 'transfer'
                    ? Icons.swap_horiz
                    : CategoryService.getCategoryIcon(category?.icon),
                color: primaryColor,
                size: 20.0.scaled(context, ref),
              ),
            ),
            SizedBox(width: 12.0.scaled(context, ref)),
            // 内容
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // v1.15.0: 标题 + 账本标签
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          displayTitle,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: BeeTokens.textPrimary(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (ledgerName.isNotEmpty) ...[
                        SizedBox(width: 6.0.scaled(context, ref)),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 6.0.scaled(context, ref),
                            vertical: 2.0.scaled(context, ref),
                          ),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.1),
                            borderRadius:
                                BorderRadius.circular(4.0.scaled(context, ref)),
                          ),
                          child: Text(
                            ledgerName,
                            style: TextStyle(
                              fontSize: 11,
                              color: primaryColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  // 转账时显示对方账户
                  if (displaySubtitle != null)
                    Padding(
                      padding: EdgeInsets.only(top: 2.0.scaled(context, ref)),
                      child: Text(
                        displaySubtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: BeeTokens.textSecondary(context),
                        ),
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.only(top: 2.0.scaled(context, ref)),
                    child: Text(
                      _formatDate(transaction.happenedAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: BeeTokens.textTertiary(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 金额
            AmountText(
              value: transaction.type == 'expense'
                  ? -transaction.amount
                  : transaction.type == 'transfer'
                      ? (isTransferOut
                          ? -transaction.amount
                          : transaction.amount)
                      : transaction.amount,
              signed: true,
              showCurrency: false,
              currencyCode: currencyCode,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: amountColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final local = date.toLocal();

    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }

    return '${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

// Provider: 账户相关的交易列表
final accountTransactionsProvider = StreamProvider.family
    .autoDispose<List<db.Transaction>, int>((ref, accountId) {
  final repo = ref.watch(repositoryProvider);
  return repo.watchAccountTransactions(accountId);
});
