import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

import 'pages/main/home_page.dart';
import 'providers/theme_providers.dart';
import 'pages/main/analytics_page.dart';
import 'pages/main/ledgers_page_new.dart';
import 'pages/main/mine_page.dart';
import 'pages/transaction/transaction_editor_page.dart';
import 'pages/settings/personalize_page.dart' show headerStyleProvider;
import 'providers.dart';
import 'utils/ui_scale_extensions.dart';
import 'l10n/app_localizations.dart';
import 'widget/widget_manager.dart';
import 'services/automation/ocr_service.dart';
import 'services/automation/bill_creation_service.dart';
import 'widgets/ui/ui.dart';
import 'cloud/transactions_sync_manager.dart';

class BeeApp extends ConsumerStatefulWidget {
  const BeeApp({super.key});

  @override
  ConsumerState<BeeApp> createState() => _BeeAppState();
}

class _BeeAppState extends ConsumerState<BeeApp> with WidgetsBindingObserver {
  final _pages = const [
    HomePage(),
    AnalyticsPage(),
    LedgersPageNew(),
    MinePage(),
  ];

  // 双击检测：记录最后一次点击的时间和索引
  DateTime? _lastTapTime;
  int? _lastTappedIndex;

  // 双击返回退出：记录最后一次返回键按下时间
  DateTime? _lastBackPressTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 后台刷新账本同步状态
    _refreshLedgersStatusInBackground();
  }

  /// 后台刷新账本同步状态
  void _refreshLedgersStatusInBackground() {
    Future.microtask(() async {
      try {
        final syncService = ref.read(syncServiceProvider);
        if (syncService is TransactionsSyncManager) {
          await syncService.refreshAllLedgersStatus();
          // 刷新完成后触发账本列表更新
          ref.read(ledgerListRefreshProvider.notifier).state++;
        }
      } catch (e) {
        // 静默失败，不影响App启动
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 当app从后台恢复到前台时，更新小组件数据
    if (state == AppLifecycleState.resumed) {
      _updateWidget();
    }
  }

  Future<void> _updateWidget() async {
    try {
      final repository = ref.read(repositoryProvider);
      final ledgerId = ref.read(currentLedgerIdProvider);
      final primaryColor = ref.read(primaryColorProvider);

      final widgetManager = WidgetManager();
      await widgetManager.updateWidget(repository, ledgerId, primaryColor);
      print('✅ App恢复前台，小组件数据已更新');
    } catch (e) {
      print('❌ 更新小组件失败: $e');
    }
  }

  /// 打开相机拍照并自动记账
  Future<void> _openCameraForBilling(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);

    try {
      // 打开相机拍照
      final imagePicker = ImagePicker();
      final pickedFile = await imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (pickedFile == null) {
        // 用户取消拍照
        return;
      }

      if (!context.mounted) return;

      // 显示加载提示
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(l10n.aiOcrRecognizing),
                ],
              ),
            ),
          ),
        ),
      );

      // OCR识别
      final ocrService = OcrService();
      final imageFile = File(pickedFile.path);
      final ocrResult = await ocrService.recognizePaymentImage(imageFile);

      if (!context.mounted) return;

      // 关闭加载提示
      Navigator.of(context).pop();

      // 验证识别结果
      if (ocrResult.amount == null || ocrResult.amount!.abs() <= 0) {
        showToast(context, l10n.aiOcrNoAmount);
        return;
      }

      // 获取当前账本
      final currentLedger = await ref.read(currentLedgerProvider.future);
      if (currentLedger == null) {
        if (!context.mounted) return;
        showToast(context, l10n.aiOcrNoLedger);
        return;
      }

      // 使用BillCreationService创建交易
      final db = ref.read(databaseProvider);
      final billCreationService = BillCreationService(db);

      final note = ocrResult.merchant ?? '';
      final transactionId = await billCreationService.createBillTransaction(
        result: ocrResult,
        ledgerId: currentLedger.id,
        note: note.isNotEmpty ? note : null,
      );

      if (!context.mounted) return;

      if (transactionId != null) {
        final transactionType = (ocrResult.aiType == 'income') ? 'income' : 'expense';
        final typeText = transactionType == 'income' ? l10n.aiTypeIncome : l10n.aiTypeExpense;
        final amount = ocrResult.amount!.abs().toStringAsFixed(2);
        showToast(context, l10n.aiOcrSuccess(typeText, amount));
      } else {
        showToast(context, l10n.aiOcrCreateFailed);
      }
    } catch (e) {
      if (!context.mounted) return;
      // 尝试关闭可能还在显示的加载对话框
      Navigator.of(context).popUntil((route) => route.isFirst);
      showToast(context, l10n.aiOcrFailed(e.toString()));
    }
  }

  @override
  Widget build(BuildContext context) {
    // 将 4 个页面映射到 5 槽位（中间为“+”）：页面索引 0,1,2,3 对应视觉槽位 0,1,3,4（槽位 2 为 +）。
    final idx = ref.watch(bottomTabIndexProvider);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        // 拦截根路由的返回键，避免意外将根路由 pop 到空导致黑屏。
        // 实现双击返回退出应用逻辑
        if (didPop) return;

        final now = DateTime.now();
        final l10n = AppLocalizations.of(context);

        if (_lastBackPressTime == null ||
            now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
          // 第一次按返回键，显示提示并记录时间
          _lastBackPressTime = now;
          showToast(context, l10n.commonPressAgainToExit);
        } else {
          // 2秒内第二次按返回键，退出应用
          SystemNavigator.pop();
        }
      },
      child: Stack(
        children: [
          Scaffold(
            body: IndexedStack(
              index: idx,
              children: _pages,
            ),
            bottomNavigationBar: BottomAppBar(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1C1C1E)  // ⭐ 暗黑模式：深灰（与卡片同色）
              : Colors.white,             // 亮色模式：白色
          shape: null,  // ⭐ 去掉凹口设计
          notchMargin: 0,
          elevation: 8,  // ⭐ 保持阴影，让Tab栏突起
          child: SizedBox(
            height: 60.0.scaled(context, ref),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(5, (i) {
                if (i == 2) {
                  // 中间预留给 FAB 的槽位，确保 5 等分
                  return const Expanded(child: SizedBox());
                }
                // 槽位转页面索引
                final pageIndex = i > 2 ? i - 1 : i;
                final activeVisualIndex = idx >= 2 ? idx + 1 : idx;
                final active = activeVisualIndex == i;
                final isDark = Theme.of(context).brightness == Brightness.dark;
                Color color = active
                    ? Theme.of(context).colorScheme.primary
                    : (isDark ? Colors.white70 : Colors.black54); // ⭐ 自适应未选中颜色
                IconData icon;
                String label;
                final l10n = AppLocalizations.of(context);
                switch (pageIndex) {
                  case 0:
                    icon = Icons.list_alt_rounded;
                    label = l10n.tabHome;
                    break;
                  case 1:
                    icon = Icons.pie_chart_rounded;
                    label = l10n.tabAnalytics;
                    break;
                  case 2:
                    icon = Icons.menu_book_rounded;
                    label = l10n.tabLedgers;
                    break;
                  default:
                    icon = Icons.person_rounded;
                    label = l10n.tabMine;
                }
                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      final now = DateTime.now();
                      // 检测双击：同一个标签在300ms内连续点击两次
                      if (_lastTappedIndex == pageIndex &&
                          _lastTapTime != null &&
                          now.difference(_lastTapTime!) < const Duration(milliseconds: 300)) {
                        // 双击首页标签，触发滚动到顶部
                        if (pageIndex == 0) {
                          ref.read(homeScrollToTopProvider.notifier).state++;
                        }
                        // 重置双击状态
                        _lastTapTime = null;
                        _lastTappedIndex = null;
                      } else {
                        // 记录本次点击
                        _lastTapTime = now;
                        _lastTappedIndex = pageIndex;
                        // 切换标签
                        ref.read(bottomTabIndexProvider.notifier).state = pageIndex;
                      }
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        vertical: 8.0.scaled(context, ref),
                        horizontal: 4.0.scaled(context, ref),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon, color: color, size: 24),
                          SizedBox(height: 4.0.scaled(context, ref)),
                          Text(label,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: color,
                                  fontWeight: active
                                      ? FontWeight.w600
                                      : FontWeight.w400)),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
        floatingActionButton: Consumer(builder: (context, ref, _) {
          final style = ref.watch(headerStyleProvider);
          final color = Theme.of(context).colorScheme.primary;
          final cameraFirst = ref.watch(fabCameraFirstProvider).value ?? false;
          final tipDismissed = ref.watch(fabLongPressTipDismissedProvider).value ?? true;
          final l10n = AppLocalizations.of(context);

          // 根据设置决定图标：拍照优先显示相机，手动优先显示+号
          final icon = cameraFirst ? Icons.camera_alt : Icons.add;

          // 只有在手动优先模式下才显示长按拍照提示
          final showTip = !cameraFirst && !tipDismissed;

          return SizedBox(
            width: showTip ? 200.0.scaled(context, ref) : 80.0.scaled(context, ref),
            height: showTip ? 140.0.scaled(context, ref) : 80.0.scaled(context, ref),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.bottomCenter,
              children: [
                // FAB 按钮
                Positioned(
                  bottom: 0,
                  child: SizedBox(
                    width: 80.0.scaled(context, ref),
                    height: 80.0.scaled(context, ref),
                    child: GestureDetector(
                      onLongPress: () async {
                        // 长按行为：与短按相反
                        if (cameraFirst) {
                          // 拍照优先模式：长按打开手动记账
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const TransactionEditorPage(
                                initialKind: 'expense',
                                quickAdd: true,
                              ),
                            ),
                          );
                        } else {
                          // 手动优先模式：长按打开拍照记账
                          // 关闭提示
                          if (!tipDismissed) {
                            await ref.read(fabTipSetterProvider).dismiss();
                            ref.invalidate(fabLongPressTipDismissedProvider);
                          }
                          await _openCameraForBilling(context, ref);
                        }
                      },
                      child: FloatingActionButton(
                        heroTag: 'addFab',
                        elevation: 8,  // ⭐ 保持阴影
                        shape: const CircleBorder(),
                        backgroundColor: style == 'primary' ? color : color,  // ⭐ 主题色背景
                        onPressed: () async {
                          // 短按行为：根据设置决定
                          if (cameraFirst) {
                            // 拍照优先模式：短按打开拍照记账
                            await _openCameraForBilling(context, ref);
                          } else {
                            // 手动优先模式：短按打开手动记账
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const TransactionEditorPage(
                                  initialKind: 'expense',
                                  quickAdd: true,
                                ),
                              ),
                            );
                          }
                        },
                        child: Icon(icon, color: Colors.white, size: 34.0.scaled(context, ref)),
                      ),
                    ),
                  ),
                ),
                // 长按提示气泡（带箭头和呼吸动画）
                if (showTip)
                  Positioned(
                    top: 0,
                    child: _FabTipBubble(
                      text: l10n.fabLongPressTip,
                      primaryColor: color,
                      onDismiss: () async {
                        await ref.read(fabTipSetterProvider).dismiss();
                        ref.invalidate(fabLongPressTipDismissedProvider);
                      },
                    ),
                  ),
              ],
            ),
          );
        }),
            floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
          ),
          // 开发模式下的主题切换按钮
          if (kDebugMode)
            Positioned(
              right: 16,
              bottom: 100,
              child: FloatingActionButton.small(
                heroTag: 'themeSwitcher',
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black,
                onPressed: () {
                  final current = ref.read(themeModeProvider);
                  final next = current == ThemeMode.dark
                      ? ThemeMode.light
                      : ThemeMode.dark;
                  ref.read(themeModeProvider.notifier).state = next;
                },
                child: Icon(
                  Theme.of(context).brightness == Brightness.dark
                      ? Icons.light_mode
                      : Icons.dark_mode,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.black
                      : Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// FAB 长按提示气泡组件（带箭头和呼吸动画）
class _FabTipBubble extends StatefulWidget {
  final String text;
  final Color primaryColor;
  final VoidCallback onDismiss;

  const _FabTipBubble({
    required this.text,
    required this.primaryColor,
    required this.onDismiss,
  });

  @override
  State<_FabTipBubble> createState() => _FabTipBubbleState();
}

class _FabTipBubbleState extends State<_FabTipBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _opacityAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = widget.primaryColor;

    return AnimatedBuilder(
      animation: _opacityAnimation,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityAnimation.value,
          child: child,
        );
      },
      child: GestureDetector(
        onTap: widget.onDismiss,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 气泡主体
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: primaryColor.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.touch_app,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ],
              ),
            ),
            // 箭头指向 FAB
            CustomPaint(
              size: const Size(16, 10),
              painter: _ArrowPainter(color: primaryColor),
            ),
          ],
        ),
      ),
    );
  }
}

/// 箭头绘制器
class _ArrowPainter extends CustomPainter {
  final Color color;

  _ArrowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
