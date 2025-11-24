import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/biz/biz.dart';
import '../../styles/tokens.dart';
import '../ai/ai_settings_page.dart';
import '../automation/ocr_billing_page.dart';
import '../automation/voice_billing_page.dart';
import '../automation/auto_billing_settings_page.dart';
import '../../l10n/app_localizations.dart';

/// 智能记账二级页面
class SmartBillingPage extends ConsumerWidget {
  const SmartBillingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final cameraFirst = ref.watch(fabCameraFirstProvider).value ?? false;

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.smartBillingPageTitle,
            subtitle: l10n.smartBillingPageSubtitle,
            showBack: true,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SectionCard(
                  margin: EdgeInsets.zero,
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
                      BeeTokens.cardDivider(context),
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
                      BeeTokens.cardDivider(context),
                      AppListTile(
                        leading: Icons.mic_none,
                        title: l10n.voiceBilling,
                        subtitle: l10n.voiceBillingDesc,
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
                            MaterialPageRoute(builder: (_) => const VoiceBillingPage()),
                          );
                        },
                      ),
                      BeeTokens.cardDivider(context),
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
                            MaterialPageRoute(builder: (_) => const AutoBillingSettingsPage()),
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
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
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
                                        color: BeeTokens.textPrimary(context),
                                      ),
                                    ),
                                    Text(
                                      cameraFirst ? l10n.aiFabSettingDescCamera : l10n.aiFabSettingDescManual,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: BeeTokens.textSecondary(context),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: cameraFirst,
                                onChanged: (value) async {
                                  await ref.read(fabBehaviorSetterProvider).setCameraFirst(value);
                                  ref.invalidate(fabCameraFirstProvider);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
