import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../styles/tokens.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../services/automation/asr_service.dart';
import '../../services/automation/ocr_service.dart';
import '../../services/automation/ai_bill_service.dart';
import '../../services/automation/bill_creation_service.dart';
import '../../providers.dart';
import '../../data/db.dart';

class VoiceBillingPage extends ConsumerStatefulWidget {
  const VoiceBillingPage({super.key});

  @override
  ConsumerState<VoiceBillingPage> createState() => _VoiceBillingPageState();
}

class _VoiceBillingPageState extends ConsumerState<VoiceBillingPage> {
  final AsrService _asr = AsrService();
  final OcrService _ocrService = OcrService();
  final AIBillService _aiBillService = AIBillService();
  
  bool _initializing = true;
  bool _recording = false;
  bool _isProcessing = false;
  String _partialText = '';
  String _finalText = '';
  String _statusMessage = '';
  String? _errorMessage;
  
  // 解析结果
  OcrResult? _parsedResult;
  String? _selectedAmount;
  
  // 用于动画的音量值
  double _currentVolume = 0.0;
  Timer? _volumeTimer;

  @override
  void initState() {
    super.initState();
    _checkVoiceRecognitionPermission();
    _setupVolumeAnimation();
  }

  Future<void> _checkVoiceRecognitionPermission() async {
    final prefs = await SharedPreferences.getInstance();
    final voiceRecognitionEnabled = prefs.getBool('voice_recognition_enabled') ?? true;
    
    if (voiceRecognitionEnabled) {
      _initAsr();
    } else {
      setState(() {
        _initializing = false;
        _statusMessage = '语音识别功能已关闭，请在设置中开启';
      });
    }
  }
  
  void _setupVolumeAnimation() {
    // 创建模拟音量动画的定时器
    _volumeTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) return;
      if (_recording) {
        // 随机波动模拟音量变化
        setState(() {
          _currentVolume = (_currentVolume + (0.1 * (DateTime.now().millisecond % 3 - 1))).clamp(0.0, 1.0);
        });
      } else {
        // 录音停止时音量逐渐降低
        setState(() {
          _currentVolume = (_currentVolume - 0.05).clamp(0.0, 1.0);
        });
      }
    });
  }

  Future<void> _initAsr() async {
    setState(() {
      _statusMessage = '正在初始化语音识别...';
      _initializing = true;
    });
    
    try {
      await _asr.initialize(modelName: 'vosk-model-small-cn-0.22');
      
      // 设置流监听
      _asr.partialResultStream.listen((text) {
        if (mounted) {
          setState(() {
            _partialText = text;
          });
        }
      });
      
      _asr.recognizedTextStream.listen((text) async {
        if (mounted) {
          setState(() {
            _finalText = text;
            _partialText = '';
            _recording = false;
            _statusMessage = '识别完成，点击下方按钮进行解析';
          });
        }
      });
      
      _asr.errorStream.listen((error) {
        if (mounted) {
          _showError('语音识别错误: $error');
          setState(() {
            _errorMessage = error;
            _statusMessage = '发生错误';
            _recording = false;
          });
        }
      });
      
      setState(() {
        _initializing = false;
        _statusMessage = '准备就绪，请说出账单信息';
      });
    } catch (e) {
      _showError('初始化失败: $e');
      setState(() {
        _initializing = false;
        _statusMessage = '初始化失败，请重试';
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _toggleRecord() async {
    if (_isProcessing) return;
    
    if (_recording) {
      await _asr.stopRecording();
      setState(() {
        _recording = false;
        _statusMessage = '录音已停止，识别中...';
      });
    } else {
      // 重置状态
      setState(() {
        _partialText = '';
        _finalText = '';
        _parsedResult = null;
        _selectedAmount = null;
        _errorMessage = null;
        _statusMessage = '正在录音，请说话...';
      });
      
      try {
        await _asr.startRecording();
        setState(() {
          _recording = true;
        });
      } catch (e) {
        _showError('启动录音失败: $e');
        setState(() {
          _statusMessage = '录音启动失败';
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _parseAndProceed() async {
    final text = _finalText.isNotEmpty ? _finalText : _partialText;
    if (text.trim().isEmpty) {
      _showError('没有可解析的文本');
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = '正在解析账单信息...';
      _errorMessage = null;
    });

    try {
      
      // 1. 针对语音识别文本的增强解析
      final voiceEnhancedText = _enhanceVoiceText(text);
      
      // 2. 使用OCR服务的parsePaymentText函数解析基础信息
      final parsedResult = _ocrService.parsePaymentText(voiceEnhancedText);
      
      // 3. 增强对语音文本的解析结果
      final voiceParsedResult = _parseVoiceRecognitionResult(text, parsedResult);
      
      // 4. 尝试使用AI增强解析（可选）
      final prefs = await SharedPreferences.getInstance();
      final aiStrategy = prefs.getString('ai_strategy') ?? 'local_first';
      final aiBillExtractionEnabled = prefs.getBool('ai_bill_extraction_enabled') ?? false;
      
      OcrResult? enhancedResult = voiceParsedResult;
      
      // 只有在非local_only策略且启用了AI提取的情况下才使用AI增强
      if (aiStrategy != 'local_only' && aiBillExtractionEnabled) {
        try {
          // 获取分类信息用于AI增强
          final repository = ref.read(repositoryProvider);
          final expenseCats = await repository.getTopLevelCategories('expense');
          final incomeCats = await repository.getTopLevelCategories('income');
          
          // 构建更适合语音识别的AI提示词上下文（直接使用Map格式）
          
          final aiEnhancedResult = await _aiBillService.extractBillInfo(
              text,
              expenseCategories: expenseCats.map((c) => c.name).toList(),
              incomeCategories: incomeCats.map((c) => c.name).toList(),
            );
          
          // 更新增强的识别结果
          if (aiEnhancedResult != null) {
            enhancedResult = OcrResult(
              amount: aiEnhancedResult.amount ?? voiceParsedResult.amount,
              merchant: aiEnhancedResult.merchant ?? voiceParsedResult.merchant,
              time: aiEnhancedResult.time ?? voiceParsedResult.time,
              rawText: text,
              allNumbers: voiceParsedResult.allNumbers,
              suggestedCategoryId: null, // BillInfo没有提供分类ID，需要在后续处理
              aiCategoryName: aiEnhancedResult.category,
              aiType: aiEnhancedResult.type?.toString().split('.').last,
              aiProvider: null,
              aiEnhanced: true,
              aiAccountName: aiEnhancedResult.account,
            );
          }
        } catch (e) {
          debugPrint('⚠️ [AI增强] 解析失败: $e');
          // AI增强失败不影响基础解析结果的使用
        }
      }
      
      // 3. 使用BillCreationService匹配分类
      final db = ref.read(databaseProvider);
      final billCreationService = BillCreationService(db);
      final categoryKind = (enhancedResult?.aiType == 'income') ? 'income' : 'expense';
      final categories = await billCreationService.getCategoriesByType(categoryKind);
      final suggestedCategoryId = enhancedResult != null ? await billCreationService.matchCategory(enhancedResult, categories) : null;
      // 合并结果
      final finalResult = OcrResult(
        amount: enhancedResult?.amount,
        merchant: enhancedResult?.merchant,
        time: enhancedResult?.time,
        rawText: text,
        allNumbers: enhancedResult?.allNumbers ?? [],
        suggestedCategoryId: suggestedCategoryId,
        aiCategoryName: enhancedResult?.aiCategoryName,
        aiType: enhancedResult?.aiType,
        aiProvider: enhancedResult?.aiProvider,
        aiEnhanced: enhancedResult?.aiEnhanced ?? false,
        aiAccountName: enhancedResult?.aiAccountName,
      );
      
      if (mounted) {
        setState(() {
          _parsedResult = finalResult;
          // 默认选择第一个识别到的金额
          if (finalResult.allNumbers.isNotEmpty && _selectedAmount == null) {
            _selectedAmount = finalResult.allNumbers.first;
          } else if (finalResult.amount != null) {
            _selectedAmount = finalResult.amount.toString();
          }
          _statusMessage = '解析完成，请确认账单信息';
          _isProcessing = false;
        });
      }
    } catch (e) {
      debugPrint('❌ [解析] 失败: $e');
      if (mounted) {
        _showError('解析失败: $e');
        setState(() {
          _errorMessage = e.toString();
          _statusMessage = '解析失败';
          _isProcessing = false;
        });
      }
    }
  }
  
  Future<void> _createTransaction() async {
    if (_parsedResult == null || _selectedAmount == null || _selectedAmount!.isEmpty) {
      _showError('请确保已解析账单并选择金额');
      return;
    }
    
    setState(() {
      _isProcessing = true;
      _statusMessage = '正在创建账单...';
    });
    
    try {
      final db = ref.read(databaseProvider);
      final billCreationService = BillCreationService(db);
      
      // 验证金额有效性
      final amountValue = double.tryParse(_selectedAmount!);
      if (amountValue == null || amountValue <= 0) {
        throw Exception('无效的金额值');
      }
      
      // 构建更新后的OcrResult，包含选定的金额
      final updatedResult = OcrResult(
        amount: amountValue,
        merchant: _parsedResult!.merchant,
        time: _parsedResult!.time ?? DateTime.now(),
        rawText: _parsedResult!.rawText,
        allNumbers: _parsedResult!.allNumbers,
        suggestedCategoryId: _parsedResult!.suggestedCategoryId,
        aiCategoryName: _parsedResult!.aiCategoryName,
        aiType: _parsedResult!.aiType,
        aiProvider: _parsedResult!.aiProvider,
        aiEnhanced: _parsedResult!.aiEnhanced,
        aiAccountName: _parsedResult!.aiAccountName,
      );
      
      // 获取当前账本ID
      final ledger = ref.read(currentLedgerProvider).maybeWhen(
        data: (data) => data,
        orElse: () => null,
      );
      if (ledger == null) throw Exception('未找到当前账本');
      final ledgerId = ledger.id;
      
      // 创建交易
      final transactionId = await billCreationService.createBillTransaction(
        result: updatedResult,
        ledgerId: ledgerId,
        note: '语音记账创建 - ${DateTime.now().toString()}',
      );
      
      if (!mounted) return;
      
      if (transactionId != null) {
        // 增强数据刷新：确保所有相关数据都得到更新
        await _refreshAllRelatedData(ref, ledgerId);
        
        debugPrint('✅ 语音记账交易创建成功: ID=$transactionId');
      } else {
        throw Exception('交易创建失败，返回null ID');
      }
      
      // 显示成功消息
      _showSuccess('账单创建成功');
      
      // 重置状态，准备下一次记账
      _resetForNewBilling();
    } catch (e) {
      if (mounted) {
        debugPrint('❌ 交易创建失败: $e');
        _showError('创建账单失败: ${e.toString().split(':').last.trim()}');
        setState(() {
          _isProcessing = false;
          _statusMessage = '创建账单失败';
          _errorMessage = e.toString();
        });
      }
    }
  }
  
  /// 刷新所有相关数据
  Future<void> _refreshAllRelatedData(WidgetRef ref, int ledgerId) async {
    try {
      // 刷新统计数据
      ref.read(statsRefreshProvider.notifier).state++;
      
      // 刷新账本数据
      ref.invalidate(currentLedgerProvider);
      
      // 暂时注释掉同步状态刷新，以避免类型错误
      // 在未来版本中可以根据Provider的实际类型定义进行修复
      debugPrint('跳过同步状态刷新，等待Provider类型定义明确后实现');
      
      // 更新应用widget
      await updateAppWidget(ref, context);
      
      debugPrint('✅ 所有相关数据刷新完成');
    } catch (e) {
      debugPrint('⚠️ 数据刷新过程中出现错误: $e');
      // 数据刷新错误不影响主流程
    }
  }
  
  /// 重置状态，准备新的记账
  void _resetForNewBilling() {
    setState(() {
      _partialText = '';
      _finalText = '';
      _parsedResult = null;
      _selectedAmount = null;
      _statusMessage = '账单创建成功，可以继续记账';
      _isProcessing = false;
      _errorMessage = null;
      // 重置波形动画状态
    });
    
    // 如果正在录音，停止录音
    if (_recording) {
      _toggleRecord();
    }
  }
  
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ),
    );
  }
  
  void _showPrivacySettings() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return FutureBuilder<bool>(
          future: SharedPreferences.getInstance().then((prefs) => 
              prefs.getBool('voice_recognition_enabled') ?? true),
          builder: (context, snapshot) {
            final isEnabled = snapshot.data ?? true;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('语音识别功能'),
                  subtitle: const Text('启用后可使用麦克风进行语音识别'),
                  trailing: Switch(
                    value: isEnabled,
                    onChanged: (value) async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('voice_recognition_enabled', value);
                      Navigator.pop(context);
                        
                      // 显示设置已更改的提示
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(value 
                              ? '语音识别已开启'
                              : '语音识别已关闭'
                            ),
                            backgroundColor: Colors.green,
                            behavior: SnackBarBehavior.floating,
                            margin: const EdgeInsets.all(16),
                          ),
                        );
                        
                        // 重新初始化或重置状态
                        if (value && !_initializing) {
                            _initAsr();
                          } else if (!value) {
                            setState(() {
                              _statusMessage = '语音识别功能已关闭，请在设置中开启';
                              _recording = false;
                            });
                            // 确保_asr不为null再调用dispose
                            _asr.dispose();
                          }
                        }
                      }
                    },
                  ),
                ),
                const ListTile(
                  title: Text('隐私说明'),
                  subtitle: Text('语音识别在设备本地进行，不会上传您的语音数据'),
                ),
              ],
            );
          },
        );
      },
    );
  }
  
  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // AppLocalizations not used in this build method
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final primaryColor = ref.watch(primaryColorProvider);
    
    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      appBar: AppBar(
        title: const Text('语音记账'),
        backgroundColor: theme.scaffoldBackgroundColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: _showPrivacySettings,
            tooltip: '语音识别设置',
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16.0.scaled(context, ref)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 状态消息
              Text(
                _statusMessage,
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 24),
              
              // 录音按钮和波形显示
              Center(
                child: Column(
                  children: [
                    // 状态指示器
                    Container(
                      margin: const EdgeInsets.only(bottom: 24),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: _getStateColor(),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _getStatusText(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    
                    // 波形动画或加载指示器
                    SizedBox(
                      height: 120,
                      width: double.infinity,
                      child: _isProcessing ? _buildLoadingIndicator() : _buildWaveformAnimation(),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // 录音按钮
                    GestureDetector(
                      onTap: _initializing || !_asr.isReady || _isProcessing ? null : _toggleRecord,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: _recording ? Colors.red : primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _recording ? Colors.red.withValues(alpha: 0.4) : primary.withValues(alpha: 0.4),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: Icon(
                          _recording ? Icons.stop : Icons.mic,
                          size: 60,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    Text(
                      _recording ? '点击停止录音' : '点击开始录音',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 32),
              
              // 识别文本显示
              if (_partialText.isNotEmpty || _finalText.isNotEmpty) ...[
                Card(
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '识别文本',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 4,
                          controller: TextEditingController(text: _finalText.isNotEmpty ? _finalText : _partialText),
                          onChanged: (v) {
                            _finalText = v;
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // 解析按钮
                if (_parsedResult == null && _finalText.isNotEmpty)
                  FilledButton(
                    onPressed: _isProcessing ? null : _parseAndProceed,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    child: const Text('解析账单信息'),
                  ),
              ],
              
              // 解析结果显示
              if (_parsedResult != null) ...[
                const SizedBox(height: 24),
                Card(
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '账单信息',
                          style: theme.textTheme.titleMedium,
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // 金额选择
                        Text(
                          '金额',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        
                        if (_parsedResult!.allNumbers.isNotEmpty) ...[
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _parsedResult!.allNumbers.map((number) {
                              final isSelected = _selectedAmount == number;
                              return ChoiceChip(
                                label: Text('¥$number'),
                                selected: isSelected,
                                showCheckmark: isSelected,
                                selectedColor: primaryColor,
                                backgroundColor: theme.colorScheme.surface,
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
                            '未检测到金额',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.orange,
                            ),
                          ),
                        ],
                        
                        // 手动输入金额
                        const SizedBox(height: 16),
                        TextField(
                          decoration: InputDecoration(
                            labelText: '手动输入金额',
                            prefixText: '¥',
                            border: const OutlineInputBorder(),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (value) {
                            setState(() {
                              _selectedAmount = value;
                            });
                          },
                        ),
                        
                        // 商家名称
                        if (_parsedResult!.merchant != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            '商家',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _parsedResult!.merchant!,
                            style: theme.textTheme.bodyLarge,
                          ),
                        ],
                        
                        // 推荐分类
                        if (_parsedResult!.suggestedCategoryId != null) ...[
                          const SizedBox(height: 16),
                          FutureBuilder<Category?>(
                            future: ref.read(repositoryProvider).getCategoryById(_parsedResult!.suggestedCategoryId!),
                            builder: (context, snapshot) {
                              if (snapshot.hasData && snapshot.data != null) {
                                final category = snapshot.data!;
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '推荐分类',
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: primaryColor,
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
                        if (_parsedResult!.time != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            '时间',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_parsedResult!.time!.year}-${_parsedResult!.time!.month.toString().padLeft(2, '0')}-${_parsedResult!.time!.day.toString().padLeft(2, '0')} ${_parsedResult!.time!.hour.toString().padLeft(2, '0')}:${_parsedResult!.time!.minute.toString().padLeft(2, '0')}',
                            style: theme.textTheme.bodyLarge,
                          ),
                        ],
                        
                        const SizedBox(height: 24),
                        
                        // 创建账单按钮
                        FilledButton(
                          onPressed: _selectedAmount?.isNotEmpty == true && !_isProcessing ? _createTransaction : null,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                          ),
                          child: const Text('创建账单'),
                        ),
                      ],
                    ),
                  ),
                ),
                
                // 错误消息
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: Colors.red.shade50,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _errorMessage!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.red,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
              
              // 提示信息
              const SizedBox(height: 24),
              Card(
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '使用提示',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '1. 请在安静环境下使用\n'
                        '2. 清晰说出账单信息，如"今天买咖啡花了30元"\n'
                        '3. 包含金额、商家等关键信息可提高识别准确率',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  // 构建波形动画
  Widget _buildWaveformAnimation() {
    final bars = List.generate(30, (index) => index);
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: bars.map((index) {
        final baseHeight = 20.0;
        final maxHeight = 80.0;
        // 创建有规律的波形
        final height = _recording
            ? baseHeight + (sin(index * 0.5 + DateTime.now().millisecond / 200) * _currentVolume * (maxHeight - baseHeight))
            : baseHeight + (sin(index * 0.5) * _currentVolume * (maxHeight - baseHeight));
        
        return Container(
          width: 4,
          height: height,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: _recording ? Colors.red : Theme.of(context).primaryColor,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }).toList(),
    );
  }

  /// 增强语音识别文本，使其更适合解析
  String _enhanceVoiceText(String text) {
    // 替换口语化表达为标准格式
    var enhancedText = text;
    
    // 将"点"转换为小数点
    enhancedText = enhancedText.replaceAllMapped(
      RegExp(r'(\d+)\s*点\s*(\d+)'),
      (match) => '${match.group(1)}.${match.group(2)}',
    );
    
    // 添加货币符号标识
    if (!enhancedText.contains(RegExp(r'[¥￥]'))) {
      enhancedText = enhancedText.replaceAllMapped(
        RegExp(r'花了\s*(\d+(\.\d+)?)\s*元'),
        (match) => '花了 ¥${match.group(1)} 元',
      );
    }
    
    // 规范化时间表达
    final now = DateTime.now();
    enhancedText = enhancedText
      .replaceAll('今天', '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}')
      .replaceAll('昨天', '${now.subtract(const Duration(days: 1)).year}-${now.subtract(const Duration(days: 1)).month.toString().padLeft(2, '0')}-${now.subtract(const Duration(days: 1)).day.toString().padLeft(2, '0')}');
    
    return enhancedText;
  }

  /// 专门针对语音识别结果的解析增强
  OcrResult _parseVoiceRecognitionResult(String text, OcrResult baseResult) {
    // 提取金额
    double? amount = baseResult.amount;
    amount ??= _extractAmountFromVoiceText(text);
    
    // 提取商家
    String? merchant = baseResult.merchant;
    merchant ??= _extractMerchantFromVoiceText(text);
    
    // 提取时间
    DateTime? time = baseResult.time;
    time ??= _extractTimeFromVoiceText(text);
    
    // 合并所有数字
    final allNumbers = _extractAllNumbersFromVoice(text);
    
    return OcrResult(
      amount: amount,
      merchant: merchant,
      time: time,
      rawText: text,
      allNumbers: allNumbers.isNotEmpty ? allNumbers : baseResult.allNumbers,
    );
  }

  /// 从语音文本中提取金额
  double? _extractAmountFromVoiceText(String text) {
    // 匹配常见语音表达：花了xx元，xx元，xx块，xx块钱
    final patterns = [
      RegExp(r'花了\s*(\d+(\.\d+)?)\s*[元块]'),
      RegExp(r'(\d+(\.\d+)?)\s*[元块][钱]?'),
      RegExp(r'[是花]\s*[¥￥]?\s*(\d+(\.\d+)?)'),
    ];
    
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null && match.groupCount > 0) {
        final amountStr = match.group(1);
        if (amountStr != null) {
          final amount = double.tryParse(amountStr);
          if (amount != null && amount > 0) {
            return amount;
          }
        }
      }
    }
    
    return null;
  }

  /// 从语音文本中提取商家
  String? _extractMerchantFromVoiceText(String text) {
    // 匹配常见语音表达：在xx买，xx店，xx超市
    final patterns = [
      RegExp(r'在\s*([^买花了\d]+)\s*[买花]'),
      RegExp(r'([^\s\d]+[店超市餐厅])'),
      RegExp(r'([^\s\d]+)\s*的'),
    ];
    
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null && match.groupCount > 0) {
        var merchant = match.group(1)?.trim();
        if (merchant != null && merchant.length >= 2) {
          return merchant;
        }
      }
    }
    
    return null;
  }

  /// 从语音文本中提取时间
  DateTime? _extractTimeFromVoiceText(String text) {
    final now = DateTime.now();
    
    // 今天、昨天、前天
    if (text.contains('今天')) {
      return now;
    } else if (text.contains('昨天')) {
      return now.subtract(const Duration(days: 1));
    } else if (text.contains('前天')) {
      return now.subtract(const Duration(days: 2));
    }
    
    // 星期几
    final weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    for (int i = 0; i < weekdays.length; i++) {
      if (text.contains(weekdays[i])) {
        final daysDiff = (i + 1) - now.weekday;
        return now.add(Duration(days: daysDiff > 0 ? daysDiff - 7 : daysDiff));
      }
    }
    
    // 本月某天
    final dayPattern = RegExp(r'(\d+)号');
    final dayMatch = dayPattern.firstMatch(text);
    if (dayMatch != null) {
      final day = int.tryParse(dayMatch.group(1)!);
      if (day != null && day > 0 && day <= 31) {
        try {
          return DateTime(now.year, now.month, day);
        } catch (_) {
          // 无效日期，忽略
        }
      }
    }
    
    return null;
  }

  /// 从语音文本中提取所有可能的数字
  List<String> _extractAllNumbersFromVoice(String text) {
    final numbers = <String>[];
    
    // 匹配常见语音数字表达
    final patterns = [
      RegExp(r'[花了是]\s*[¥￥]?\s*(\d+(\.\d+)?)'),
      RegExp(r'(\d+(\.\d+)?)\s*[元块][钱]?'),
      RegExp(r'[¥￥]\s*(\d+(\.\d+)?)'),
    ];
    
    for (final pattern in patterns) {
      final matches = pattern.allMatches(text);
      for (final match in matches) {
        if (match.groupCount > 0) {
          final numStr = match.group(1);
          if (numStr != null && numStr.isNotEmpty) {
            final num = double.tryParse(numStr);
            if (num != null && num > 0 && num < 1000000) {
              numbers.add(numStr);
            }
          }
        }
      }
    }
    
    // 去重并排序
    final uniqueNumbers = numbers.toSet().toList();
    uniqueNumbers.sort((a, b) {
      final numA = double.parse(a);
      final numB = double.parse(b);
      return numB.compareTo(numA); // 从大到小排序
    });
    
    return uniqueNumbers;
  }

  // 获取当前状态的颜色
  Color _getStateColor() {
    if (_recording) return Colors.red;
    if (_isProcessing) return Colors.blue;
    if (_errorMessage != null) return Colors.orange;
    if (_initializing) return Colors.grey;
    return Theme.of(context).primaryColor;
  }
  
  // 获取当前状态的文本
  String _getStatusText() {
    if (_recording) return '录音中';
    if (_isProcessing) return '处理中';
    if (_errorMessage != null) return '错误';
    if (_initializing) return '初始化';
    return '就绪';
  }

  // 构建加载指示器
  Widget _buildLoadingIndicator() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: 40,
            width: 40,
            child: CircularProgressIndicator(
              color: Theme.of(context).primaryColor,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '正在解析语音...',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _volumeTimer?.cancel();
    _asr.dispose();
    super.dispose();
  }
}