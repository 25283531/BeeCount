/// 重构后的账本列表页面
///
/// 集成本地账本 + 远程账本管理
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../providers.dart';
import '../../models/ledger_display_item.dart';
import '../../cloud/transactions_sync_manager.dart';
import '../../cloud/sync_service.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/biz/biz.dart';
import '../../utils/currencies.dart';
import '../../services/logger_service.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../utils/format_utils.dart';
import '../../utils/sync_helpers.dart';
import '../../l10n/app_localizations.dart';
import '../../styles/tokens.dart';

class LedgersPageNew extends ConsumerStatefulWidget {
  const LedgersPageNew({super.key});

  @override
  ConsumerState<LedgersPageNew> createState() => _LedgersPageNewState();
}

class _LedgersPageNewState extends ConsumerState<LedgersPageNew> {
  bool _isRestoring = false;

  @override
  Widget build(BuildContext context) {
    final currentId = ref.watch(currentLedgerIdProvider);
    // 使用新的分离提供者：本地（快速）和远程（慢速）
    final localLedgersAsync = ref.watch(localLedgersProvider);
    final remoteLedgersAsync = ref.watch(remoteLedgersProvider);

    // 监听导入进度，当导入完成时自动刷新账本列表和同步状态
    ref.listen<ImportProgress>(importProgressProvider, (previous, next) {
      // 检测到导入完成（从运行中变为完成状态）
      if (previous?.running == true &&
          next.isJustCompleted &&
          next.ledgerId != null) {
        print('🟢 [LedgersPage] 检测到导入完成: ledgerId=${next.ledgerId}');
        // 触发同步状态刷新和账本列表刷新
        handleLocalChange(ref, ledgerId: next.ledgerId!, background: true);
      }
    });

    return Scaffold(
      body: Column(
        children: [
          PrimaryHeader(
            title: AppLocalizations.of(context).ledgersTitle,
            showBack: false,
            actions: [
              // 新建账本
              IconButton(
                onPressed: () => _showCreateLedgerDialog(context),
                icon: Icon(Icons.add, color: BeeTokens.textPrimary(context)),
              ),
              // 刷新
              IconButton(
                onPressed: () {
                  ref.read(ledgerListRefreshProvider.notifier).state++;
                },
                icon:
                    Icon(Icons.refresh, color: BeeTokens.textPrimary(context)),
              ),
            ],
          ),
          Expanded(
            child: _buildProgressiveList(
              context,
              ref,
              currentId,
              localLedgersAsync,
              remoteLedgersAsync,
            ),
          ),
        ],
      ),
    );
  }

  /// 渐进式加载列表：先显示本地，再加载远程
  Widget _buildProgressiveList(
    BuildContext context,
    WidgetRef ref,
    int? currentId,
    AsyncValue<List<LedgerDisplayItem>> localAsync,
    AsyncValue<List<LedgerDisplayItem>> remoteAsync,
  ) {
    // 获取本地账本（快速）
    final localLedgers = localAsync.value ?? [];
    final localError = localAsync.error;

    // 获取远程账本（慢速）
    final remoteLedgers = remoteAsync.value ?? [];
    final remoteLoading = remoteAsync.isLoading;
    final remoteError = remoteAsync.error;

    // 如果本地也在加载中且没有缓存数据，显示全局加载
    if (localAsync.isLoading && localLedgers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // 如果本地加载失败，显示错误
    if (localError != null && localLedgers.isEmpty) {
      return Center(
        child: Text('${AppLocalizations.of(context).commonError}: $localError'),
      );
    }

    // 如果本地和远程都为空
    if (localLedgers.isEmpty && remoteLedgers.isEmpty && !remoteLoading) {
      return Center(
        child: Text(AppLocalizations.of(context).ledgersEmpty),
      );
    }

    // 构建列表（本地 + 远程）
    return _buildSplitLedgerList(
      context,
      ref,
      localLedgers,
      remoteLedgers,
      currentId,
      remoteLoading: remoteLoading,
      remoteError: remoteError,
    );
  }

  /// 构建分离的账本列表（本地 + 远程）
  Widget _buildSplitLedgerList(
    BuildContext context,
    WidgetRef ref,
    List<LedgerDisplayItem> localLedgers,
    List<LedgerDisplayItem> remoteLedgers,
    int? currentId, {
    bool remoteLoading = false,
    Object? remoteError,
  }) {
    return ListView(
      padding: EdgeInsets.symmetric(
        vertical: 8.0.scaled(context, ref),
      ),
      children: [
        // 本地账本区域
        if (localLedgers.isNotEmpty) ...[
          _SectionHeader(
            title: AppLocalizations.of(context).ledgersLocal,
            trailing: localLedgers.length.toString(),
          ),
          ...localLedgers.map((ledger) => LedgerCard(
                ledger: ledger,
                selected: !ledger.isRemoteOnly && ledger.id == currentId,
                onTap: () => _handleLocalLedgerTap(ledger),
                onLongPress: () => _showLocalLedgerActions(context, ledger),
              )),
        ],

        // 远程账本区域（仅在加载中或有远程账本时显示）
        if (remoteLoading ||
            remoteLedgers.isNotEmpty ||
            remoteError != null) ...[
          SizedBox(height: 16.0.scaled(context, ref)),
          _SectionHeader(
            title: AppLocalizations.of(context).ledgersRemote,
            trailing: remoteLoading ? null : remoteLedgers.length.toString(),
            action: remoteLedgers.isNotEmpty
                ? TextButton.icon(
                    icon: const Icon(Icons.cloud_download, size: 18),
                    label: Text(AppLocalizations.of(context).ledgersRestoreAll),
                    onPressed: _isRestoring
                        ? null
                        : () => _handleBatchRestore(context),
                  )
                : null,
          ),

          // 远程账本加载状态
          if (remoteLoading)
            Padding(
              padding:
                  EdgeInsets.symmetric(vertical: 24.0.scaled(context, ref)),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            )
          else if (remoteError != null)
            Padding(
              padding: EdgeInsets.all(16.0.scaled(context, ref)),
              child: Center(
                child: Text(
                  '${AppLocalizations.of(context).commonError}: $remoteError',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            )
          else
            ...remoteLedgers.map((ledger) => LedgerCard(
                  ledger: ledger,
                  onTap: () => _handleRemoteLedgerTap(context, ledger),
                  onLongPress: () => _showRemoteLedgerActions(context, ledger),
                )),
        ],

        SizedBox(height: 60.0.scaled(context, ref)),
      ],
    );
  }

  /// 构建账本列表（旧版，保留用于兼容）
  Widget _buildLedgerList(
    BuildContext context,
    WidgetRef ref,
    List<LedgerDisplayItem> ledgers,
    int? currentId, {
    bool showLoadingOverlay = false,
  }) {
    // 分组：本地账本 vs 远程账本
    final localLedgers = ledgers.where((l) => !l.isRemoteOnly).toList();
    final remoteLedgers = ledgers.where((l) => l.isRemoteOnly).toList();

    return Stack(
      children: [
        ListView(
          padding: EdgeInsets.symmetric(
            vertical: 8.0.scaled(context, ref),
          ),
          children: [
            // 本地账本区域
            if (localLedgers.isNotEmpty) ...[
              _SectionHeader(
                title: AppLocalizations.of(context).ledgersLocal,
                trailing: localLedgers.length.toString(),
              ),
              ...localLedgers.map((ledger) => LedgerCard(
                    ledger: ledger,
                    selected: !ledger.isRemoteOnly && ledger.id == currentId,
                    onTap: () => _handleLocalLedgerTap(ledger),
                    onLongPress: () => _showLocalLedgerActions(context, ledger),
                  )),
            ],

            // 远程账本区域
            if (remoteLedgers.isNotEmpty) ...[
              SizedBox(height: 16.0.scaled(context, ref)),
              _SectionHeader(
                title: AppLocalizations.of(context).ledgersRemote,
                trailing: remoteLedgers.length.toString(),
                action: TextButton.icon(
                  icon: const Icon(Icons.cloud_download, size: 18),
                  label: Text(AppLocalizations.of(context).ledgersRestoreAll),
                  onPressed:
                      _isRestoring ? null : () => _handleBatchRestore(context),
                ),
              ),
              ...remoteLedgers.map((ledger) => LedgerCard(
                    ledger: ledger,
                    onTap: () => _handleRemoteLedgerTap(context, ledger),
                    onLongPress: () =>
                        _showRemoteLedgerActions(context, ledger),
                  )),
            ],

            SizedBox(height: 60.0.scaled(context, ref)),
          ],
        ),

        // 加载蒙层：刷新时显示
        if (showLoadingOverlay)
          Positioned.fill(
            child: Container(
              color: BeeTokens.surfaceElevated(context).withValues(alpha: 0.7),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
          ),
      ],
    );
  }

  /// 处理本地账本点击 - 切换账本或显示冲突对话框
  Future<void> _handleLocalLedgerTap(LedgerDisplayItem ledger) async {
    // 获取同步状态
    final syncStatusAsync = ref.read(syncStatusProvider(ledger.id));
    final syncStatus = syncStatusAsync.value;

    // 检查是否有冲突
    if (syncStatus?.diff == SyncDiff.different) {
      // 显示冲突解决对话框
      await _showConflictResolutionDialog(context, ledger);
      return;
    }

    // 正常切换账本
    ref.read(currentLedgerIdProvider.notifier).state = ledger.id;
    showToast(
        context,
        AppLocalizations.of(context)
            .ledgersSwitched(translateLedgerName(context, ledger.name)));
  }

  /// 处理远程账本点击 - 下载
  Future<void> _handleRemoteLedgerTap(
      BuildContext context, LedgerDisplayItem ledger) async {
    final confirmed = await AppDialog.confirm<bool>(
      context,
      title: AppLocalizations.of(context).ledgersDownloadTitle,
      message: AppLocalizations.of(context)
          .ledgersDownloadMessage(translateLedgerName(context, ledger.name)),
    );

    if (confirmed != true || !mounted) return;

    try {
      showToast(context, AppLocalizations.of(context).ledgersDownloading);

      final syncService = ref.read(syncServiceProvider);
      if (syncService is! TransactionsSyncManager) {
        throw Exception('Cloud sync not available');
      }

      await syncService.downloadRemoteLedger(
        name: ledger.name,
        currency: ledger.currency,
        remotePath: 'ledger_${ledger.id}.json',
      );

      if (!mounted) return;

      // 刷新列表和同步状态
      ref.read(ledgerListRefreshProvider.notifier).state++;
      ref.read(statsRefreshProvider.notifier).state++;
      ref.read(syncStatusRefreshProvider.notifier).state++;

      showToast(
          context,
          AppLocalizations.of(context).ledgersDownloadSuccess(
              translateLedgerName(context, ledger.name)));
    } catch (e) {
      if (!mounted) return;
      await AppDialog.error(
        context,
        title: AppLocalizations.of(context).commonFailed,
        message: '$e',
      );
    }
  }

  /// 显示本地账本操作菜单
  Future<void> _showLocalLedgerActions(
      BuildContext context, LedgerDisplayItem ledger) async {
    final action = await showDialog<String>(
      context: context,
      builder: (dctx) {
        final primary = Theme.of(dctx).colorScheme.primary;
        return SimpleDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(AppLocalizations.of(context).ledgersActions),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dctx, 'edit'),
              child: Row(
                children: [
                  Icon(Icons.edit, color: primary),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.of(context).ledgersEdit),
                ],
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dctx, 'clear'),
              child: Row(
                children: [
                  const Icon(Icons.clear_all, color: Colors.orange),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.of(context).ledgersClear),
                ],
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dctx, 'deleteLocal'),
              child: Row(
                children: [
                  const Icon(Icons.delete_outline, color: Colors.deepOrange),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.of(context).ledgersDeleteLocal),
                ],
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dctx, 'delete'),
              child: Row(
                children: [
                  const Icon(Icons.delete_forever_outlined,
                      color: Colors.redAccent),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.of(context).ledgersDelete),
                ],
              ),
            ),
          ],
        );
      },
    );

    if (!mounted) return;

    if (action == 'edit') {
      await _handleEditLedger(context, ledger);
    } else if (action == 'clear') {
      await _handleClearLedger(context, ledger);
    } else if (action == 'deleteLocal') {
      await _handleDeleteLocalLedgerOnly(context, ledger);
    } else if (action == 'delete') {
      await _handleDeleteLocalLedger(context, ledger);
    }
  }

  /// 显示远程账本操作菜单
  Future<void> _showRemoteLedgerActions(
      BuildContext context, LedgerDisplayItem ledger) async {
    final action = await showDialog<String>(
      context: context,
      builder: (dctx) {
        final primary = Theme.of(dctx).colorScheme.primary;
        return SimpleDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(AppLocalizations.of(context).ledgersActions),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dctx, 'download'),
              child: Row(
                children: [
                  Icon(Icons.cloud_download, color: primary),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.of(context).ledgersDownload),
                ],
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dctx, 'delete'),
              child: Row(
                children: [
                  const Icon(Icons.delete_forever_outlined,
                      color: Colors.redAccent),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.of(context).ledgersDeleteRemote),
                ],
              ),
            ),
          ],
        );
      },
    );

    if (!mounted) return;

    if (action == 'download') {
      await _handleRemoteLedgerTap(context, ledger);
    } else if (action == 'delete') {
      await _handleDeleteRemoteLedger(context, ledger);
    }
  }

  /// 编辑账本
  Future<void> _handleEditLedger(
      BuildContext context, LedgerDisplayItem ledger) async {
    final repo = ref.read(repositoryProvider);
    final ledgerData = await (repo.db.select(repo.db.ledgers)
          ..where((l) => l.id.equals(ledger.id)))
        .getSingle();

    if (!mounted) return;

    final result = await _showLedgerEditorDialog(
      context,
      title: AppLocalizations.of(context).ledgersEdit,
      initialName: ledgerData.name,
      initialCurrency: ledgerData.currency,
    );

    if (result == null || !mounted) return;

    await repo.updateLedger(
      id: ledger.id,
      name: result.name.trim(),
      currency: result.currency,
    );

    // 修改账本名称/币种后，需要触发同步以更新云端账本文件
    await handleLocalChange(ref, ledgerId: ledger.id, background: true);

    ref.read(ledgerListRefreshProvider.notifier).state++;
  }

  /// 清空账本（删除所有账单，保留账本）
  Future<void> _handleClearLedger(
      BuildContext context, LedgerDisplayItem ledger) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await AppDialog.confirm<bool>(
      context,
      title: l10n.ledgersClearTitle,
      message:
          l10n.ledgersClearMessage(translateLedgerName(context, ledger.name)),
    );

    if (confirmed != true || !mounted) return;

    try {
      final repo = ref.read(repositoryProvider);

      // 删除该账本的所有账单
      await (repo.db.delete(repo.db.transactions)
            ..where((t) => t.ledgerId.equals(ledger.id)))
          .go();

      if (!mounted) return;

      // 触发同步状态刷新
      await handleLocalChange(ref, ledgerId: ledger.id, background: true);

      ref.read(ledgerListRefreshProvider.notifier).state++;
      ref.read(statsRefreshProvider.notifier).state++;

      showToast(context, l10n.ledgersClearSuccess);
    } catch (e) {
      if (!mounted) return;
      await AppDialog.error(
        context,
        title: l10n.commonFailed,
        message: '$e',
      );
    }
  }

  /// 仅删除本地账本（保留云端备份）
  Future<void> _handleDeleteLocalLedgerOnly(
      BuildContext context, LedgerDisplayItem ledger) async {
    final l10n = AppLocalizations.of(context);

    // 检查是否只剩一个账本
    final repo = ref.read(repositoryProvider);
    final allLedgers = await repo.db.select(repo.db.ledgers).get();
    if (allLedgers.length <= 1) {
      if (!mounted) return;
      showToast(context, l10n.ledgersCannotDeleteLastOne);
      return;
    }

    final confirmed = await AppDialog.confirm<bool>(
      context,
      title: l10n.ledgersDeleteLocalTitle,
      message: l10n
          .ledgersDeleteLocalMessage(translateLedgerName(context, ledger.name)),
    );

    if (confirmed != true || !mounted) return;

    try {
      final current = ref.read(currentLedgerIdProvider);

      // 如果删除的是当前账本，需要切换到另一个账本
      if (current == ledger.id) {
        final remainAfterDelete =
            allLedgers.where((l) => l.id != ledger.id).toList();
        // 由于已经检查过账本数量 > 1，这里一定有剩余账本
        final newId = remainAfterDelete.first.id;
        ref.read(currentLedgerIdProvider.notifier).state = newId;
      }

      // 只删除本地账本，不删除云端备份
      await repo.deleteLedger(ledger.id);

      if (!mounted) return;

      ref.read(ledgerListRefreshProvider.notifier).state++;
      ref.read(statsRefreshProvider.notifier).state++;

      showToast(context, l10n.ledgersDeleteLocalSuccess);
    } catch (e) {
      if (!mounted) return;
      await AppDialog.error(
        context,
        title: l10n.commonFailed,
        message: '$e',
      );
    }
  }

  /// 删除本地账本
  Future<void> _handleDeleteLocalLedger(
      BuildContext context, LedgerDisplayItem ledger) async {
    final l10n = AppLocalizations.of(context);

    // 检查是否只剩一个账本
    final repo = ref.read(repositoryProvider);
    final allLedgers = await repo.db.select(repo.db.ledgers).get();
    if (allLedgers.length <= 1) {
      if (!mounted) return;
      showToast(context, l10n.ledgersCannotDeleteLastOne);
      return;
    }

    final confirmed = await AppDialog.confirm<bool>(
      context,
      title: l10n.ledgersDeleteConfirm,
      message: l10n.ledgersDeleteMessage,
    );

    if (confirmed != true || !mounted) return;

    try {
      final sync = ref.read(syncServiceProvider);
      final current = ref.read(currentLedgerIdProvider);

      // 如果删除的是当前账本，需要切换到另一个账本
      if (current == ledger.id) {
        final remainAfterDelete =
            allLedgers.where((l) => l.id != ledger.id).toList();
        // 由于已经检查过账本数量 > 1，这里一定有剩余账本
        final newId = remainAfterDelete.first.id;
        ref.read(currentLedgerIdProvider.notifier).state = newId;
      }

      // 删除本地账本
      await repo.deleteLedger(ledger.id);

      // 删除远程备份（忽略错误）
      try {
        await sync.deleteRemoteBackup(ledgerId: ledger.id);
      } catch (e) {
        logger.warning('ledger', '删除云端备份失败（忽略）：$e');
      }

      if (!mounted) return;

      ref.read(ledgerListRefreshProvider.notifier).state++;
      ref.read(statsRefreshProvider.notifier).state++;

      showToast(context, AppLocalizations.of(context).ledgersDeleted);
    } catch (e) {
      if (!mounted) return;
      await AppDialog.error(
        context,
        title: AppLocalizations.of(context).ledgersDeleteFailed,
        message: '$e',
      );
    }
  }

  /// 删除远程账本
  Future<void> _handleDeleteRemoteLedger(
      BuildContext context, LedgerDisplayItem ledger) async {
    final confirmed = await AppDialog.confirm<bool>(
      context,
      title: AppLocalizations.of(context).ledgersDeleteRemoteConfirm,
      message: AppLocalizations.of(context).ledgersDeleteRemoteMessage(
          translateLedgerName(context, ledger.name)),
    );

    if (confirmed != true || !mounted) return;

    try {
      showToast(context, AppLocalizations.of(context).ledgersDeleting);

      final syncService = ref.read(syncServiceProvider);
      if (syncService is! TransactionsSyncManager) {
        throw Exception('Cloud sync not available');
      }

      await syncService.deleteRemoteLedger(
          remotePath: 'ledger_${ledger.id}.json');

      if (!mounted) return;

      ref.read(ledgerListRefreshProvider.notifier).state++;

      showToast(
          context, AppLocalizations.of(context).ledgersDeleteRemoteSuccess);
    } catch (e) {
      if (!mounted) return;
      await AppDialog.error(
        context,
        title: AppLocalizations.of(context).commonFailed,
        message: '$e',
      );
    }
  }

  /// 批量恢复所有远程账本
  Future<void> _handleBatchRestore(BuildContext context) async {
    // 获取远程账本数量
    final remoteLedgersAsync = ref.read(remoteLedgersProvider);
    final remoteLedgers = remoteLedgersAsync.value ?? [];

    final confirmed = await AppDialog.confirm<bool>(
      context,
      title: AppLocalizations.of(context).ledgersRestoreAllTitle,
      message: AppLocalizations.of(context)
          .ledgersRestoreAllMessage(remoteLedgers.length),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isRestoring = true);

    try {
      showToast(context, AppLocalizations.of(context).ledgersRestoring);

      final syncService = ref.read(syncServiceProvider);
      if (syncService is! TransactionsSyncManager) {
        throw Exception('Cloud sync not available');
      }

      final result = await syncService.restoreAllRemoteLedgers();

      if (!mounted) return;

      setState(() => _isRestoring = false);

      // 刷新列表和同步状态
      ref.read(ledgerListRefreshProvider.notifier).state++;
      ref.read(statsRefreshProvider.notifier).state++;
      ref.read(syncStatusRefreshProvider.notifier).state++;

      // 显示结果
      await AppDialog.info(
        context,
        title: AppLocalizations.of(context).ledgersRestoreComplete,
        message: AppLocalizations.of(context).ledgersRestoreResult(
          result.success,
          result.failed,
        ),
      );
    } catch (e) {
      setState(() => _isRestoring = false);

      if (!mounted) return;

      await AppDialog.error(
        context,
        title: AppLocalizations.of(context).commonFailed,
        message: '$e',
      );
    }
  }

  /// 显示创建账本对话框
  Future<void> _showCreateLedgerDialog(BuildContext context) async {
    final result = await _showLedgerEditorDialog(
      context,
      title: AppLocalizations.of(context).ledgersNew,
    );

    if (result == null || !mounted) return;

    final repo = ref.read(repositoryProvider);
    await repo.createLedger(
      name: result.name.trim(),
      currency: result.currency,
    );

    ref.read(ledgerListRefreshProvider.notifier).state++;
  }

  /// 账本编辑对话框
  Future<({String name, String currency})?> _showLedgerEditorDialog(
    BuildContext context, {
    String? title,
    String? initialName,
    String? initialCurrency,
  }) async {
    String name = initialName ?? '';
    String currency = initialCurrency ?? 'CNY';
    final nameCtrl = TextEditingController(text: name);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final primary = Theme.of(ctx).colorScheme.primary;
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          content: StatefulBuilder(builder: (ctx, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title ?? AppLocalizations.of(ctx).ledgersEdit,
                  textAlign: TextAlign.center,
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(ctx).ledgersName,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(AppLocalizations.of(ctx).ledgersCurrency),
                  subtitle: Text(displayCurrency(currency, context)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final picked =
                        await _showCurrencyPicker(ctx, initial: currency);
                    if (picked != null) {
                      setState(() => currency = picked);
                    }
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primary,
                        side: BorderSide(color: primary),
                      ),
                      child: Text(AppLocalizations.of(ctx).commonCancel),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(
                        title == AppLocalizations.of(ctx).ledgersNew
                            ? AppLocalizations.of(ctx).ledgersCreate
                            : AppLocalizations.of(ctx).commonSave,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            );
          }),
        );
      },
    );

    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      return (name: nameCtrl.text.trim(), currency: currency);
    }

    return null;
  }

  /// 货币选择器
  Future<String?> _showCurrencyPicker(BuildContext context,
      {String? initial}) async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BeeTokens.surfaceElevated(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (bctx) {
        String query = '';
        String? selected = initial;
        return StatefulBuilder(builder: (sctx, setState) {
          final filtered = getCurrencies(context).where((c) {
            final q = query.trim();
            if (q.isEmpty) return true;
            final uq = q.toUpperCase();
            return c.code.contains(uq) || c.name.contains(q);
          }).toList();

          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: 16 + MediaQuery.of(bctx).viewInsets.bottom,
            ),
            child: SizedBox(
              height: 420,
              child: Column(
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: BeeTokens.textTertiary(context)
                          .withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Text(
                    AppLocalizations.of(bctx).ledgersSelectCurrency,
                    style: Theme.of(bctx).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: AppLocalizations.of(bctx).ledgersSearchCurrency,
                    ),
                    onChanged: (v) => setState(() => query = v),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final c = filtered[i];
                        final sel = c.code == selected;
                        return ListTile(
                          title: Text('${c.name} (${c.code})'),
                          trailing: sel
                              ? Icon(Icons.check,
                                  color: BeeTokens.textPrimary(context))
                              : null,
                          onTap: () => Navigator.pop(bctx, c.code),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  /// 显示冲突解决对话框
  Future<void> _showConflictResolutionDialog(
      BuildContext context, LedgerDisplayItem ledger) async {
    final l10n = AppLocalizations.of(context);
    final syncService = ref.read(syncServiceProvider);

    // 获取同步状态详情
    final syncStatus = await syncService.getStatus(ledgerId: ledger.id);

    if (!mounted) return;

    final DateFormat dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (stateContext, setState) {
            bool isProcessing = false;

            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.red, size: 28),
                  const SizedBox(width: 12),
                  Text(l10n.ledgersConflictTitle),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.ledgersConflictMessage,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 16),

                    // 本地信息
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.ledgersConflictLocalInfo(
                                syncStatus.localCount),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.ledgersConflictLocalFingerprint(
                              syncStatus.localFingerprint.substring(0, 8),
                            ),
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black54),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // 云端信息
                    if (syncStatus.cloudFingerprint != null &&
                        syncStatus.cloudExportedAt != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.ledgersConflictRemoteInfo(
                                  syncStatus.cloudCount ?? 0),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              l10n.ledgersConflictRemoteUpdated(
                                dateFormat.format(
                                    syncStatus.cloudExportedAt!.toLocal()),
                              ),
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.black54),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              l10n.ledgersConflictRemoteFingerprint(
                                syncStatus.cloudFingerprint!.substring(0, 8),
                              ),
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                if (isProcessing)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else ...[
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text(l10n.commonCancel),
                  ),
                  TextButton(
                    onPressed: () async {
                      setState(() => isProcessing = true);
                      try {
                        showToast(context, l10n.ledgersConflictDownloading);
                        final result =
                            await syncService.downloadAndRestoreToCurrentLedger(
                          ledgerId: ledger.id,
                        );

                        if (stateContext.mounted) {
                          Navigator.pop(dialogContext);
                        }

                        if (!mounted) return;

                        // 下载完成后，触发刷新状态和账本列表
                        await handleLocalChange(ref,
                            ledgerId: ledger.id, background: true);

                        // 刷新统计
                        ref.read(statsRefreshProvider.notifier).state++;

                        showToast(
                          context,
                          l10n.ledgersConflictDownloadSuccess(result.inserted),
                        );
                      } catch (e) {
                        setState(() => isProcessing = false);
                        if (stateContext.mounted) {
                          await AppDialog.error(
                            stateContext,
                            title: l10n.commonFailed,
                            message: '$e',
                          );
                        }
                      }
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.download, size: 18),
                        const SizedBox(width: 4),
                        Text(l10n.ledgersConflictDownload),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: () async {
                      setState(() => isProcessing = true);
                      try {
                        showToast(context, l10n.ledgersConflictUploading);
                        await syncService.uploadCurrentLedger(
                            ledgerId: ledger.id);

                        if (stateContext.mounted) {
                          Navigator.pop(dialogContext);
                        }

                        if (!mounted) return;

                        // 刷新列表和同步状态
                        ref.read(ledgerListRefreshProvider.notifier).state++;
                        ref.read(syncStatusRefreshProvider.notifier).state++;

                        showToast(context, l10n.ledgersConflictUploadSuccess);
                      } catch (e) {
                        setState(() => isProcessing = false);
                        if (stateContext.mounted) {
                          await AppDialog.error(
                            stateContext,
                            title: l10n.commonFailed,
                            message: '$e',
                          );
                        }
                      }
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.upload, size: 18),
                        const SizedBox(width: 4),
                        Text(l10n.ledgersConflictUpload),
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

/// 区域标题
class _SectionHeader extends ConsumerWidget {
  final String title;
  final String? trailing;
  final Widget? action;

  const _SectionHeader({
    required this.title,
    this.trailing,
    this.action,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16.0.scaled(context, ref),
        8.0.scaled(context, ref),
        16.0.scaled(context, ref),
        8.0.scaled(context, ref),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16.0.scaled(context, ref),
              fontWeight: FontWeight.w600,
              color: BeeTokens.textSecondary(context),
            ),
          ),
          if (trailing != null) ...[
            SizedBox(width: 8.0.scaled(context, ref)),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: 8.0.scaled(context, ref),
                vertical: 2.0.scaled(context, ref),
              ),
              decoration: BoxDecoration(
                color: BeeTokens.surfaceSecondary(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                trailing!,
                style: TextStyle(
                  fontSize: 12.0.scaled(context, ref),
                  color: BeeTokens.textTertiary(context),
                ),
              ),
            ),
          ],
          const Spacer(),
          if (action != null) action!,
        ],
      ),
    );
  }
}
