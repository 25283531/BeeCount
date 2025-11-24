import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/automation/ocr_service.dart';
import '../../services/automation/bill_creation_service.dart';
import '../../widgets/ui/ui.dart';
import '../../styles/tokens.dart';
import '../../providers.dart';
import '../../data/db.dart';
import '../../l10n/app_localizations.dart';

/// OCR扫描记账页面
class OcrBillingPage extends ConsumerStatefulWidget {
  const OcrBillingPage({super.key});

  @override
  ConsumerState<OcrBillingPage> createState() => _OcrBillingPageState();
}

class _OcrBillingPageState extends ConsumerState<OcrBillingPage> {
  final _ocrService = OcrService();
  final _imagePicker = ImagePicker();

  File? _selectedImage;
  OcrResult? _ocrResult;
  bool _isProcessing = false;
  String? _selectedAmount;

  @override
  void dispose() {
    _ocrService.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
          _ocrResult = null;
          _selectedAmount = null;
        });

        await _processImage();
      }
    } catch (e) {
      if (!mounted) return;
      _showError('选择图片失败: $e');
    }
  }

  Future<void> _processImage() async {
    if (_selectedImage == null) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      // 获取数据库实例
      final db = ref.read(databaseProvider);

      // OCR识别（包含AI增强）
      final ocrResult = await _ocrService.recognizePaymentImage(
        _selectedImage!,
        db: db,
      );

      // 使用BillCreationService匹配分类
      final billCreationService = BillCreationService(db);

      final categoryKind =
          (ocrResult.aiType == 'income') ? 'income' : 'expense';
      final categories =
          await billCreationService.getCategoriesByType(categoryKind);
      final suggestedCategoryId =
          await billCreationService.matchCategory(ocrResult, categories);

      // 使用AI增强的结果，只补充分类ID
      final result = OcrResult(
        amount: ocrResult.amount,
        merchant: ocrResult.merchant,
        time: ocrResult.time,
        rawText: ocrResult.rawText,
        allNumbers: ocrResult.allNumbers,
        suggestedCategoryId: suggestedCategoryId,
        aiCategoryName: ocrResult.aiCategoryName,
        aiType: ocrResult.aiType,
        aiProvider: ocrResult.aiProvider,
        aiEnhanced: ocrResult.aiEnhanced,
      );

      setState(() {
        _ocrResult = result;
        // 在 allNumbers 中查找匹配的金额字符串
        if (result.amount != null) {
          final targetAmount = result.amount!.abs();
          _selectedAmount = result.allNumbers.firstWhere(
            (numStr) {
              final num = double.tryParse(numStr);
              return num != null && (num - targetAmount).abs() < 0.01;
            },
            orElse: () => targetAmount.toString(),
          );
        }
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      _showError(l10n.aiOcrFailed(e.toString()));
    }
  }

  void _showError(String message) {
    showToast(context, message);
  }

  Future<Category?> _getCategory(int categoryId) async {
    final db = ref.read(databaseProvider);
    return await (db.select(db.categories)
          ..where((t) => t.id.equals(categoryId)))
        .getSingleOrNull();
  }

  Future<void> _createTransaction() async {
    if (_selectedAmount == null || _selectedAmount!.isEmpty) {
      _showError('请选择或输入金额');
      return;
    }

    final amount = double.tryParse(_selectedAmount!);
    if (amount == null || amount <= 0) {
      _showError('请输入有效金额');
      return;
    }

    try {
      // 获取当前账本
      final currentLedger = await ref.read(currentLedgerProvider.future);
      if (currentLedger == null) {
        if (!mounted) return;
        showToast(context, '未找到账本');
        return;
      }

      // 构造OcrResult用于创建交易
      final ocrResultForCreation = OcrResult(
        amount: (_ocrResult?.aiType == 'income') ? amount : -amount,
        merchant: _ocrResult?.merchant,
        time: _ocrResult?.time,
        rawText: _ocrResult?.rawText ?? '',
        allNumbers: _ocrResult?.allNumbers ?? [],
        suggestedCategoryId: _ocrResult?.suggestedCategoryId,
        aiCategoryName: _ocrResult?.aiCategoryName,
        aiType: _ocrResult?.aiType,
        aiProvider: _ocrResult?.aiProvider,
        aiEnhanced: _ocrResult?.aiEnhanced ?? false,
      );

      // 使用BillCreationService创建交易
      final db = ref.read(databaseProvider);
      final billCreationService = BillCreationService(db);

      final note = _ocrResult?.merchant ?? '';
      final transactionId = await billCreationService.createBillTransaction(
        result: ocrResultForCreation,
        ledgerId: currentLedger.id,
        note: note.isNotEmpty ? note : null,
      );

      if (!mounted) return;

      if (transactionId != null) {
        // 显示成功提示
        final l10n = AppLocalizations.of(context);
        final transactionKind =
            (_ocrResult?.aiType == 'income') ? 'income' : 'expense';
        final typeText = transactionKind == 'income'
            ? l10n.aiTypeIncome
            : l10n.aiTypeExpense;
        // 使用用户最终选择的金额而不是默认金额
        final finalAmount = amount.toStringAsFixed(2);
        showToast(context, l10n.aiOcrSuccess(typeText, finalAmount));

        // 返回上一页
        Navigator.of(context).pop();
      } else {
        final l10n = AppLocalizations.of(context);
        showToast(context, l10n.aiOcrCreateFailed);
      }
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      showToast(context, l10n.aiOcrFailed(e.toString()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final primaryColor = ref.watch(primaryColorProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.ocrBilling,
            showBack: true,
          ),
          Expanded(
            child: _selectedImage == null
                ? _buildImagePicker(context, theme, l10n)
                : _buildResult(context, theme, l10n, primaryColor),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePicker(
      BuildContext context, ThemeData theme, AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_search,
            size: 80,
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 24),
          Text(
            '选择支付截图',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text(
            '支持识别支付宝、微信支付截图',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildPickButton(
                context,
                icon: Icons.photo_library,
                label: '从相册选择',
                onTap: () => _pickImage(ImageSource.gallery),
              ),
              const SizedBox(width: 24),
              _buildPickButton(
                context,
                icon: Icons.camera_alt,
                label: '拍照',
                onTap: () => _pickImage(ImageSource.camera),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPickButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult(BuildContext context, ThemeData theme,
      AppLocalizations l10n, Color primaryColor) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 图片预览
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                _selectedImage!,
                height: 300,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 16),

            // 重新选择按钮
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _selectedImage = null;
                  _ocrResult = null;
                  _selectedAmount = null;
                });
              },
              icon: const Icon(Icons.refresh),
              label: Text(l10n.reselectImage),
            ),
            const SizedBox(height: 24),

            // 识别中或结果
            if (_isProcessing)
              Center(
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      '正在识别...',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              )
            else if (_ocrResult != null) ...[
              _buildResultCard(context, theme, l10n, primaryColor),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(BuildContext context, ThemeData theme,
      AppLocalizations l10n, Color primaryColor) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.ocrRecognitionResult,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // 金额选择
            Text(
              l10n.ocrAmount,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),

            if (_ocrResult!.allNumbers.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _ocrResult!.allNumbers.map((number) {
                  final isSelected = _selectedAmount == number;
                  return ChoiceChip(
                    label: Text('¥$number'),
                    selected: isSelected,
                    showCheckmark: isSelected,
                    selectedColor: primaryColor,
                    backgroundColor: BeeTokens.surfaceElevated(context),
                    disabledColor: BeeTokens.surfaceElevated(context),
                    checkmarkColor: theme.colorScheme.onSurface,
                    labelStyle: TextStyle(
                      color: theme.colorScheme.onSurface,
                    ),
                    side: BorderSide(
                      color: primaryColor.withValues(alpha: 0.2),
                      width: 1,
                    ),
                    onSelected: (selected) {
                      setState(() {
                        _selectedAmount = selected ? number : null;
                      });
                    },
                  );
                }).toList(),
              ),
            ] else ...[
              Text(
                l10n.ocrNoAmountDetected,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.orange,
                ),
              ),
            ],

            // 手动输入金额
            const SizedBox(height: 16),
            TextField(
              decoration: InputDecoration(
                labelText: l10n.ocrManualAmountInput,
                prefixText: '¥',
                border: const OutlineInputBorder(),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (value) {
                setState(() {
                  _selectedAmount = value;
                });
              },
            ),

            // 商家名称
            if (_ocrResult!.merchant != null) ...[
              const SizedBox(height: 16),
              Text(
                l10n.ocrMerchant,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _ocrResult!.merchant!,
                style: theme.textTheme.bodyLarge,
              ),
            ],

            // 推荐分类
            if (_ocrResult!.suggestedCategoryId != null) ...[
              const SizedBox(height: 16),
              FutureBuilder<Category?>(
                future: _getCategory(_ocrResult!.suggestedCategoryId!),
                builder: (context, snapshot) {
                  if (snapshot.hasData && snapshot.data != null) {
                    final category = snapshot.data!;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.ocrSuggestedCategory,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: ref.watch(primaryColorProvider),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                size: 16,
                                color: Colors.black,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                category.name,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],

            // 时间
            if (_ocrResult!.time != null) ...[
              const SizedBox(height: 16),
              Text(
                l10n.ocrTime,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_ocrResult!.time!.year}-${_ocrResult!.time!.month.toString().padLeft(2, '0')}-${_ocrResult!.time!.day.toString().padLeft(2, '0')} ${_ocrResult!.time!.hour.toString().padLeft(2, '0')}:${_ocrResult!.time!.minute.toString().padLeft(2, '0')}',
                style: theme.textTheme.bodyLarge,
              ),
            ],

            // 原始文本（折叠）
            const SizedBox(height: 16),
            Theme(
              data: theme.copyWith(
                dividerColor: Colors.transparent,
                expansionTileTheme: ExpansionTileThemeData(
                  iconColor: primaryColor,
                  collapsedIconColor:
                      theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  textColor: primaryColor,
                  collapsedTextColor: theme.colorScheme.onSurface,
                ),
              ),
              child: ExpansionTile(
                title: Text(l10n.viewOriginalText),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _ocrResult!.rawText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 创建账单按钮
            FilledButton(
              onPressed: _createTransaction,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
              child: Text(l10n.createBill),
            ),
          ],
        ),
      ),
    );
  }
}
