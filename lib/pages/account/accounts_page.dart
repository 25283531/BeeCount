import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../providers/theme_providers.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/biz/amount_text.dart';
import '../../widgets/biz/section_card.dart';
import '../../data/db.dart' as db;
import '../../l10n/app_localizations.dart';
import '../../styles/tokens.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../utils/currencies.dart';
import 'account_edit_page.dart';
import 'account_detail_page.dart';

class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  IconData _getIconForType(String type) {
    switch (type) {
      case 'cash':
        return Icons.payments_outlined;
      case 'bank_card':
        return Icons.credit_card;
      case 'credit_card':
        return Icons.credit_score;
      case 'alipay':
        return Icons.currency_yuan;
      case 'wechat':
        return Icons.chat;
      case 'other':
        return Icons.account_balance_outlined;
      default:
        return Icons.account_balance_wallet_outlined;
    }
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

  Color _getColorForType(String type, Color primaryColor) {
    switch (type) {
      case 'alipay':
        return const Color(0xFF1677FF); // 支付宝蓝
      case 'wechat':
        return const Color(0xFF07C160); // 微信绿
      case 'cash':
        return Colors.orange;
      case 'bank_card':
        return const Color(0xFF1890FF); // 银行卡蓝
      case 'credit_card':
        return Colors.purple;
      default:
        return primaryColor;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final ledgerId = ref.watch(currentLedgerIdProvider);
    // v1.15.0: 显示所有账户，不限账本
    final accountsAsync = ref.watch(allAccountsStreamProvider);
    final accountFeatureAsync = ref.watch(accountFeatureEnabledProvider);
    final primaryColor = ref.watch(primaryColorProvider);
    // v1.15.0: 全局统计，不再限制账本
    final totalStatsAsync = ref.watch(allAccountsTotalStatsProvider);
    final allStatsAsync = ref.watch(allAccountStatsProvider);

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.accountsTitle,
            showBack: true,
            actions: [
              IconButton(
                onPressed: () => _addAccount(context, ref, ledgerId),
                icon: const Icon(Icons.add),
                tooltip: l10n.accountAddTooltip,
              ),
            ],
          ),
          Expanded(
            child: accountsAsync.when(
              data: (accounts) {
                return ListView(
                  padding: EdgeInsets.symmetric(
                    horizontal: 12.0.scaled(context, ref),
                    vertical: 8.0.scaled(context, ref),
                  ),
                  children: [
                    // 功能开关卡片
                    accountFeatureAsync.when(
                      data: (enabled) {
                        return SectionCard(
                          margin: EdgeInsets.zero,
                          child: Column(
                            children: [
                              SwitchListTile(
                                title: Text(
                                  l10n.accountsEnableFeature,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                subtitle: Text(l10n.accountsFeatureDescription),
                                value: enabled,
                                activeColor: primaryColor,
                                onChanged: (value) async {
                                  await ref
                                      .read(accountFeatureSetterProvider)
                                      .setEnabled(value);
                                  ref.invalidate(accountFeatureEnabledProvider);
                                },
                              ),
                              // 默认账户设置（仅在启用账户功能时显示）
                              if (enabled && accounts.isNotEmpty) ...[
                                Divider(
                                  height: 1,
                                  color: BeeTokens.divider(context),
                                ),
                                _DefaultAccountSelector(
                                  accounts: accounts,
                                  primaryColor: primaryColor,
                                  type: 'expense',
                                ),
                                Divider(
                                  height: 1,
                                  indent: 16,
                                  endIndent: 16,
                                  color: BeeTokens.divider(context),
                                ),
                                _DefaultAccountSelector(
                                  accounts: accounts,
                                  primaryColor: primaryColor,
                                  type: 'income',
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),

                    if (accounts.isEmpty)
                      // 空状态
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.account_balance_wallet_outlined,
                                size: 64.0.scaled(context, ref),
                                color: BeeTokens.textTertiary(context),
                              ),
                              SizedBox(height: 16.0.scaled(context, ref)),
                              Text(
                                l10n.accountsEmptyMessage,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: BeeTokens.textSecondary(context),
                                ),
                              ),
                              SizedBox(height: 24.0.scaled(context, ref)),
                              ElevatedButton.icon(
                                onPressed: () => _addAccount(context, ref, ledgerId),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  foregroundColor: Colors.white,
                                ),
                                icon: const Icon(Icons.add),
                                label: Text(l10n.accountAddButton),
                              ),
                            ],
                          ),
                        ),
                      )
                    else ...[
                      // 顶部汇总统计卡片
                      SizedBox(height: 8.0.scaled(context, ref)),
                      totalStatsAsync.when(
                        data: (stats) => SectionCard(
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 16.0.scaled(context, ref),
                              vertical: 12.0.scaled(context, ref),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _StatCell(
                                    label: l10n.accountTotalBalance,
                                    value: stats.totalBalance,
                                    color: stats.totalBalance >= 0
                                        ? BeeTokens.textPrimary(context)
                                        : Colors.red,
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: 40.0.scaled(context, ref),
                                  color: BeeTokens.border(context),
                                ),
                                Expanded(
                                  child: _StatCell(
                                    label: l10n.accountTotalIncome,
                                    value: stats.totalIncome,
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
                                    label: l10n.accountTotalExpense,
                                    value: stats.totalExpense,
                                    color: BeeTokens.error(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        loading: () => SectionCard(
                          child: Center(
                            child: Padding(
                              padding:
                                  EdgeInsets.all(16.0.scaled(context, ref)),
                              child: const CircularProgressIndicator(),
                            ),
                          ),
                        ),
                        error: (err, stack) => const SizedBox.shrink(),
                      ),

                      // 账户列表
                      SizedBox(height: 8.0.scaled(context, ref)),
                      ...accounts.map((account) {
                        return _AccountCard(
                          account: account,
                          primaryColor: primaryColor,
                          typeColor:
                              _getColorForType(account.type, primaryColor),
                          icon: _getIconForType(account.type),
                          typeLabel: _getTypeLabel(context, account.type),
                          stats: allStatsAsync.asData?.value[account.id],
                          onTap: () =>
                              _viewAccountDetail(context, ref, account),
                          onEdit: () =>
                              _editAccount(context, ref, account, ledgerId),
                        );
                      }),
                    ],
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(
                child: Text('${l10n.commonError}: $err'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addAccount(BuildContext context, WidgetRef ref, int ledgerId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AccountEditPage(ledgerId: ledgerId),
      ),
    );

    // v1.15.0: 刷新全局统计数据
    ref.invalidate(allAccountStatsProvider);
    ref.invalidate(allAccountsTotalStatsProvider);
    ref.invalidate(statsRefreshProvider);
  }

  Future<void> _editAccount(BuildContext context, WidgetRef ref,
      db.Account account, int ledgerId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AccountEditPage(
          account: account,
          ledgerId: ledgerId,
        ),
      ),
    );

    // v1.15.0: 刷新全局统计数据
    ref.invalidate(allAccountStatsProvider);
    ref.invalidate(allAccountsTotalStatsProvider);
    ref.invalidate(statsRefreshProvider);
  }

  void _viewAccountDetail(
      BuildContext context, WidgetRef ref, db.Account account) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AccountDetailPage(account: account),
      ),
    );
  }
}

/// 统计单元格
class _StatCell extends ConsumerWidget {
  final String label;
  final double value;
  final Color color;

  const _StatCell({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        // v1.15.0: 全局统计可能包含多币种，暂不显示币种符号
        AmountText(
          value: value,
          signed: false,
          showCurrency: false,
          useCompactFormat: ref.watch(compactAmountProvider),
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
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// 账户卡片 - 类似银行卡样式
class _AccountCard extends ConsumerWidget {
  final db.Account account;
  final Color primaryColor;
  final Color typeColor;
  final IconData icon;
  final String typeLabel;
  final ({double balance, double expense, double income})? stats;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  const _AccountCard({
    required this.account,
    required this.primaryColor,
    required this.typeColor,
    required this.icon,
    required this.typeLabel,
    this.stats,
    required this.onTap,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: 12.0.scaled(context, ref)),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              typeColor,
              typeColor.withValues(alpha: 0.8),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12.0.scaled(context, ref)),
          boxShadow: [
            BoxShadow(
              color: typeColor.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12.0.scaled(context, ref)),
          child: Stack(
            children: [
              // 背景装饰圆圈
              Positioned(
                right: -20,
                top: -20,
                child: Container(
                  width: 100.0.scaled(context, ref),
                  height: 100.0.scaled(context, ref),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
              ),
              Positioned(
                right: 40,
                bottom: -30,
                child: Container(
                  width: 120.0.scaled(context, ref),
                  height: 120.0.scaled(context, ref),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
              ),
              // 卡片内容
              Padding(
                padding: EdgeInsets.all(16.0.scaled(context, ref)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 顶部：账户名称和图标
                    Row(
                      children: [
                        Container(
                          width: 40.0.scaled(context, ref),
                          height: 40.0.scaled(context, ref),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            icon,
                            color: Colors.white,
                            size: 20.0.scaled(context, ref),
                          ),
                        ),
                        SizedBox(width: 12.0.scaled(context, ref)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            account.name,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        SizedBox(width: 8.0.scaled(context, ref)),
                                        // v1.15.0: 显示币种名称（如：人民币、美元）
                                        Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 6.0.scaled(context, ref),
                                            vertical: 2.0.scaled(context, ref),
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(4.0.scaled(context, ref)),
                                          ),
                                          child: Text(
                                            getCurrencyName(account.currency, context),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 2.0.scaled(context, ref)),
                              Text(
                                typeLabel,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 12.0.scaled(context, ref)),
                        // 编辑按钮
                        GestureDetector(
                          onTap: () {
                            onEdit();
                          },
                          child: Container(
                            padding: EdgeInsets.all(8.0.scaled(context, ref)),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.edit,
                              color: Colors.white,
                              size: 16.0.scaled(context, ref),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16.0.scaled(context, ref)),
                    // 统计数据
                    if (stats != null)
                      Row(
                        children: [
                          Expanded(
                            child: _CardStatItem(
                              label:
                                  AppLocalizations.of(context).accountBalance,
                              value: stats!.balance,
                              currencyCode: account.currency,
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 30.0.scaled(context, ref),
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                          Expanded(
                            child: _CardStatItem(
                              label: AppLocalizations.of(context).homeIncome,
                              value: stats!.income,
                              currencyCode: account.currency,
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 30.0.scaled(context, ref),
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                          Expanded(
                            child: _CardStatItem(
                              label: AppLocalizations.of(context).homeExpense,
                              value: stats!.expense,
                              currencyCode: account.currency,
                            ),
                          ),
                        ],
                      )
                    else
                      Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              vertical: 8.0.scaled(context, ref)),
                          child: const CircularProgressIndicator(
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 卡片内统计项
class _CardStatItem extends ConsumerWidget {
  final String label;
  final double value;
  final String currencyCode;

  const _CardStatItem({
    required this.label,
    required this.value,
    required this.currencyCode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        AmountText(
          value: value,
          signed: false,
          showCurrency: false,
          useCompactFormat: ref.watch(compactAmountProvider),
          currencyCode: currencyCode,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        SizedBox(height: 2.0.scaled(context, ref)),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// 默认账户选择器
class _DefaultAccountSelector extends ConsumerWidget {
  final List<db.Account> accounts;
  final Color primaryColor;
  final String type; // 'income' 或 'expense'

  const _DefaultAccountSelector({
    required this.accounts,
    required this.primaryColor,
    required this.type,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isIncome = type == 'income';
    final defaultAccountIdAsync = isIncome
        ? ref.watch(defaultIncomeAccountIdProvider)
        : ref.watch(defaultExpenseAccountIdProvider);

    return defaultAccountIdAsync.when(
      data: (defaultAccountId) {
        // 查找默认账户
        db.Account? defaultAccount;
        if (defaultAccountId != null) {
          defaultAccount = accounts
              .where((a) => a.id == defaultAccountId)
              .firstOrNull;
        }

        final title = isIncome
            ? l10n.accountDefaultIncomeTitle
            : l10n.accountDefaultExpenseTitle;
        final description = isIncome
            ? l10n.accountDefaultIncomeDescription
            : l10n.accountDefaultExpenseDescription;

        return ListTile(
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          subtitle: Text(
            defaultAccount != null
                ? l10n.accountDefaultSet(defaultAccount.name)
                : description,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                defaultAccount?.name ?? l10n.accountDefaultNone,
                style: TextStyle(
                  color: BeeTokens.textSecondary(context),
                  fontSize: 14,
                ),
              ),
              SizedBox(width: 4.0.scaled(context, ref)),
              Icon(
                Icons.chevron_right,
                color: BeeTokens.iconTertiary(context),
              ),
            ],
          ),
          onTap: () => _showAccountPicker(context, ref, accounts, defaultAccountId),
        );
      },
      loading: () => ListTile(
        title: Text(isIncome ? l10n.accountDefaultIncomeTitle : l10n.accountDefaultExpenseTitle),
        trailing: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  void _showAccountPicker(
    BuildContext context,
    WidgetRef ref,
    List<db.Account> accounts,
    int? currentDefaultId,
  ) {
    final l10n = AppLocalizations.of(context);
    final isIncome = type == 'income';
    final title = isIncome
        ? l10n.accountDefaultIncomeTitle
        : l10n.accountDefaultExpenseTitle;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: BeeTokens.surfaceElevated(context),
        title: Text(
          title,
          style: TextStyle(color: BeeTokens.textPrimary(context)),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 不设置选项
              _buildAccountOption(
                context, ref,
                title: l10n.accountDefaultNone,
                icon: Icons.block,
                iconColor: BeeTokens.iconSecondary(context),
                isSelected: currentDefaultId == null,
                onTap: () async {
                  if (isIncome) {
                    await ref
                        .read(defaultAccountSetterProvider)
                        .setDefaultIncomeAccountId(null);
                    ref.invalidate(defaultIncomeAccountIdProvider);
                  } else {
                    await ref
                        .read(defaultAccountSetterProvider)
                        .setDefaultExpenseAccountId(null);
                    ref.invalidate(defaultExpenseAccountIdProvider);
                  }
                  if (context.mounted) Navigator.pop(context);
                },
              ),
              // 账户列表
              ...accounts.map((account) {
                final isSelected = account.id == currentDefaultId;
                return _buildAccountOption(
                  context, ref,
                  title: account.name,
                  subtitle: getCurrencyName(account.currency, context),
                  icon: _getIconForType(account.type),
                  iconColor: _getColorForType(account.type, primaryColor),
                  isSelected: isSelected,
                  onTap: () async {
                    if (isIncome) {
                      await ref
                          .read(defaultAccountSetterProvider)
                          .setDefaultIncomeAccountId(account.id);
                      ref.invalidate(defaultIncomeAccountIdProvider);
                    } else {
                      await ref
                          .read(defaultAccountSetterProvider)
                          .setDefaultExpenseAccountId(account.id);
                      ref.invalidate(defaultExpenseAccountIdProvider);
                    }
                    if (context.mounted) Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccountOption(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    String? subtitle,
    required IconData icon,
    required Color iconColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? primaryColor : BeeTokens.textPrimary(context),
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: BeeTokens.textTertiary(context),
              ),
            )
          : null,
      trailing: isSelected ? Icon(Icons.check, color: primaryColor) : null,
      onTap: onTap,
    );
  }

  IconData _getIconForType(String type) {
    switch (type) {
      case 'cash':
        return Icons.payments_outlined;
      case 'bank_card':
        return Icons.credit_card;
      case 'credit_card':
        return Icons.credit_score;
      case 'alipay':
        return Icons.currency_yuan;
      case 'wechat':
        return Icons.chat;
      case 'other':
        return Icons.account_balance_outlined;
      default:
        return Icons.account_balance_wallet_outlined;
    }
  }

  Color _getColorForType(String type, Color primaryColor) {
    switch (type) {
      case 'alipay':
        return const Color(0xFF1677FF);
      case 'wechat':
        return const Color(0xFF07C160);
      case 'cash':
        return Colors.orange;
      case 'bank_card':
        return const Color(0xFF1890FF);
      case 'credit_card':
        return Colors.purple;
      default:
        return primaryColor;
    }
  }
}
