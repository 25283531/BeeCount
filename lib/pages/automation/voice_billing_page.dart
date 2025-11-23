import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../widgets/ui/ui.dart';
import '../../styles/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../services/automation/asr_service.dart';
import '../../services/automation/ocr_service.dart';
import '../../services/automation/ai_bill_service.dart';
import '../../pages/transaction/transaction_editor_page.dart';

class VoiceBillingPage extends ConsumerStatefulWidget {
  const VoiceBillingPage({super.key});

  @override
  ConsumerState<VoiceBillingPage> createState() => _VoiceBillingPageState();
}

class _VoiceBillingPageState extends ConsumerState<VoiceBillingPage> {
  final AsrService _asr = AsrService();
  bool _initializing = true;
  bool _recording = false;
  String _partialText = '';
  String _finalText = '';
  Stream<dynamic>? _partialStream;
  Stream<dynamic>? _resultStream;

  @override
  void initState() {
    super.initState();
    _initAsr();
  }

  Future<void> _initAsr() async {
    try {
      await _asr.initialize(modelName: 'vosk-model-small-cn-0.22');
      setState(() => _initializing = false);
      if (Platform.isAndroid) {
        _partialStream = _asr.onPartial();
        _resultStream = _asr.onResult();
      }
    } catch (e) {
      setState(() => _initializing = false);
    }
  }

  Future<void> _toggleRecord() async {
    if (_recording) {
      await _asr.stop();
      setState(() => _recording = false);
    } else {
      setState(() {
        _partialText = '';
        _finalText = '';
      });
      await _asr.start();
      setState(() => _recording = true);
    }
  }

  Future<void> _parseAndProceed() async {
    final text = _finalText.isNotEmpty ? _finalText : _partialText;
    if (text.trim().isEmpty) return;
    final ocr = OcrService();
    final base = ocr.parsePaymentText(text);
    final ai = AIBillService();
    await ai.initialize();
    final info = await ai.extractBillInfo(base.rawText);
    final mergedAmount = info?.amount ?? base.amount;
    final mergedTime = info?.time ?? base.time;
    final mergedNote = info?.merchant ?? base.merchant ?? text;
    final kind = info?.type?.toString().split('.').last ?? 'expense';
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TransactionEditorPage(
        initialKind: kind,
        quickAdd: true,
        initialAmount: mergedAmount,
        initialDate: mergedTime ?? DateTime.now(),
        initialNote: mergedNote,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.smartBillingPageTitle,
            subtitle: '语音记账',
            showBack: true,
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.all(16.0.scaled(context, ref)),
              children: [
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.mic, color: primary),
                          const SizedBox(width: 8),
                          Text('语音识别'),
                          const Spacer(),
                          FilledButton(
                            onPressed: _initializing || !_asr.isReady ? null : _toggleRecord,
                            child: Text(_recording ? '停止' : '开始'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_initializing)
                        const Center(child: CircularProgressIndicator())
                      else ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: BeeTokens.surfaceCard(context),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextField(
                                decoration: const InputDecoration(
                                  labelText: '识别文本',
                                  border: OutlineInputBorder(),
                                ),
                                maxLines: 4,
                                controller: TextEditingController(text: _finalText.isNotEmpty ? _finalText : _partialText),
                                onChanged: (v) {
                                  _finalText = v;
                                  setState(() {});
                                },
                              ),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: (_finalText.isEmpty && _partialText.isEmpty) ? null : _parseAndProceed,
                                child: const Text('解析并记账'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (Platform.isAndroid && _resultStream != null)
                          StreamBuilder(
                            stream: _resultStream,
                            builder: (context, snapshot) {
                              if (snapshot.hasData) {
                                final data = snapshot.data.toString();
                                try {
                                  final obj = jsonDecode(data);
                                  final text = obj is Map && obj['text'] is String ? obj['text'] as String : '';
                                  if (text.isNotEmpty) {
                                    _finalText = text;
                                  }
                                } catch (_) {}
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        if (Platform.isAndroid && _partialStream != null)
                          StreamBuilder(
                            stream: _partialStream,
                            builder: (context, snapshot) {
                              if (snapshot.hasData) {
                                final data = snapshot.data.toString();
                                try {
                                  final obj = jsonDecode(data);
                                  final text = obj is Map && obj['partial'] is String ? obj['partial'] as String : '';
                                  if (text.isNotEmpty) {
                                    _partialText = text;
                                  }
                                } catch (_) {}
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                      ],
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

  @override
  void dispose() {
    _asr.dispose();
    super.dispose();
  }
}