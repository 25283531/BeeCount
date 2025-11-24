import 'dart:io' show Platform, File;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:beecount/widgets/biz/bee_icon.dart';

import '../data/import_page.dart';
import '../data/export_page.dart';
import '../settings/personalize_page.dart';
import '../../providers.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/biz/biz.dart';
import '../../styles/tokens.dart';
import 'package:flutter_cloud_sync/flutter_cloud_sync.dart' hide SyncStatus;
import '../../cloud/sync_service.dart';
import '../cloud/cloud_service_page.dart';
import '../../services/logger_service.dart';
import '../../services/avatar_service.dart';
import '../../services/share_poster_service.dart';
import '../../l10n/app_localizations.dart';
import '../settings/font_settings_page.dart';
import '../category/category_manage_page.dart';
import '../category/category_migration_page.dart';
import '../transaction/recurring_transaction_page.dart';
import '../settings/reminder_settings_page.dart';
import '../settings/language_settings_page.dart';
import '../account/accounts_page.dart';
import '../settings/widget_management_page.dart';
import '../automation/ocr_billing_page.dart';
import '../automation/auto_billing_settings_page.dart';
import '../ai/ai_settings_page.dart';
import '../cloud/cloud_sync_page.dart';
import '../settings/data_management_page.dart';
import '../settings/appearance_settings_page.dart';
import '../settings/smart_billing_page.dart';
import '../settings/automation_page.dart';
import '../settings/about_page.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:in_app_review/in_app_review.dart';
import '../../utils/ui_scale_extensions.dart';

class MinePage extends ConsumerWidget {
  const MinePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authAsync = ref.watch(authServiceProvider);
    final ledgerId = ref.watch(currentLedgerIdProvider);

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context), // ⭐ 使用 Token
      body: Column(
        children: [
          PrimaryHeader(
            showBack: false,
            title: AppLocalizations.of(context).mineTitle,
            compact: true,
            showTitleSection: false,
            content: _MinePageHeader(),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                BeeTokens.cardDivider(context),
                SizedBox(height: 8.0.scaled(context, ref)),
                // 云同步与备份
                Consumer(builder: (sectionContext, sectionRef, _) {
                  final activeCfg = sectionRef.watch(activeCloudConfigProvider);

                  return SectionCard(
                    margin: EdgeInsets.fromLTRB(
                        12.0.scaled(sectionContext, sectionRef),
                        0,
                        12.0.scaled(sectionContext, sectionRef),
                        0),
                    child: Column(
                      children: [
                        // 云服务
                        AppListTile(
                          leading: Icons.cloud_queue_outlined,
                          title: AppLocalizations.of(sectionContext)
                              .mineCloudService,
                          subtitle: activeCfg.when(
                            loading: () => AppLocalizations.of(sectionContext)
                                .mineCloudServiceLoading,
                            error: (e, _) =>
                                '${AppLocalizations.of(sectionContext).commonError}: $e',
                            data: (cfg) {
                              if (cfg.type == CloudBackendType.local) {
                                return AppLocalizations.of(sectionContext)
                                    .mineCloudServiceOffline;
                              } else {
                                if (cfg.type == CloudBackendType.webdav) {
                                  return AppLocalizations.of(sectionContext)
                                      .mineCloudServiceWebDAV;
                                } else {
                                  return AppLocalizations.of(sectionContext)
                                      .mineCloudServiceCustom;
                                }
                              }
                            },
                          ),
                          onTap: () async {
                            await Navigator.of(sectionContext).push(
                              MaterialPageRoute(
                                  builder: (_) => const CloudServicePage()),
                            );
                          },
                        ),
                        // 同步状态
                        Builder(
                          builder: (ctx) {
                            return authAsync.when(
                              loading: () => const Padding(
                                padding: EdgeInsets.all(16.0),
                                child:
                                    Center(child: CircularProgressIndicator()),
                              ),
                              error: (e, _) => Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Text(
                                  '${AppLocalizations.of(sectionContext).commonError}: $e',
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ),
                              data: (auth) => FutureBuilder<CloudUser?>(
                                future: auth.currentUser,
                                builder: (ctx, snap) {
                                  if (snap.hasError) {
                                    return Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Text(
                                        '${AppLocalizations.of(sectionContext).commonError}: ${snap.error}',
                                        style:
                                            const TextStyle(color: Colors.red),
                                      ),
                                    );
                                  }

                                  final user = snap.data;
                                  final cloudConfig = sectionRef
                                      .watch(activeCloudConfigProvider);
                                  final isLocalMode = cloudConfig.hasValue &&
                                      cloudConfig.value!.type ==
                                          CloudBackendType.local;
                                  final canUseCloud =
                                      user != null && !isLocalMode;
                                  final asyncSt = sectionRef
                                      .watch(syncStatusProvider(ledgerId));
                                  final cached = sectionRef
                                      .watch(lastSyncStatusProvider(ledgerId));
                                  final st = asyncSt.asData?.value ?? cached;

                                  // 计算简化的同步状态显示
                                  String subtitle = '';
                                  bool showCheckIcon = false;
                                  final isFirstLoad = st == null;
                                  final refreshing = asyncSt.isLoading;

                                  if (!isFirstLoad) {
                                    switch (st.diff) {
                                      case SyncDiff.notLoggedIn:
                                        subtitle =
                                            AppLocalizations.of(sectionContext)
                                                .mineSyncNotLoggedIn;
                                        break;
                                      case SyncDiff.notConfigured:
                                        subtitle =
                                            AppLocalizations.of(sectionContext)
                                                .mineSyncNotConfigured;
                                        break;
                                      case SyncDiff.noRemote:
                                        subtitle =
                                            AppLocalizations.of(sectionContext)
                                                .mineSyncNoRemote;
                                        break;
                                      case SyncDiff.inSync:
                                        subtitle =
                                            AppLocalizations.of(sectionContext)
                                                .mineSyncInSyncSimple;
                                        showCheckIcon = true;
                                        break;
                                      case SyncDiff.localNewer:
                                        subtitle =
                                            AppLocalizations.of(sectionContext)
                                                .mineSyncLocalNewerSimple;
                                        break;
                                      case SyncDiff.cloudNewer:
                                        subtitle =
                                            AppLocalizations.of(sectionContext)
                                                .mineSyncCloudNewerSimple;
                                        break;
                                      case SyncDiff.different:
                                        subtitle =
                                            AppLocalizations.of(sectionContext)
                                                .mineSyncDifferent;
                                        break;
                                      case SyncDiff.error:
                                        subtitle =
                                            AppLocalizations.of(sectionContext)
                                                .mineSyncError;
                                        break;
                                    }
                                  }

                                  return Column(
                                    children: [
                                      BeeTokens.cardDivider(sectionContext),
                                      AppListTile(
                                        leading: Icons.cloud_sync_outlined,
                                        title:
                                            AppLocalizations.of(sectionContext)
                                                .mineSyncTitle,
                                        subtitle: isFirstLoad ? null : subtitle,
                                        enabled: !isLocalMode,
                                        trailing: (canUseCloud &&
                                                (isFirstLoad || refreshing))
                                            ? const SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2))
                                            : showCheckIcon
                                                ? Icon(Icons.check_circle,
                                                    color: sectionRef.watch(
                                                        primaryColorProvider),
                                                    size: 20)
                                                : Icon(Icons.chevron_right,
                                                    color: BeeTokens.iconTertiary(
                                                        context), // ⭐ 使用 Token
                                                    size: 20),
                                        onTap: () async {
                                          await Navigator.of(sectionContext)
                                              .push(
                                            MaterialPageRoute(
                                                builder: (_) =>
                                                    const CloudSyncPage()),
                                          );
                                        },
                                      ),
                                    ],
                                  );
                                },
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  );
                }),
                // 功能管理
                SizedBox(height: 8.0.scaled(context, ref)),
                SectionCard(
                  margin: EdgeInsets.fromLTRB(12.0.scaled(context, ref), 0,
                      12.0.scaled(context, ref), 0),
                  child: Column(
                    children: [
                      // 智能记账
                      AppListTile(
                        leading: Icons.auto_awesome_outlined,
                        title: AppLocalizations.of(context).smartBilling,
                        subtitle: AppLocalizations.of(context).smartBillingDesc,
                        trailing: Icon(Icons.chevron_right,
                            color: BeeTokens.iconTertiary(context),
                            size: 20), // ⭐ 使用 Token
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const SmartBillingPage()),
                          );
                        },
                      ),
                      BeeTokens.cardDivider(context),
                      // 数据管理
                      AppListTile(
                        leading: Icons.storage_outlined,
                        title: AppLocalizations.of(context).dataManagement,
                        subtitle:
                            AppLocalizations.of(context).dataManagementDesc,
                        trailing: Icon(Icons.chevron_right,
                            color: BeeTokens.iconTertiary(context),
                            size: 20), // ⭐ 使用 Token
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const DataManagementPage()),
                          );
                        },
                      ),
                      BeeTokens.cardDivider(context),
                      // 账户管理
                      AppListTile(
                        leading: Icons.account_balance_wallet_outlined,
                        title: AppLocalizations.of(context).accountsTitle,
                        subtitle:
                            AppLocalizations.of(context).accountsManageDesc,
                        trailing: Icon(Icons.chevron_right,
                            color: BeeTokens.iconTertiary(context),
                            size: 20), // ⭐ 使用 Token
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const AccountsPage()),
                          );
                        },
                      ),
                      BeeTokens.cardDivider(context),
                      // 自动化功能
                      AppListTile(
                        leading: Icons.schedule_outlined,
                        title: AppLocalizations.of(context).automation,
                        subtitle: AppLocalizations.of(context).automationDesc,
                        trailing: Icon(Icons.chevron_right,
                            color: BeeTokens.iconTertiary(context),
                            size: 20), // ⭐ 使用 Token
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const AutomationPage()),
                          );
                        },
                      ),
                      BeeTokens.cardDivider(context),
                      // 外观设置
                      AppListTile(
                        leading: Icons.palette_outlined,
                        title: AppLocalizations.of(context).appearanceSettings,
                        subtitle:
                            AppLocalizations.of(context).appearanceSettingsDesc,
                        trailing: Icon(Icons.chevron_right,
                            color: BeeTokens.iconTertiary(context),
                            size: 20), // ⭐ 使用 Token
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const AppearanceSettingsPage()),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                // 支持与关于
                SizedBox(height: 8.0.scaled(context, ref)),
                SectionCard(
                  margin: EdgeInsets.fromLTRB(12.0.scaled(context, ref), 0,
                      12.0.scaled(context, ref), 0),
                  child: Column(
                    children: [
                      AppListTile(
                        leading: Icons.info_outline,
                        title: AppLocalizations.of(context).about,
                        subtitle: AppLocalizations.of(context).aboutDesc,
                        trailing: Icon(Icons.chevron_right,
                            color: BeeTokens.iconTertiary(context),
                            size: 20), // ⭐ 使用 Token
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const AboutPage()),
                          );
                        },
                      ),
                      BeeTokens.cardDivider(context),
                      AppListTile(
                        leading: Icons.feedback_outlined,
                        title: AppLocalizations.of(context).mineFeedback,
                        subtitle:
                            AppLocalizations.of(context).mineFeedbackSubtitle,
                        onTap: () async {
                          final url = Uri.parse(
                              'https://github.com/TNT-Likely/BeeCount/issues');
                          await _tryOpenUrl(url);
                        },
                      ),
                      BeeTokens.cardDivider(context),
                      AppListTile(
                        leading: Icons.star_outline,
                        title: AppLocalizations.of(context).mineSupportAuthor,
                        subtitle: AppLocalizations.of(context)
                            .mineSupportAuthorSubtitle,
                        onTap: () async {
                          final url = Uri.parse(
                              'https://github.com/TNT-Likely/BeeCount');
                          await _tryOpenUrl(url);
                        },
                      ),
                      BeeTokens.cardDivider(context),
                      AppListTile(
                        leading: Icons.share_outlined,
                        title: AppLocalizations.of(context).mineShareApp,
                        subtitle:
                            AppLocalizations.of(context).mineShareAppSubtitle,
                        onTap: () async {
                          try {
                            showToast(
                                context,
                                AppLocalizations.of(context)
                                    .mineShareGenerating);
                            final primaryColor = ref.read(primaryColorProvider);
                            final imageBytes =
                                await SharePosterService.generatePoster(
                                    context, primaryColor);
                            if (!context.mounted) return;
                            if (imageBytes != null) {
                              await SharePosterService.showPosterPreview(
                                  context, imageBytes);
                            } else {
                              await AppDialog.error(
                                context,
                                title:
                                    AppLocalizations.of(context).commonFailed,
                                message: AppLocalizations.of(context)
                                    .mineShareFailed,
                              );
                            }
                          } catch (e) {
                            if (!context.mounted) return;
                            await AppDialog.error(
                              context,
                              title: AppLocalizations.of(context).commonFailed,
                              message: '$e',
                            );
                          }
                        },
                      ),
                      // 只在iOS上显示评分入口（Android还未上架）
                      if (Platform.isIOS) ...[
                        BeeTokens.cardDivider(context),
                        AppListTile(
                          leading: Icons.star_border_rounded,
                          title: AppLocalizations.of(context).mineRateApp,
                          subtitle:
                              AppLocalizations.of(context).mineRateAppSubtitle,
                          onTap: () => _rateApp(context),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: BeeDimens.p16.scaled(context, ref)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCell extends ConsumerWidget {
  final String label;
  final dynamic value; // 可以是 String 或 double
  final TextStyle? labelStyle;
  final TextStyle? numStyle;
  final bool isAmount; // 是否为金额类型
  final String? currencyCode; // 币种代码
  final bool centered; // 是否居中对齐

  const _StatCell({
    required this.label,
    required this.value,
    this.labelStyle,
    this.numStyle,
    this.isAmount = false,
    this.currencyCode,
    this.centered = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget valueWidget;
    if (isAmount && value is double) {
      // 金额类型,使用 AmountText
      valueWidget = AmountText(
        value: value as double,
        signed: false,
        showCurrency: true,
        useCompactFormat: ref.watch(compactAmountProvider),
        currencyCode: currencyCode,
        style: numStyle,
      );
    } else {
      // 其他类型,直接显示字符串
      valueWidget = Text(value.toString(), style: numStyle);
    }

    return Column(
      crossAxisAlignment:
          centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        valueWidget,
        SizedBox(height: 4.0.scaled(context, ref)), // 数字与标签间距增大
        Text(label,
            style: labelStyle,
            textAlign: centered ? TextAlign.center : TextAlign.start),
      ],
    );
  }
}

// 导入完成后的短暂动画提示：线性进度条从 0 -> 100%
class _ImportSuccessTile extends StatelessWidget {
  const _ImportSuccessTile();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (ctx, v, child) {
        return AppListTile(
          leading: Icons.check_circle_outline,
          title: AppLocalizations.of(ctx).mineImportCompleteTitle,
          subtitle: AppLocalizations.of(ctx).mineImportCompleteAllSuccess,
          trailing: SizedBox(
            width: 72,
            child: LinearProgressIndicator(
              value: v,
              valueColor: AlwaysStoppedAnimation(primary),
            ),
          ),
        );
      },
    );
  }
}

// 数据管理分组
Widget _buildDataManagementSection(BuildContext context, WidgetRef ref) {
  return SectionCard(
    margin: EdgeInsets.fromLTRB(
        12.0.scaled(context, ref), 0, 12.0.scaled(context, ref), 0),
    child: Column(
      children: [
        // 导入数据
        Consumer(builder: (ctx, r, _) {
          final p = r.watch(importProgressProvider);
          if (!p.running && p.total == 0) {
            return AppListTile(
              leading: Icons.file_upload_outlined,
              title: AppLocalizations.of(context).mineImport,
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ImportPage()),
                );
              },
            );
          }
          if (p.running) {
            final percent =
                p.total == 0 ? null : (p.done / p.total).clamp(0.0, 1.0);
            return AppListTile(
              leading: Icons.upload_outlined,
              title: AppLocalizations.of(context).mineImportProgressTitle,
              subtitle: AppLocalizations.of(context)
                  .mineImportProgressSubtitle(p.done, p.fail, p.ok, p.total),
              trailing: SizedBox(
                  width: 72, child: LinearProgressIndicator(value: percent)),
              onTap: null,
            );
          }
          final allOk = (p.done == p.total) && (p.fail == 0);
          if (allOk) return const _ImportSuccessTile();
          return AppListTile(
            leading: Icons.info_outline,
            title: AppLocalizations.of(context).mineImportCompleteTitle,
            subtitle:
                '${AppLocalizations.of(context).commonSuccess} ${p.ok}，${AppLocalizations.of(context).commonFailed} ${p.fail}',
            onTap: null,
          );
        }),
        BeeDivider.thin(),
        // 导出数据
        AppListTile(
          leading: Icons.file_download_outlined,
          title: AppLocalizations.of(context).mineExport,
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ExportPage()),
            );
          },
        ),
        BeeDivider.thin(),
        // 分类管理
        AppListTile(
          leading: Icons.category_outlined,
          title: AppLocalizations.of(context).mineCategoryManagement,
          subtitle: AppLocalizations.of(context).mineCategoryManagementSubtitle,
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CategoryManagePage()),
            );
          },
        ),
        BeeDivider.thin(),
        // 分类迁移
        AppListTile(
          leading: Icons.swap_horiz,
          title: AppLocalizations.of(context).mineCategoryMigration,
          subtitle: AppLocalizations.of(context).mineCategoryMigrationSubtitle,
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CategoryMigrationPage()),
            );
          },
        ),
        BeeDivider.thin(),
        // 账户管理
        AppListTile(
          leading: Icons.account_balance_wallet_outlined,
          title: AppLocalizations.of(context).accountsTitle,
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AccountsPage()),
            );
          },
        ),
      ],
    ),
  );
}

// 智能记账分组（合并AI和OCR功能）
Widget _buildSmartBillingSection(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context);
  final cameraFirst = ref.watch(fabCameraFirstProvider).value ?? false;

  return SectionCard(
    margin: EdgeInsets.fromLTRB(
        12.0.scaled(context, ref), 0, 12.0.scaled(context, ref), 0),
    child: Column(
      children: [
        // AI智能识别
        AppListTile(
          leading: Icons.psychology_outlined,
          title: l10n.aiSettingsTitle,
          subtitle: l10n.aiSettingsSubtitle,
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'AI',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AISettingsPage()),
            );
          },
        ),
        BeeDivider.thin(),
        // OCR扫描记账
        AppListTile(
          leading: Icons.document_scanner_outlined,
          title: l10n.ocrBilling,
          subtitle: l10n.ocrBillingDesc,
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'BETA',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const OcrBillingPage()),
            );
          },
        ),
        BeeDivider.thin(),
        // 截图自动记账
        AppListTile(
          leading: Icons.auto_fix_high,
          title: l10n.autoScreenshotBilling,
          subtitle: Platform.isAndroid
              ? l10n.autoScreenshotBillingDesc
              : '通过快捷指令实现截图自动识别记账',
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'BETA',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const AutoBillingSettingsPage()),
            );
          },
        ),
        BeeTokens.cardDivider(context),
        // FAB行为切换
        InkWell(
          onTap: () async {
            final newValue = !cameraFirst;
            await ref.read(fabBehaviorSetterProvider).setCameraFirst(newValue);
            ref.invalidate(fabCameraFirstProvider);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    cameraFirst ? Icons.camera_alt : Icons.edit,
                    color: Theme.of(context).colorScheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.aiFabSettingTitle,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: BeeTokens.textPrimary(context), // ⭐ 使用 Token
                        ),
                      ),
                      Text(
                        cameraFirst
                            ? l10n.aiFabSettingDescCamera
                            : l10n.aiFabSettingDescManual,
                        style: TextStyle(
                          fontSize: 13,
                          color: BeeTokens.textSecondary(context), // ⭐ 使用 Token
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: cameraFirst,
                  onChanged: (value) async {
                    await ref
                        .read(fabBehaviorSetterProvider)
                        .setCameraFirst(value);
                    ref.invalidate(fabCameraFirstProvider);
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

// 自动化功能分组（仅保留周期和提醒）
Widget _buildAutomationSection(BuildContext context, WidgetRef ref) {
  return SectionCard(
    margin: EdgeInsets.fromLTRB(
        12.0.scaled(context, ref), 0, 12.0.scaled(context, ref), 0),
    child: Column(
      children: [
        // 周期记账
        AppListTile(
          leading: Icons.repeat,
          title: AppLocalizations.of(context).mineRecurringTransactions,
          subtitle:
              AppLocalizations.of(context).mineRecurringTransactionsSubtitle,
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const RecurringTransactionPage()),
            );
          },
        ),
        BeeDivider.thin(),
        // 记账提醒
        AppListTile(
          leading: Icons.notifications_outlined,
          title: AppLocalizations.of(context).mineReminderSettings,
          subtitle: AppLocalizations.of(context).mineReminderSettingsSubtitle,
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ReminderSettingsPage()),
            );
          },
        ),
      ],
    ),
  );
}

// 外观与显示分组
Widget _buildAppearanceSection(BuildContext context, WidgetRef ref) {
  final currentLanguage = ref.watch(languageProvider);
  final l10n = AppLocalizations.of(context);

  String languageDisplay;
  if (currentLanguage == null) {
    languageDisplay = l10n.languageSystemDefault;
  } else {
    switch (currentLanguage.languageCode) {
      case 'zh':
        languageDisplay = l10n.languageChinese;
        break;
      case 'en':
        languageDisplay = l10n.languageEnglish;
        break;
      default:
        languageDisplay = currentLanguage.languageCode;
    }
  }

  return SectionCard(
    margin: EdgeInsets.fromLTRB(
        12.0.scaled(context, ref), 0, 12.0.scaled(context, ref), 0),
    child: Column(
      children: [
        // 桌面小组件
        AppListTile(
          leading: Icons.widgets_outlined,
          title: l10n.widgetManagement,
          subtitle: l10n.widgetManagementDesc,
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'NEW',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WidgetManagementPage()),
            );
          },
        ),
        BeeDivider.thin(),
        // 个性化
        AppListTile(
          leading: Icons.brush_outlined,
          title: AppLocalizations.of(context).minePersonalize,
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PersonalizePage()),
            );
          },
        ),
        BeeDivider.thin(),
        // 显示缩放
        AppListTile(
          leading: Icons.zoom_out_map_outlined,
          title: AppLocalizations.of(context).mineDisplayScale,
          subtitle: AppLocalizations.of(context).mineDisplayScaleSubtitle,
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FontSettingsPage()),
            );
          },
        ),
        BeeDivider.thin(),
        // 语言设置
        AppListTile(
          leading: Icons.language_outlined,
          title: l10n.mineLanguageSettings,
          subtitle: languageDisplay,
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LanguageSettingsPage()),
            );
          },
        ),
      ],
    ),
  );
}

// -------- 工具方法：关于与更新 --------
class _AppInfo {
  final String version;
  final String buildNumber;
  final String? commit;
  final String? buildTime;
  const _AppInfo(this.version, this.buildNumber, {this.commit, this.buildTime});
}

// 优先读取 CI 注入的 dart-define（CI_VERSION/GIT_COMMIT/BUILD_TIME），否则回退 PackageInfo
Future<_AppInfo> _getAppInfo() async {
  final p = await PackageInfo.fromPlatform();
  final commit = const String.fromEnvironment('GIT_COMMIT');
  final buildTime = const String.fromEnvironment('BUILD_TIME');
  final ciVersion = const String.fromEnvironment('CI_VERSION');

  // 版本号策略：CI版本优先，本地开发显示 "dev-{pubspec版本}"
  final version =
      ciVersion.isNotEmpty ? ciVersion : 'dev-${p.version}'; // 本地开发版本标识

  return _AppInfo(version, p.buildNumber,
      commit: commit.isEmpty ? null : commit,
      buildTime: buildTime.isEmpty ? null : buildTime);
}

/// 尝试使用多种方式打开URL，提供更好的兼容性
Future<bool> _tryOpenUrl(Uri url) async {
  try {
    // 方式1: 默认外部应用打开
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
      return true;
    }

    // 方式2: 浏览器内打开
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalNonBrowserApplication);
      return true;
    }

    // 方式3: 平台默认方式
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.platformDefault);
      return true;
    }

    logger.error('MinePage', '无法打开URL: $url');
    return false;
  } catch (e) {
    logger.error('MinePage', '打开URL失败: $url', e);
    return false;
  }
}

/// 请求应用评分
///
/// iOS系统对原生评分弹窗有限制：
/// 1. 每365天最多弹出3次
/// 2. 模拟器上不显示
/// 3. 用户可在系统设置中禁用
///
/// 因此直接打开App Store评分页面更可靠
Future<void> _rateApp(BuildContext context) async {
  try {
    final InAppReview inAppReview = InAppReview.instance;

    // 直接打开应用商店评分页面（更可靠，不受系统限制）
    if (Platform.isIOS) {
      await inAppReview.openStoreListing(
        appStoreId: '6754611670', // BeeCount的App Store ID
      );
      logger.info('MinePage', '已打开App Store评分页面');
    } else {
      // Android会自动打开Google Play（如果已上架）
      await inAppReview.openStoreListing();
      logger.info('MinePage', '已打开Google Play评分页面');
    }
  } catch (e) {
    logger.error('MinePage', '打开评分失败', e);
    // 失败时不显示错误提示，静默失败
  }
}

/// 我的页面头部
class _MinePageHeader extends ConsumerStatefulWidget {
  const _MinePageHeader();

  @override
  ConsumerState<_MinePageHeader> createState() => _MinePageHeaderState();
}

class _MinePageHeaderState extends ConsumerState<_MinePageHeader> {
  String? _avatarPath;
  bool _isLoadingAvatar = true;

  @override
  void initState() {
    super.initState();
    _loadAvatar();
  }

  Future<void> _loadAvatar() async {
    final path = await AvatarService.getAvatarPath();
    if (mounted) {
      setState(() {
        _avatarPath = path;
        _isLoadingAvatar = false;
      });
    }
  }

  Future<void> _showAvatarOptions() async {
    final l10n = AppLocalizations.of(context);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.mineAvatarTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(l10n.mineAvatarFromGallery),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: Text(l10n.mineAvatarFromCamera),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            if (_avatarPath != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: Text(l10n.mineAvatarDelete,
                    style: const TextStyle(color: Colors.red)),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonCancel),
          ),
        ],
      ),
    );

    if (result == null || !mounted) return;

    try {
      if (result == 'gallery') {
        final path = await AvatarService.pickAndSaveAvatar();
        if (mounted && path != null) {
          setState(() => _avatarPath = path);
        }
      } else if (result == 'camera') {
        final path = await AvatarService.takePhotoAndSaveAvatar();
        if (mounted && path != null) {
          setState(() => _avatarPath = path);
        }
      } else if (result == 'delete') {
        await AvatarService.deleteAvatar();
        if (mounted) {
          setState(() => _avatarPath = null);
        }
      }
    } catch (e) {
      if (!mounted) return;
      showToast(context, '${AppLocalizations.of(context).commonError}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 头像功能不受云同步限制，任何时候都可以上传
    final canEditAvatar = true;

    // 获取当前账本信息
    final currentLedgerId = ref.watch(currentLedgerIdProvider);
    final countsAsync = ref.watch(countsForLedgerProvider(currentLedgerId));
    final balanceAsync = ref.watch(currentBalanceProvider(currentLedgerId));
    final currentLedgerAsync = ref.watch(currentLedgerProvider);

    final day = countsAsync.asData?.value.dayCount ?? 0;
    final tx = countsAsync.asData?.value.txCount ?? 0;
    final balance = balanceAsync.asData?.value ?? 0.0;
    final currencyCode = currentLedgerAsync.asData?.value?.currency ?? 'CNY';

    // 统计信息文字颜色
    final labelStyle = Theme.of(context)
        .textTheme
        .labelMedium
        ?.copyWith(color: BeeTokens.textSecondary(context));
    final numStyle = BeeTextTokens.strongTitle(context)
        .copyWith(fontSize: 20, color: BeeTokens.textPrimary(context));

    return Padding(
      padding: EdgeInsets.fromLTRB(
        12.0.scaled(context, ref),
        12.0.scaled(context, ref),
        12.0.scaled(context, ref),
        10.0.scaled(context, ref),
      ),
      child: Column(
        children: [
          // 头像/Logo
          GestureDetector(
            onTap: canEditAvatar ? _showAvatarOptions : null,
            child: Stack(
              children: [
                Container(
                  width: 80.0.scaled(context, ref),
                  height: 80.0.scaled(context, ref),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.1),
                    border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: ClipOval(
                    child: _isLoadingAvatar
                        ? Center(
                            child: SizedBox(
                              width: 20.0.scaled(context, ref),
                              height: 20.0.scaled(context, ref),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          )
                        : (_avatarPath != null
                            ? Image.file(
                                File(_avatarPath!),
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return BeeIcon(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    size: 40.0.scaled(context, ref),
                                  );
                                },
                              )
                            : BeeIcon(
                                color: Theme.of(context).colorScheme.primary,
                                size: 40.0.scaled(context, ref),
                              )),
                  ),
                ),
                if (canEditAvatar)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 24.0.scaled(context, ref),
                      height: 24.0.scaled(context, ref),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Icon(
                        Icons.camera_alt,
                        size: 12.0.scaled(context, ref),
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: 12.0.scaled(context, ref)),
          // Slogan
          Text(
            AppLocalizations.of(context).mineSlogan,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: BeeTokens.textPrimary(context), // ⭐ 使用 Token
                  fontWeight: FontWeight.w600,
                ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 16.0.scaled(context, ref)),
          // 统计数据
          Row(
            children: [
              Expanded(
                child: _StatCell(
                  label: AppLocalizations.of(context).mineDaysCount,
                  value: day.toString(),
                  labelStyle: labelStyle,
                  numStyle: numStyle,
                  centered: true,
                ),
              ),
              Expanded(
                child: _StatCell(
                  label: AppLocalizations.of(context).mineTotalRecords,
                  value: tx.toString(),
                  labelStyle: labelStyle,
                  numStyle: numStyle,
                  centered: true,
                ),
              ),
              Expanded(
                child: _StatCell(
                  label: AppLocalizations.of(context).mineCurrentBalance,
                  value: balance,
                  isAmount: true,
                  currencyCode: currencyCode,
                  labelStyle: labelStyle,
                  numStyle: numStyle.copyWith(
                    color: balance >= 0
                        ? BeeTokens.textPrimary(context)
                        : BeeTokens.error(context),
                  ),
                  centered: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
