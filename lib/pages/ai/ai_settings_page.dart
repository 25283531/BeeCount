import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../widgets/ui/ui.dart';
import '../../widgets/biz/section_card.dart';
import '../../styles/tokens.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../providers/theme_providers.dart';
import '../../l10n/app_localizations.dart';

/// AI智能识别设置页面
class AISettingsPage extends ConsumerStatefulWidget {
  const AISettingsPage({super.key});

  @override
  ConsumerState<AISettingsPage> createState() => _AISettingsPageState();
}

class _AISettingsPageState extends ConsumerState<AISettingsPage> {
  String _strategy = 'local_first';
  String _glmApiKey = '';
  bool _aiEnabled = false; // AI增强开关
  bool _useVision = true; // 使用视觉模型开关（默认打开）
  bool _loading = true;

  late final TextEditingController _apiKeyController;

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController();
    _loadSettings();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('ai_glm_api_key') ?? '';

    setState(() {
      _strategy = prefs.getString('ai_strategy') ?? 'local_first';
      _glmApiKey = apiKey;
      _apiKeyController.text = apiKey;
      _aiEnabled = prefs.getBool('ai_bill_extraction_enabled') ?? false;
      _useVision = prefs.getBool('ai_use_vision') ?? true; // 默认打开
      _loading = false;
    });
  }

  Future<void> _openGlmWebsite() async {
    final uri = Uri.parse('https://open.bigmodel.cn/');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (_loading) {
      return Scaffold(
        backgroundColor: BeeTokens.scaffoldBackground(context),
        body: Column(
          children: [
            PrimaryHeader(
              title: l10n.aiSettingsTitle,
              showBack: true,
            ),
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.aiSettingsTitle,
            subtitle: l10n.aiSettingsSubtitle,
            showBack: true,
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(
                horizontal: 12.0.scaled(context, ref),
                vertical: 8.0.scaled(context, ref),
              ),
              children: [
                // AI增强开关
                _buildEnableSection(),

                SizedBox(height: 8.0.scaled(context, ref)),

                // 执行策略
                _buildStrategySection(),

                SizedBox(height: 8.0.scaled(context, ref)),

                // 云端API配置
                _buildCloudApiSection(),

                SizedBox(height: 8.0.scaled(context, ref)),

                // 本地模型管理
                _buildLocalModelSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnableSection() {
    final l10n = AppLocalizations.of(context);

    return SectionCard(
      child: Column(
        children: [
          SwitchListTile(
            value: _aiEnabled,
            onChanged: (value) async {
              setState(() => _aiEnabled = value);

              // 立即保存AI开关状态（用户体验更好）
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('ai_bill_extraction_enabled', value);

              if (mounted) {
                showToast(context,
                    value ? l10n.aiEnableToastOn : l10n.aiEnableToastOff);
              }
            },
            title: Text(
              l10n.aiEnableTitle,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(l10n.aiEnableSubtitle),
            activeThumbColor: ref.watch(primaryColorProvider),
          ),

          // 上传图片到AI开关
          BeeTokens.cardDivider(context),
          SwitchListTile(
            value: _useVision,
            onChanged: _aiEnabled
                ? (value) async {
                    setState(() => _useVision = value);

                    // 立即保存Vision开关状态
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('ai_use_vision', value);

                    if (mounted) {
                      showToast(
                        context,
                        value ? '已启用图片识别，识别准确率更高' : '已关闭图片识别，仅使用OCR文本',
                      );
                    }
                  }
                : null,
            title: const Text(
              '上传图片到AI',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              _useVision
                  ? '使用GLM-4V-Flash视觉模型，识别更准确（免费）'
                  : '仅使用GLM-4.6文本模型分析OCR结果',
            ),
            activeThumbColor: ref.watch(primaryColorProvider),
          ),
        ],
      ),
    );
  }

  Widget _buildStrategySection() {
    final l10n = AppLocalizations.of(context);

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 20,
                  color: ref.watch(primaryColorProvider),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.aiStrategyTitle,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _buildStrategyOption(
            'local_first',
            l10n.aiStrategyLocalFirst,
            l10n.aiStrategyLocalFirstDesc,
            Icons.phone_android,
            enabled: false, // 本地模型训练中
          ),
          _buildStrategyOption(
            'cloud_first',
            l10n.aiStrategyCloudFirst,
            l10n.aiStrategyCloudFirstDesc,
            Icons.cloud,
          ),
          _buildStrategyOption(
            'local_only',
            l10n.aiStrategyLocalOnly,
            l10n.aiStrategyLocalOnlyDesc,
            Icons.offline_bolt,
            enabled: false, // 本地模型训练中
          ),
          _buildStrategyOption(
            'cloud_only',
            l10n.aiStrategyCloudOnly,
            l10n.aiStrategyCloudOnlyDesc,
            Icons.cloud_done,
          ),
        ],
      ),
    );
  }

  Widget _buildStrategyOption(
    String value,
    String title,
    String subtitle,
    IconData icon, {
    bool enabled = true,
  }) {
    final l10n = AppLocalizations.of(context);
    final isSelected = _strategy == value;
    final displaySubtitle = enabled ? subtitle : l10n.aiStrategyUnavailable;

    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: InkWell(
        onTap: enabled
            ? () async {
                setState(() => _strategy = value);

                // 立即保存执行策略
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('ai_strategy', value);

                if (mounted) {
                  showToast(context, l10n.aiStrategySwitched(title));
                }
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                icon,
                size: 24,
                color: enabled && isSelected
                    ? ref.watch(primaryColorProvider)
                    : BeeTokens.textTertiary(context),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: enabled && isSelected
                            ? ref.watch(primaryColorProvider)
                            : BeeTokens.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      displaySubtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: enabled
                            ? BeeTokens.textSecondary(context)
                            : Colors.orange[700],
                        fontStyle:
                            enabled ? FontStyle.normal : FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              Radio<String>(
                value: value,
                groupValue: _strategy,
                onChanged: enabled
                    ? (v) async {
                        if (v == null) return;
                        setState(() => _strategy = v);

                        // 立即保存执行策略
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('ai_strategy', v);

                        if (mounted) {
                          showToast(context, l10n.aiStrategySwitched(title));
                        }
                      }
                    : null,
                activeColor: ref.watch(primaryColorProvider),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCloudApiSection() {
    final l10n = AppLocalizations.of(context);

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(
                  Icons.cloud_outlined,
                  size: 20,
                  color: ref.watch(primaryColorProvider),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.aiCloudApiTitle,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  decoration: InputDecoration(
                    labelText: l10n.aiCloudApiKeyLabel,
                    hintText: l10n.aiCloudApiKeyHint,
                    border: const OutlineInputBorder(),
                    helperText: l10n.aiCloudApiKeyHelper,
                    prefixIcon: const Icon(Icons.vpn_key),
                    suffixIcon: _glmApiKey.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.check_circle,
                                color: Colors.green),
                            onPressed: () async {
                              // 手动保存
                              final prefs =
                                  await SharedPreferences.getInstance();
                              await prefs.setString(
                                  'ai_glm_api_key', _glmApiKey);
                              if (mounted) {
                                showToast(context, l10n.aiCloudApiKeySaved);
                              }
                            },
                            tooltip: l10n.aiCloudApiKeySaved,
                          )
                        : null,
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: ref.watch(primaryColorProvider),
                        width: 2,
                      ),
                    ),
                  ),
                  controller: _apiKeyController,
                  onChanged: (v) {
                    setState(() => _glmApiKey = v);
                  },
                  onSubmitted: (v) async {
                    // 按回车键自动保存
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('ai_glm_api_key', v);
                    if (mounted) {
                      showToast(context, l10n.aiCloudApiKeySaved);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: _openGlmWebsite,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(l10n.aiCloudApiGetKey),
                  style: TextButton.styleFrom(
                    foregroundColor: ref.watch(primaryColorProvider),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalModelSection() {
    final l10n = AppLocalizations.of(context);

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(
                  Icons.storage,
                  size: 20,
                  color: BeeTokens.textTertiary(context),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.aiLocalModelTitle,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange[100],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    l10n.aiLocalModelTraining,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.orange[800],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Opacity(
            opacity: 0.5,
            child: ListTile(
              leading: Icon(Icons.download_outlined,
                  color: BeeTokens.textTertiary(context)),
              title: Text(l10n.aiLocalModelManagement),
              subtitle: Text(l10n.aiLocalModelUnavailable),
              trailing: const Icon(Icons.chevron_right),
              enabled: false,
              onTap: null,
            ),
          ),
        ],
      ),
    );
  }
}
