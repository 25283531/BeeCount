import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yaml/yaml.dart';
import 'package:flutter_cloud_sync/flutter_cloud_sync.dart';
import 'package:drift/drift.dart' as d;
import '../data/db.dart';
import '../providers.dart';
import 'logger_service.dart';

/// 应用配置模型
class AppConfig {
  final SupabaseConfig? supabase;
  final WebdavConfig? webdav;
  final AIConfig? ai;
  final AppSettingsConfig? appSettings;
  final RecurringTransactionsConfig? recurringTransactions;

  const AppConfig({
    this.supabase,
    this.webdav,
    this.ai,
    this.appSettings,
    this.recurringTransactions,
  });

  Map<String, dynamic> toYaml() {
    final map = <String, dynamic>{};

    if (supabase != null) {
      map['supabase'] = supabase!.toMap();
    }

    if (webdav != null) {
      map['webdav'] = webdav!.toMap();
    }

    if (ai != null) {
      map['ai'] = ai!.toMap();
    }

    if (appSettings != null) {
      map['app_settings'] = appSettings!.toMap();
    }

    if (recurringTransactions != null) {
      map['recurring_transactions'] = recurringTransactions!.toMap();
    }

    return map;
  }

  static AppConfig fromYaml(Map<dynamic, dynamic> yaml) {
    return AppConfig(
      supabase: yaml.containsKey('supabase')
          ? SupabaseConfig.fromMap(
              Map<String, dynamic>.from(yaml['supabase'] as Map))
          : null,
      webdav: yaml.containsKey('webdav')
          ? WebdavConfig.fromMap(
              Map<String, dynamic>.from(yaml['webdav'] as Map))
          : null,
      ai: yaml.containsKey('ai')
          ? AIConfig.fromMap(Map<String, dynamic>.from(yaml['ai'] as Map))
          : null,
      appSettings: yaml.containsKey('app_settings')
          ? AppSettingsConfig.fromMap(
              Map<String, dynamic>.from(yaml['app_settings'] as Map))
          : null,
      recurringTransactions: yaml.containsKey('recurring_transactions')
          ? RecurringTransactionsConfig.fromMap(
              Map<String, dynamic>.from(yaml['recurring_transactions'] as Map))
          : null,
    );
  }
}

/// Supabase配置
class SupabaseConfig {
  final String url;
  final String anonKey;

  const SupabaseConfig({
    required this.url,
    required this.anonKey,
  });

  Map<String, dynamic> toMap() => {
        'url': url,
        'anon_key': anonKey,
      };

  static SupabaseConfig fromMap(Map<String, dynamic> map) => SupabaseConfig(
        url: map['url'] as String,
        anonKey: map['anon_key'] as String,
      );
}

/// WebDAV配置
class WebdavConfig {
  final String url;
  final String username;
  final String password;
  final String? remotePath;

  const WebdavConfig({
    required this.url,
    required this.username,
    required this.password,
    this.remotePath,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'url': url,
      'username': username,
      'password': password,
    };
    if (remotePath != null && remotePath!.isNotEmpty) {
      map['remote_path'] = remotePath;
    }
    return map;
  }

  static WebdavConfig fromMap(Map<String, dynamic> map) => WebdavConfig(
        url: map['url'] as String,
        username: map['username'] as String,
        password: map['password'] as String,
        remotePath: map['remote_path'] as String?,
      );
}

/// AI配置
class AIConfig {
  final String? glmApiKey;
  final String? strategy;
  final bool? enabled;
  final bool? useVision;

  const AIConfig({
    this.glmApiKey,
    this.strategy,
    this.enabled,
    this.useVision,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{};
    if (glmApiKey != null && glmApiKey!.isNotEmpty) {
      map['glm_api_key'] = glmApiKey;
    }
    if (strategy != null && strategy!.isNotEmpty) {
      map['strategy'] = strategy;
    }
    if (enabled != null) {
      map['enabled'] = enabled;
    }
    if (useVision != null) {
      map['use_vision'] = useVision;
    }
    return map;
  }

  static AIConfig fromMap(Map<String, dynamic> map) => AIConfig(
        glmApiKey: map['glm_api_key'] as String?,
        strategy: map['strategy'] as String?,
        enabled: map['enabled'] as bool?,
        useVision: map['use_vision'] as bool?,
      );
}

/// 应用设置配置
class AppSettingsConfig {
  // 账户管理
  final bool? accountFeatureEnabled;
  final int? defaultIncomeAccountId;
  final int? defaultExpenseAccountId;

  // 记账提醒
  final bool? reminderEnabled;
  final int? reminderHour;
  final int? reminderMinute;

  // 语言设置
  final String? languageCode;
  final String? countryCode;

  // 个性化设置
  final int? primaryColor;
  final int? fontScaleLevel;
  final double? customFontScale;

  // 外观设置
  final String? themeMode;
  final String? darkModePatternStyle;
  final bool? compactAmount;
  final bool? showTransactionTime;

  // 云服务选择
  final String? cloudServiceType;

  // 自动记账功能
  final bool? autoScreenshotEnabled;
  final bool? shortcutPreferCamera;

  const AppSettingsConfig({
    this.accountFeatureEnabled,
    this.defaultIncomeAccountId,
    this.defaultExpenseAccountId,
    this.reminderEnabled,
    this.reminderHour,
    this.reminderMinute,
    this.languageCode,
    this.countryCode,
    this.primaryColor,
    this.fontScaleLevel,
    this.customFontScale,
    this.themeMode,
    this.darkModePatternStyle,
    this.compactAmount,
    this.showTransactionTime,
    this.cloudServiceType,
    this.autoScreenshotEnabled,
    this.shortcutPreferCamera,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{};

    if (accountFeatureEnabled != null) {
      map['account_feature_enabled'] = accountFeatureEnabled;
    }
    if (defaultIncomeAccountId != null) {
      map['default_income_account_id'] = defaultIncomeAccountId;
    }
    if (defaultExpenseAccountId != null) {
      map['default_expense_account_id'] = defaultExpenseAccountId;
    }
    if (reminderEnabled != null) {
      map['reminder_enabled'] = reminderEnabled;
    }
    if (reminderHour != null) {
      map['reminder_hour'] = reminderHour;
    }
    if (reminderMinute != null) {
      map['reminder_minute'] = reminderMinute;
    }
    if (languageCode != null && languageCode!.isNotEmpty) {
      map['language_code'] = languageCode;
    }
    if (countryCode != null && countryCode!.isNotEmpty) {
      map['country_code'] = countryCode;
    }
    if (primaryColor != null) {
      map['primary_color'] = primaryColor;
    }
    if (fontScaleLevel != null) {
      map['font_scale_level'] = fontScaleLevel;
    }
    if (customFontScale != null) {
      map['custom_font_scale'] = customFontScale;
    }
    if (themeMode != null && themeMode!.isNotEmpty) {
      map['theme_mode'] = themeMode;
    }
    if (darkModePatternStyle != null && darkModePatternStyle!.isNotEmpty) {
      map['dark_mode_pattern_style'] = darkModePatternStyle;
    }
    if (compactAmount != null) {
      map['compact_amount'] = compactAmount;
    }
    if (showTransactionTime != null) {
      map['show_transaction_time'] = showTransactionTime;
    }
    if (cloudServiceType != null && cloudServiceType!.isNotEmpty) {
      map['cloud_service_type'] = cloudServiceType;
    }
    if (autoScreenshotEnabled != null) {
      map['auto_screenshot_enabled'] = autoScreenshotEnabled;
    }
    if (shortcutPreferCamera != null) {
      map['shortcut_prefer_camera'] = shortcutPreferCamera;
    }

    return map;
  }

  static AppSettingsConfig fromMap(Map<String, dynamic> map) =>
      AppSettingsConfig(
        accountFeatureEnabled: map['account_feature_enabled'] as bool?,
        defaultIncomeAccountId: map['default_income_account_id'] as int?,
        defaultExpenseAccountId: map['default_expense_account_id'] as int?,
        reminderEnabled: map['reminder_enabled'] as bool?,
        reminderHour: map['reminder_hour'] as int?,
        reminderMinute: map['reminder_minute'] as int?,
        languageCode: map['language_code'] as String?,
        countryCode: map['country_code'] as String?,
        primaryColor: map['primary_color'] as int?,
        fontScaleLevel: map['font_scale_level'] as int?,
        customFontScale: map['custom_font_scale'] != null
            ? (map['custom_font_scale'] as num).toDouble()
            : null,
        themeMode: map['theme_mode'] as String?,
        darkModePatternStyle: map['dark_mode_pattern_style'] as String?,
        compactAmount: map['compact_amount'] as bool?,
        showTransactionTime: map['show_transaction_time'] as bool?,
        cloudServiceType: map['cloud_service_type'] as String?,
        autoScreenshotEnabled: map['auto_screenshot_enabled'] as bool?,
        shortcutPreferCamera: map['shortcut_prefer_camera'] as bool?,
      );
}

/// 周期账单配置
class RecurringTransactionsConfig {
  final List<RecurringTransactionItem> items;

  const RecurringTransactionsConfig({required this.items});

  Map<String, dynamic> toMap() {
    return {
      'items': items.map((item) => item.toMap()).toList(),
    };
  }

  static RecurringTransactionsConfig fromMap(Map<String, dynamic> map) {
    final itemsList = map['items'] as List<dynamic>? ?? [];
    return RecurringTransactionsConfig(
      items: itemsList
          .map((item) =>
              RecurringTransactionItem.fromMap(Map<String, dynamic>.from(item as Map)))
          .toList(),
    );
  }
}

/// 周期账单项
class RecurringTransactionItem {
  final String type; // expense / income / transfer
  final double amount;
  final int? categoryId;
  final int? accountId;
  final int? toAccountId;
  final String? note;
  final String frequency; // daily / weekly / monthly / yearly
  final int interval;
  final int? dayOfMonth;
  final int? dayOfWeek;
  final int? monthOfYear;
  final String startDate; // ISO 8601 format
  final String? endDate;
  final bool enabled;

  const RecurringTransactionItem({
    required this.type,
    required this.amount,
    this.categoryId,
    this.accountId,
    this.toAccountId,
    this.note,
    required this.frequency,
    required this.interval,
    this.dayOfMonth,
    this.dayOfWeek,
    this.monthOfYear,
    required this.startDate,
    this.endDate,
    required this.enabled,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'type': type,
      'amount': amount,
      'frequency': frequency,
      'interval': interval,
      'start_date': startDate,
      'enabled': enabled,
    };
    if (categoryId != null) map['category_id'] = categoryId;
    if (accountId != null) map['account_id'] = accountId;
    if (toAccountId != null) map['to_account_id'] = toAccountId;
    if (note != null && note!.isNotEmpty) map['note'] = note;
    if (dayOfMonth != null) map['day_of_month'] = dayOfMonth;
    if (dayOfWeek != null) map['day_of_week'] = dayOfWeek;
    if (monthOfYear != null) map['month_of_year'] = monthOfYear;
    if (endDate != null) map['end_date'] = endDate;
    return map;
  }

  static RecurringTransactionItem fromMap(Map<String, dynamic> map) {
    return RecurringTransactionItem(
      type: map['type'] as String,
      amount: (map['amount'] as num).toDouble(),
      categoryId: map['category_id'] as int?,
      accountId: map['account_id'] as int?,
      toAccountId: map['to_account_id'] as int?,
      note: map['note'] as String?,
      frequency: map['frequency'] as String,
      interval: map['interval'] as int,
      dayOfMonth: map['day_of_month'] as int?,
      dayOfWeek: map['day_of_week'] as int?,
      monthOfYear: map['month_of_year'] as int?,
      startDate: map['start_date'] as String,
      endDate: map['end_date'] as String?,
      enabled: map['enabled'] as bool,
    );
  }

  factory RecurringTransactionItem.fromDb(RecurringTransaction rt) {
    return RecurringTransactionItem(
      type: rt.type,
      amount: rt.amount,
      categoryId: rt.categoryId,
      accountId: rt.accountId,
      toAccountId: rt.toAccountId,
      note: rt.note,
      frequency: rt.frequency,
      interval: rt.interval,
      dayOfMonth: rt.dayOfMonth,
      dayOfWeek: rt.dayOfWeek,
      monthOfYear: rt.monthOfYear,
      startDate: rt.startDate.toIso8601String(),
      endDate: rt.endDate?.toIso8601String(),
      enabled: rt.enabled,
    );
  }
}

/// 配置导入导出服务
class ConfigExportService {
  /// 导出配置到YAML字符串
  /// [db] 数据库实例，用于导出周期账单等数据
  /// [ledgerId] 账本ID，用于过滤导出的周期账单
  static Future<String> exportToYaml({BeeDatabase? db, int? ledgerId}) async {
    final prefs = await SharedPreferences.getInstance();

    // 读取Supabase配置
    SupabaseConfig? supabaseConfig;
    final supabaseCfgRaw = prefs.getString('cloud_supabase_cfg');
    if (supabaseCfgRaw != null) {
      try {
        final cfg = decodeCloudConfig(supabaseCfgRaw);
        if (cfg.supabaseUrl != null && cfg.supabaseAnonKey != null) {
          supabaseConfig = SupabaseConfig(
            url: cfg.supabaseUrl!,
            anonKey: cfg.supabaseAnonKey!,
          );
        }
      } catch (e) {
        logger.warning('ConfigExport', '读取Supabase配置失败: $e');
      }
    }

    // 读取WebDAV配置
    WebdavConfig? webdavConfig;
    final webdavCfgRaw = prefs.getString('cloud_webdav_cfg');
    if (webdavCfgRaw != null) {
      try {
        final cfg = decodeCloudConfig(webdavCfgRaw);
        if (cfg.webdavUrl != null &&
            cfg.webdavUsername != null &&
            cfg.webdavPassword != null) {
          webdavConfig = WebdavConfig(
            url: cfg.webdavUrl!,
            username: cfg.webdavUsername!,
            password: cfg.webdavPassword!,
            remotePath: cfg.webdavRemotePath,
          );
        }
      } catch (e) {
        logger.warning('ConfigExport', '读取WebDAV配置失败: $e');
      }
    }

    // 读取AI配置
    AIConfig? aiConfig;
    final glmApiKey = prefs.getString('ai_glm_api_key');
    final aiStrategy = prefs.getString('ai_strategy');
    final aiEnabled = prefs.getBool('ai_bill_extraction_enabled');
    final aiUseVision = prefs.getBool('ai_use_vision');

    if (glmApiKey != null || aiStrategy != null || aiEnabled != null || aiUseVision != null) {
      aiConfig = AIConfig(
        glmApiKey: glmApiKey,
        strategy: aiStrategy,
        enabled: aiEnabled,
        useVision: aiUseVision,
      );
    }

    // 读取应用设置
    AppSettingsConfig? appSettings;
    final accountFeatureEnabled = prefs.getBool('account_feature_enabled');
    final defaultIncomeAccountId = prefs.getInt('default_income_account_id');
    final defaultExpenseAccountId = prefs.getInt('default_expense_account_id');
    final reminderEnabled = prefs.getBool('reminder_enabled');
    final reminderHour = prefs.getInt('reminder_hour');
    final reminderMinute = prefs.getInt('reminder_minute');
    final languageCode = prefs.getString('selected_language');
    final countryCode = prefs.getString('selected_language_country');
    final primaryColor = prefs.getInt('primaryColor');
    final fontScaleLevel = prefs.getInt('fontScaleLevel');
    final customFontScale = prefs.getDouble('customFontScale');
    final themeMode = prefs.getString('themeMode');
    final darkModePatternStyle = prefs.getString('darkModePatternStyle');
    final compactAmount = prefs.getBool('compactAmount');
    final showTransactionTime = prefs.getBool('showTransactionTime');
    final cloudServiceType = prefs.getString('selected_cloud_service');
    final autoScreenshotEnabled = prefs.getBool('auto_screenshot_billing_enabled');
    final shortcutPreferCamera = prefs.getBool('shortcut_prefer_camera');

    // 如果有任何应用设置，就创建配置对象
    if (accountFeatureEnabled != null ||
        defaultIncomeAccountId != null ||
        defaultExpenseAccountId != null ||
        reminderEnabled != null ||
        reminderHour != null ||
        reminderMinute != null ||
        languageCode != null ||
        countryCode != null ||
        primaryColor != null ||
        fontScaleLevel != null ||
        customFontScale != null ||
        themeMode != null ||
        darkModePatternStyle != null ||
        compactAmount != null ||
        showTransactionTime != null ||
        cloudServiceType != null ||
        autoScreenshotEnabled != null ||
        shortcutPreferCamera != null) {
      appSettings = AppSettingsConfig(
        accountFeatureEnabled: accountFeatureEnabled,
        defaultIncomeAccountId: defaultIncomeAccountId,
        defaultExpenseAccountId: defaultExpenseAccountId,
        reminderEnabled: reminderEnabled,
        reminderHour: reminderHour,
        reminderMinute: reminderMinute,
        languageCode: languageCode,
        countryCode: countryCode,
        primaryColor: primaryColor,
        fontScaleLevel: fontScaleLevel,
        customFontScale: customFontScale,
        themeMode: themeMode,
        darkModePatternStyle: darkModePatternStyle,
        compactAmount: compactAmount,
        showTransactionTime: showTransactionTime,
        cloudServiceType: cloudServiceType,
        autoScreenshotEnabled: autoScreenshotEnabled,
        shortcutPreferCamera: shortcutPreferCamera,
      );
    }

    // 读取周期账单配置
    RecurringTransactionsConfig? recurringConfig;
    if (db != null && ledgerId != null) {
      try {
        final recurringList = await (db.select(db.recurringTransactions)
              ..where((t) => t.ledgerId.equals(ledgerId)))
            .get();

        if (recurringList.isNotEmpty) {
          recurringConfig = RecurringTransactionsConfig(
            items: recurringList
                .map((rt) => RecurringTransactionItem.fromDb(rt))
                .toList(),
          );
        }
      } catch (e) {
        logger.warning('ConfigExport', '读取周期账单配置失败: $e');
      }
    }

    final config = AppConfig(
      supabase: supabaseConfig,
      webdav: webdavConfig,
      ai: aiConfig,
      appSettings: appSettings,
      recurringTransactions: recurringConfig,
    );

    // 转换为YAML格式
    final yamlMap = config.toYaml();

    // 手动构建YAML字符串以保持良好格式
    final buffer = StringBuffer();
    buffer.writeln('# BeeCount 应用配置');
    buffer.writeln('# 导出时间: ${DateTime.now().toIso8601String()}');
    buffer.writeln();

    if (yamlMap.containsKey('supabase')) {
      buffer.writeln('supabase:');
      final sb = yamlMap['supabase'] as Map<String, dynamic>;
      buffer.writeln('  url: "${sb['url']}"');
      buffer.writeln('  anon_key: "${sb['anon_key']}"');
      buffer.writeln();
    }

    if (yamlMap.containsKey('webdav')) {
      buffer.writeln('webdav:');
      final wd = yamlMap['webdav'] as Map<String, dynamic>;
      buffer.writeln('  url: "${wd['url']}"');
      buffer.writeln('  username: "${wd['username']}"');
      buffer.writeln('  password: "${wd['password']}"');
      if (wd.containsKey('remote_path')) {
        buffer.writeln('  remote_path: "${wd['remote_path']}"');
      }
      buffer.writeln();
    }

    if (yamlMap.containsKey('ai')) {
      buffer.writeln('ai:');
      final ai = yamlMap['ai'] as Map<String, dynamic>;
      if (ai.containsKey('glm_api_key')) {
        buffer.writeln('  glm_api_key: "${ai['glm_api_key']}"');
      }
      if (ai.containsKey('strategy')) {
        buffer.writeln('  strategy: "${ai['strategy']}"');
      }
      if (ai.containsKey('enabled')) {
        buffer.writeln('  enabled: ${ai['enabled']}');
      }
      if (ai.containsKey('use_vision')) {
        buffer.writeln('  use_vision: ${ai['use_vision']}');
      }
      buffer.writeln();
    }

    if (yamlMap.containsKey('app_settings')) {
      buffer.writeln('app_settings:');
      final settings = yamlMap['app_settings'] as Map<String, dynamic>;

      if (settings.containsKey('account_feature_enabled') ||
          settings.containsKey('default_income_account_id') ||
          settings.containsKey('default_expense_account_id')) {
        buffer.writeln('  # 账户管理');
        if (settings.containsKey('account_feature_enabled')) {
          buffer.writeln('  account_feature_enabled: ${settings['account_feature_enabled']}');
        }
        if (settings.containsKey('default_income_account_id')) {
          buffer.writeln('  default_income_account_id: ${settings['default_income_account_id']}');
        }
        if (settings.containsKey('default_expense_account_id')) {
          buffer.writeln('  default_expense_account_id: ${settings['default_expense_account_id']}');
        }
      }

      if (settings.containsKey('reminder_enabled') ||
          settings.containsKey('reminder_hour') ||
          settings.containsKey('reminder_minute')) {
        buffer.writeln('  # 记账提醒');
        if (settings.containsKey('reminder_enabled')) {
          buffer.writeln('  reminder_enabled: ${settings['reminder_enabled']}');
        }
        if (settings.containsKey('reminder_hour')) {
          buffer.writeln('  reminder_hour: ${settings['reminder_hour']}');
        }
        if (settings.containsKey('reminder_minute')) {
          buffer.writeln('  reminder_minute: ${settings['reminder_minute']}');
        }
      }

      if (settings.containsKey('language_code') || settings.containsKey('country_code')) {
        buffer.writeln('  # 语言设置');
        if (settings.containsKey('language_code')) {
          buffer.writeln('  language_code: "${settings['language_code']}"');
        }
        if (settings.containsKey('country_code')) {
          buffer.writeln('  country_code: "${settings['country_code']}"');
        }
      }

      if (settings.containsKey('primary_color') ||
          settings.containsKey('font_scale_level') ||
          settings.containsKey('custom_font_scale')) {
        buffer.writeln('  # 个性化设置');
        if (settings.containsKey('primary_color')) {
          buffer.writeln('  primary_color: ${settings['primary_color']}');
        }
        if (settings.containsKey('font_scale_level')) {
          buffer.writeln('  font_scale_level: ${settings['font_scale_level']}');
        }
        if (settings.containsKey('custom_font_scale')) {
          buffer.writeln('  custom_font_scale: ${settings['custom_font_scale']}');
        }
      }

      if (settings.containsKey('theme_mode') ||
          settings.containsKey('dark_mode_pattern_style') ||
          settings.containsKey('compact_amount') ||
          settings.containsKey('show_transaction_time')) {
        buffer.writeln('  # 外观设置');
        if (settings.containsKey('theme_mode')) {
          buffer.writeln('  theme_mode: "${settings['theme_mode']}"');
        }
        if (settings.containsKey('dark_mode_pattern_style')) {
          buffer.writeln('  dark_mode_pattern_style: "${settings['dark_mode_pattern_style']}"');
        }
        if (settings.containsKey('compact_amount')) {
          buffer.writeln('  compact_amount: ${settings['compact_amount']}');
        }
        if (settings.containsKey('show_transaction_time')) {
          buffer.writeln('  show_transaction_time: ${settings['show_transaction_time']}');
        }
      }

      if (settings.containsKey('cloud_service_type')) {
        buffer.writeln('  # 云服务');
        buffer.writeln('  cloud_service_type: "${settings['cloud_service_type']}"');
      }

      if (settings.containsKey('auto_screenshot_enabled') ||
          settings.containsKey('shortcut_prefer_camera')) {
        buffer.writeln('  # 自动记账');
        if (settings.containsKey('auto_screenshot_enabled')) {
          buffer.writeln('  auto_screenshot_enabled: ${settings['auto_screenshot_enabled']}');
        }
        if (settings.containsKey('shortcut_prefer_camera')) {
          buffer.writeln('  shortcut_prefer_camera: ${settings['shortcut_prefer_camera']}');
        }
      }
    }

    // 周期账单
    if (yamlMap.containsKey('recurring_transactions')) {
      buffer.writeln('# 周期账单');
      buffer.writeln('recurring_transactions:');
      final recurring = yamlMap['recurring_transactions'] as Map<String, dynamic>;
      final items = recurring['items'] as List;

      if (items.isNotEmpty) {
        buffer.writeln('  items:');
        for (final item in items) {
          final itemMap = item as Map<String, dynamic>;
          buffer.writeln('    - type: "${itemMap['type']}"');
          buffer.writeln('      amount: ${itemMap['amount']}');

          if (itemMap.containsKey('category_id')) {
            buffer.writeln('      category_id: ${itemMap['category_id']}');
          }
          if (itemMap.containsKey('account_id')) {
            buffer.writeln('      account_id: ${itemMap['account_id']}');
          }
          if (itemMap.containsKey('to_account_id')) {
            buffer.writeln('      to_account_id: ${itemMap['to_account_id']}');
          }
          if (itemMap.containsKey('note') && itemMap['note'] != null) {
            buffer.writeln('      note: "${itemMap['note']}"');
          }

          buffer.writeln('      frequency: "${itemMap['frequency']}"');
          buffer.writeln('      interval: ${itemMap['interval']}');

          if (itemMap.containsKey('day_of_month')) {
            buffer.writeln('      day_of_month: ${itemMap['day_of_month']}');
          }
          if (itemMap.containsKey('day_of_week')) {
            buffer.writeln('      day_of_week: ${itemMap['day_of_week']}');
          }
          if (itemMap.containsKey('month_of_year')) {
            buffer.writeln('      month_of_year: ${itemMap['month_of_year']}');
          }

          buffer.writeln('      start_date: "${itemMap['start_date']}"');
          if (itemMap.containsKey('end_date') && itemMap['end_date'] != null) {
            buffer.writeln('      end_date: "${itemMap['end_date']}"');
          }
          buffer.writeln('      enabled: ${itemMap['enabled']}');
        }
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// 从YAML字符串导入配置
  /// [yamlContent] YAML内容
  /// [db] 数据库实例，用于导入周期账单等数据
  /// [ledgerId] 账本ID，用于导入周期账单到指定账本
  static Future<void> importFromYaml(
    String yamlContent, {
    BeeDatabase? db,
    int? ledgerId,
  }) async {
    final doc = loadYaml(yamlContent);

    if (doc is! Map) {
      throw const FormatException('无效的YAML格式');
    }

    final config = AppConfig.fromYaml(doc);
    final prefs = await SharedPreferences.getInstance();

    // 导入Supabase配置
    if (config.supabase != null) {
      final supabaseCfg = CloudServiceConfig(
        type: CloudBackendType.supabase,
        name: 'Supabase',
        supabaseUrl: config.supabase!.url,
        supabaseAnonKey: config.supabase!.anonKey,
      );
      await prefs.setString(
          'cloud_supabase_cfg', encodeCloudConfig(supabaseCfg));
      logger.info('ConfigImport', 'Supabase配置已导入');
    }

    // 导入WebDAV配置
    if (config.webdav != null) {
      final webdavCfg = CloudServiceConfig(
        type: CloudBackendType.webdav,
        name: 'WebDAV',
        webdavUrl: config.webdav!.url,
        webdavUsername: config.webdav!.username,
        webdavPassword: config.webdav!.password,
        webdavRemotePath: config.webdav!.remotePath,
      );
      await prefs.setString('cloud_webdav_cfg', encodeCloudConfig(webdavCfg));
      logger.info('ConfigImport', 'WebDAV配置已导入');
    }

    // 导入AI配置
    if (config.ai != null) {
      if (config.ai!.glmApiKey != null) {
        await prefs.setString('ai_glm_api_key', config.ai!.glmApiKey!);
      }
      if (config.ai!.strategy != null) {
        await prefs.setString('ai_strategy', config.ai!.strategy!);
      }
      if (config.ai!.enabled != null) {
        await prefs.setBool('ai_bill_extraction_enabled', config.ai!.enabled!);
      }
      if (config.ai!.useVision != null) {
        await prefs.setBool('ai_use_vision', config.ai!.useVision!);
      }
      logger.info('ConfigImport', 'AI配置已导入');
    }

    // 导入应用设置
    if (config.appSettings != null) {
      final settings = config.appSettings!;

      // 账户管理
      if (settings.accountFeatureEnabled != null) {
        await prefs.setBool('account_feature_enabled', settings.accountFeatureEnabled!);
      }
      if (settings.defaultIncomeAccountId != null) {
        await prefs.setInt('default_income_account_id', settings.defaultIncomeAccountId!);
      }
      if (settings.defaultExpenseAccountId != null) {
        await prefs.setInt('default_expense_account_id', settings.defaultExpenseAccountId!);
      }

      // 记账提醒
      if (settings.reminderEnabled != null) {
        await prefs.setBool('reminder_enabled', settings.reminderEnabled!);
      }
      if (settings.reminderHour != null) {
        await prefs.setInt('reminder_hour', settings.reminderHour!);
      }
      if (settings.reminderMinute != null) {
        await prefs.setInt('reminder_minute', settings.reminderMinute!);
      }

      // 语言设置
      if (settings.languageCode != null) {
        await prefs.setString('selected_language', settings.languageCode!);
      }
      if (settings.countryCode != null) {
        await prefs.setString('selected_language_country', settings.countryCode!);
      }

      // 个性化设置
      if (settings.primaryColor != null) {
        await prefs.setInt('primaryColor', settings.primaryColor!);
      }
      if (settings.fontScaleLevel != null) {
        await prefs.setInt('fontScaleLevel', settings.fontScaleLevel!);
      }
      if (settings.customFontScale != null) {
        await prefs.setDouble('customFontScale', settings.customFontScale!);
      }

      // 外观设置
      if (settings.themeMode != null) {
        await prefs.setString('themeMode', settings.themeMode!);
      }
      if (settings.darkModePatternStyle != null) {
        await prefs.setString('darkModePatternStyle', settings.darkModePatternStyle!);
      }
      if (settings.compactAmount != null) {
        await prefs.setBool('compactAmount', settings.compactAmount!);
      }
      if (settings.showTransactionTime != null) {
        await prefs.setBool('showTransactionTime', settings.showTransactionTime!);
      }

      // 云服务
      if (settings.cloudServiceType != null) {
        await prefs.setString('selected_cloud_service', settings.cloudServiceType!);
      }

      // 自动记账
      if (settings.autoScreenshotEnabled != null) {
        await prefs.setBool('auto_screenshot_billing_enabled', settings.autoScreenshotEnabled!);
      }
      if (settings.shortcutPreferCamera != null) {
        await prefs.setBool('shortcut_prefer_camera', settings.shortcutPreferCamera!);
      }

      logger.info('ConfigImport', '应用设置已导入');
    }

    // 导入周期账单
    if (config.recurringTransactions != null && db != null && ledgerId != null) {
      try {
        final items = config.recurringTransactions!.items;
        int importedCount = 0;

        for (final item in items) {
          try {
            await db.into(db.recurringTransactions).insert(
              RecurringTransactionsCompanion.insert(
                ledgerId: ledgerId,
                type: item.type,
                amount: item.amount,
                categoryId: d.Value(item.categoryId),
                accountId: d.Value(item.accountId),
                toAccountId: d.Value(item.toAccountId),
                note: d.Value(item.note),
                frequency: item.frequency,
                interval: d.Value(item.interval),
                dayOfMonth: d.Value(item.dayOfMonth),
                dayOfWeek: d.Value(item.dayOfWeek),
                monthOfYear: d.Value(item.monthOfYear),
                startDate: DateTime.parse(item.startDate),
                endDate: d.Value(
                    item.endDate != null ? DateTime.parse(item.endDate!) : null),
                enabled: d.Value(item.enabled),
              ),
            );
            importedCount++;
          } catch (e) {
            logger.warning('ConfigImport', '导入周期账单项失败: $e');
          }
        }

        logger.info('ConfigImport', '周期账单已导入: $importedCount/${items.length}');
      } catch (e) {
        logger.error('ConfigImport', '导入周期账单失败: $e');
      }
    }
  }

  /// 导出配置到文件
  static Future<void> exportToFile(
    String filePath, {
    BeeDatabase? db,
    int? ledgerId,
  }) async {
    final yamlContent = await exportToYaml(db: db, ledgerId: ledgerId);
    final file = File(filePath);
    await file.writeAsString(yamlContent);
    logger.info('ConfigExport', '配置已导出到: $filePath');
  }

  /// 从文件导入配置
  static Future<void> importFromFile(
    String filePath, {
    BeeDatabase? db,
    int? ledgerId,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('文件不存在: $filePath');
    }

    final yamlContent = await file.readAsString();
    await importFromYaml(yamlContent, db: db, ledgerId: ledgerId);
    logger.info('ConfigImport', '配置已从文件导入: $filePath');
  }
}
