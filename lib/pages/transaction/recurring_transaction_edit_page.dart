import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:intl/intl.dart';
import '../../providers.dart';
import '../../widgets/ui/ui.dart';
import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../../services/recurring_transaction_service.dart';
import '../../services/logger_service.dart';
import '../../utils/category_utils.dart';

class RecurringTransactionEditPage extends ConsumerStatefulWidget {
  final RecurringTransaction? recurring;

  const RecurringTransactionEditPage({super.key, this.recurring});

  @override
  ConsumerState<RecurringTransactionEditPage> createState() =>
      _RecurringTransactionEditPageState();
}

class _RecurringTransactionEditPageState
    extends ConsumerState<RecurringTransactionEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  late String _type;
  late RecurringFrequency _frequency;
  late int _interval;
  late DateTime _startDate;
  DateTime? _endDate;
  int? _dayOfMonth;
  Category? _selectedCategory;
  int? _selectedAccountId;
  int? _selectedToAccountId; // 转账的目标账户
  late bool _enabled;
  bool _hasAttemptedSave = false; // 是否已尝试保存

  bool get _isEditing => widget.recurring != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _type = widget.recurring!.type;
      _frequency = RecurringFrequency.fromString(widget.recurring!.frequency);
      _interval = widget.recurring!.interval;
      _startDate = widget.recurring!.startDate;
      _endDate = widget.recurring!.endDate;
      _dayOfMonth = widget.recurring!.dayOfMonth;
      _selectedAccountId = widget.recurring!.accountId;
      _selectedToAccountId = widget.recurring!.toAccountId;
      _enabled = widget.recurring!.enabled;
      _amountController.text = widget.recurring!.amount.toStringAsFixed(2);
      _noteController.text = widget.recurring!.note ?? '';
      _loadCategoryAndAccount();
    } else {
      _type = 'expense';
      _frequency = RecurringFrequency.monthly;
      _interval = 1;
      _startDate = DateTime.now();
      _dayOfMonth = DateTime.now().day;
      _enabled = true;
    }

    // 监听金额输入变化，更新按钮状态
    _amountController.addListener(() {
      setState(() {});
    });
  }

  Future<void> _loadCategoryAndAccount() async {
    if (_isEditing && widget.recurring!.categoryId != null) {
      final db = ref.read(databaseProvider);

      final category = await (db.select(db.categories)
            ..where((c) => c.id.equals(widget.recurring!.categoryId!)))
          .getSingleOrNull();

      setState(() {
        _selectedCategory = category;
      });
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: Column(
        children: [
          PrimaryHeader(
            title: _isEditing
                ? l10n.recurringTransactionEdit
                : l10n.recurringTransactionAdd,
            showBack: true,
            actions: _isEditing
                ? [
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: _deleteRecurringTransaction,
                    ),
                  ]
                : null,
          ),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Type selection
                  _buildTypeSelector(l10n),
                  const SizedBox(height: 16),

                  // Amount
                  TextFormField(
                    controller: _amountController,
                    decoration: InputDecoration(
                      labelText: l10n.importFieldAmount,
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return l10n.commonError;
                      }
                      if (double.tryParse(value) == null) {
                        return l10n.commonError;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Category selection (not for transfer)
                  if (_type != 'transfer') ...[
                    _buildCategorySelector(l10n),
                    const SizedBox(height: 16),
                  ],

                  // Account selection (from account)
                  _buildAccountSelector(l10n, isFromAccount: true),
                  const SizedBox(height: 16),

                  // To account selection (only for transfer)
                  if (_type == 'transfer') ...[
                    _buildAccountSelector(l10n, isFromAccount: false),
                    const SizedBox(height: 16),
                  ],

                  // Frequency
                  _buildFrequencySelector(l10n),
                  const SizedBox(height: 16),

                  // Interval
                  if (_frequency != RecurringFrequency.daily)
                    _buildIntervalSelector(l10n),
                  if (_frequency != RecurringFrequency.daily)
                    const SizedBox(height: 16),

                  // Day of month (for monthly)
                  if (_frequency == RecurringFrequency.monthly)
                    _buildDayOfMonthSelector(l10n),
                  if (_frequency == RecurringFrequency.monthly)
                    const SizedBox(height: 16),

                  // Start date
                  _buildDateField(
                    label: l10n.recurringTransactionStartDate,
                    date: _startDate,
                    onTap: () => _selectDate(context, true),
                  ),
                  const SizedBox(height: 16),

                  // End date
                  _buildDateField(
                    label: l10n.recurringTransactionEndDate,
                    date: _endDate,
                    onTap: () => _selectDate(context, false),
                    allowClear: true,
                    onClear: () => setState(() => _endDate = null),
                  ),
                  const SizedBox(height: 16),

                  // Note
                  TextFormField(
                    controller: _noteController,
                    decoration: InputDecoration(
                      labelText: l10n.commonNoteHint,
                      border: const OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),

                  // Enabled switch
                  Card(
                    child: SwitchListTile(
                      title: Text(l10n.recurringTransactionEnabled),
                      subtitle: Text(_enabled
                          ? l10n.recurringTransactionEnabled
                          : l10n.recurringTransactionDisabled),
                      value: _enabled,
                      onChanged: (value) {
                        setState(() {
                          _enabled = value;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 底部保存按钮
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: _isFormValid() ? _saveRecurringTransaction : null,
              child: Text(l10n.commonSave),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeSelector(AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: RadioListTile<String>(
            title: Text(l10n.categoryExpense,
                style: const TextStyle(fontSize: 14)),
            value: 'expense',
            groupValue: _type,
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            onChanged: (value) {
              setState(() {
                _type = value!;
                _selectedCategory = null; // Reset category when type changes
                _selectedToAccountId = null; // Reset transfer account
              });
            },
          ),
        ),
        Expanded(
          child: RadioListTile<String>(
            title:
                Text(l10n.categoryIncome, style: const TextStyle(fontSize: 14)),
            value: 'income',
            groupValue: _type,
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            onChanged: (value) {
              setState(() {
                _type = value!;
                _selectedCategory = null; // Reset category when type changes
                _selectedToAccountId = null; // Reset transfer account
              });
            },
          ),
        ),
        Expanded(
          child: RadioListTile<String>(
            title:
                Text(l10n.transferTitle, style: const TextStyle(fontSize: 14)),
            value: 'transfer',
            groupValue: _type,
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            onChanged: (value) {
              setState(() {
                _type = value!;
                _selectedCategory = null; // Reset category when type changes
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCategorySelector(AppLocalizations l10n) {
    return InkWell(
      onTap: () => _selectCategory(),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: l10n.categoryTitle,
          border: const OutlineInputBorder(),
          errorText: _getCategoryErrorText(),
        ),
        child: Text(
          _selectedCategory != null
              ? CategoryUtils.getDisplayName(_selectedCategory!.name, context)
              : l10n.commonSearch,
        ),
      ),
    );
  }

  Widget _buildAccountSelector(AppLocalizations l10n,
      {required bool isFromAccount}) {
    final accountId = isFromAccount ? _selectedAccountId : _selectedToAccountId;
    final label = isFromAccount
        ? (_type == 'transfer'
            ? l10n.transferFromAccount
            : l10n.accountSelectTitle)
        : l10n.transferToAccount;

    return InkWell(
      onTap: () => _selectAccount(isFromAccount: isFromAccount),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          errorText: _getAccountErrorText(isFromAccount),
        ),
        child: FutureBuilder<Account?>(
          future: accountId != null
              ? ref.read(repositoryProvider).getAccount(accountId)
              : Future.value(null),
          builder: (context, snapshot) {
            final accountName = snapshot.data?.name ?? l10n.accountNone;
            return Text(accountName);
          },
        ),
      ),
    );
  }

  String? _getAccountErrorText(bool isFromAccount) {
    if (!_hasAttemptedSave) return null;

    final l10n = AppLocalizations.of(context);

    if (isFromAccount) {
      if (_type == 'transfer' && _selectedAccountId == null) {
        return '请选择转出账户';
      }
    } else {
      if (_type == 'transfer' && _selectedToAccountId == null) {
        return '请选择转入账户';
      }
      if (_type == 'transfer' &&
          _selectedAccountId != null &&
          _selectedToAccountId != null &&
          _selectedAccountId == _selectedToAccountId) {
        return '转出账户和转入账户不能相同';
      }
    }

    return null;
  }

  String? _getCategoryErrorText() {
    if (!_hasAttemptedSave) return null;
    if (_type != 'transfer' && _selectedCategory == null) {
      return '请选择分类';
    }
    return null;
  }

  bool _isFormValid() {
    // 检查金额
    if (_amountController.text.isEmpty ||
        double.tryParse(_amountController.text) == null) {
      return false;
    }

    // 检查分类（非转账）
    if (_type != 'transfer' && _selectedCategory == null) {
      return false;
    }

    // 检查转账账户
    if (_type == 'transfer') {
      if (_selectedAccountId == null || _selectedToAccountId == null) {
        return false;
      }
      if (_selectedAccountId == _selectedToAccountId) {
        return false;
      }
    }

    return true;
  }

  Widget _buildFrequencySelector(AppLocalizations l10n) {
    String frequencyLabel;
    switch (_frequency) {
      case RecurringFrequency.daily:
        frequencyLabel = l10n.recurringTransactionDaily;
        break;
      case RecurringFrequency.weekly:
        frequencyLabel = l10n.recurringTransactionWeekly;
        break;
      case RecurringFrequency.monthly:
        frequencyLabel = l10n.recurringTransactionMonthly;
        break;
      case RecurringFrequency.yearly:
        frequencyLabel = l10n.recurringTransactionYearly;
        break;
    }

    return InkWell(
      onTap: () async {
        final result = await showWheelPicker<RecurringFrequency>(
          context,
          initial: _frequency,
          items: RecurringFrequency.values,
          labelBuilder: (freq) {
            switch (freq) {
              case RecurringFrequency.daily:
                return l10n.recurringTransactionDaily;
              case RecurringFrequency.weekly:
                return l10n.recurringTransactionWeekly;
              case RecurringFrequency.monthly:
                return l10n.recurringTransactionMonthly;
              case RecurringFrequency.yearly:
                return l10n.recurringTransactionYearly;
            }
          },
          title: l10n.recurringTransactionFrequency,
        );

        if (result != null) {
          setState(() {
            _frequency = result;
            if (_frequency == RecurringFrequency.daily) {
              _interval = 1;
            }
          });
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: l10n.recurringTransactionFrequency,
          border: const OutlineInputBorder(),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(frequencyLabel),
            const Icon(Icons.arrow_drop_down, size: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildIntervalSelector(AppLocalizations l10n) {
    String intervalLabel;
    switch (_frequency) {
      case RecurringFrequency.daily:
        intervalLabel = l10n.recurringTransactionEveryNDays(_interval);
        break;
      case RecurringFrequency.weekly:
        intervalLabel = l10n.recurringTransactionEveryNWeeks(_interval);
        break;
      case RecurringFrequency.monthly:
        intervalLabel = l10n.recurringTransactionEveryNMonths(_interval);
        break;
      case RecurringFrequency.yearly:
        intervalLabel = l10n.recurringTransactionEveryNYears(_interval);
        break;
    }

    return InkWell(
      onTap: () async {
        final result = await showWheelPicker<int>(
          context,
          initial: _interval,
          items: List.generate(12, (index) => index + 1),
          labelBuilder: (i) {
            switch (_frequency) {
              case RecurringFrequency.daily:
                return l10n.recurringTransactionEveryNDays(i);
              case RecurringFrequency.weekly:
                return l10n.recurringTransactionEveryNWeeks(i);
              case RecurringFrequency.monthly:
                return l10n.recurringTransactionEveryNMonths(i);
              case RecurringFrequency.yearly:
                return l10n.recurringTransactionEveryNYears(i);
            }
          },
          title: l10n.recurringTransactionInterval,
        );

        if (result != null) {
          setState(() {
            _interval = result;
          });
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: l10n.recurringTransactionInterval,
          border: const OutlineInputBorder(),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(intervalLabel),
            const Icon(Icons.arrow_drop_down, size: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildDayOfMonthSelector(AppLocalizations l10n) {
    return InkWell(
      onTap: () async {
        final result = await showWheelPicker<int>(
          context,
          initial: _dayOfMonth ?? 1,
          items: List.generate(31, (index) => index + 1),
          labelBuilder: (day) => '$day',
          title: l10n.recurringTransactionDayOfMonth,
        );

        if (result != null) {
          setState(() {
            _dayOfMonth = result;
          });
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: l10n.recurringTransactionDayOfMonth,
          border: const OutlineInputBorder(),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${_dayOfMonth ?? 1}'),
            const Icon(Icons.arrow_drop_down, size: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildDateField({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
    bool allowClear = false,
    VoidCallback? onClear,
  }) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: allowClear && date != null
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: onClear,
                )
              : null,
        ),
        child: Text(
          date != null
              ? DateFormat.yMd().format(date)
              : AppLocalizations.of(context).recurringTransactionNoEndDate,
        ),
      ),
    );
  }

  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    final date = await showWheelDatePicker(
      context,
      initial: isStartDate ? _startDate : (_endDate ?? DateTime.now()),
      minDate: DateTime(2000),
      maxDate: DateTime(2100),
    );

    if (date != null) {
      setState(() {
        if (isStartDate) {
          _startDate = date;
        } else {
          _endDate = date;
        }
      });
    }
  }

  Future<void> _selectCategory() async {
    final db = ref.read(databaseProvider);
    final categories = await (db.select(db.categories)
          ..where((c) => c.kind.equals(_type)))
        .get();

    if (!mounted) return;

    final selected = await showDialog<Category>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).categoryTitle),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories[index];
              return ListTile(
                title:
                    Text(CategoryUtils.getDisplayName(category.name, context)),
                onTap: () => Navigator.of(context).pop(category),
              );
            },
          ),
        ),
      ),
    );

    if (selected != null) {
      setState(() {
        _selectedCategory = selected;
      });
    }
  }

  Future<void> _selectAccount({required bool isFromAccount}) async {
    final repo = ref.read(repositoryProvider);
    final ledgerId = ref.read(currentLedgerIdProvider);
    final ledger = await ref.read(ledgerByIdProvider(ledgerId).future);

    if (ledger == null) return;

    // 获取所有账户，然后过滤与当前账本币种相同的账户
    final allAccounts = await repo.getAllAccounts();
    var accounts =
        allAccounts.where((a) => a.currency == ledger.currency).toList();

    // 如果是选择转入账户，排除已选择的转出账户
    if (!isFromAccount && _selectedAccountId != null) {
      accounts = accounts.where((a) => a.id != _selectedAccountId).toList();
    }

    if (!mounted) return;

    final title = isFromAccount
        ? (_type == 'transfer'
            ? AppLocalizations.of(context).transferFromAccount
            : AppLocalizations.of(context).accountSelectTitle)
        : AppLocalizations.of(context).transferToAccount;

    final selected = await showDialog<int?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: accounts.length +
                (_type == 'transfer' && !isFromAccount ? 0 : 1), // 转入账户不显示"无账户"
            itemBuilder: (context, index) {
              if (index == 0 && (_type != 'transfer' || isFromAccount)) {
                return ListTile(
                  title: Text(AppLocalizations.of(context).accountNone),
                  onTap: () => Navigator.of(context).pop(null),
                );
              }
              final accountIndex =
                  _type == 'transfer' && !isFromAccount ? index : index - 1;
              final account = accounts[accountIndex];
              return ListTile(
                title: Text(account.name),
                onTap: () => Navigator.of(context).pop(account.id),
              );
            },
          ),
        ),
      ),
    );

    // 用户点击了选项或取消
    setState(() {
      if (isFromAccount) {
        _selectedAccountId = selected;
        // 如果转出账户与转入账户相同，清空转入账户
        if (_type == 'transfer' && selected == _selectedToAccountId) {
          _selectedToAccountId = null;
        }
      } else {
        _selectedToAccountId = selected;
      }
    });
  }

  Future<void> _saveRecurringTransaction() async {
    final l10n = AppLocalizations.of(context);

    // 标记为已尝试保存，触发错误提示显示
    setState(() {
      _hasAttemptedSave = true;
    });

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (!_isFormValid()) {
      return;
    }

    final db = ref.read(databaseProvider);
    final service = RecurringTransactionService(db);
    final ledgerId = ref.read(currentLedgerIdProvider);

    final companion = RecurringTransactionsCompanion(
      ledgerId: drift.Value(ledgerId),
      type: drift.Value(_type),
      amount: drift.Value(double.parse(_amountController.text)),
      categoryId:
          drift.Value(_type == 'transfer' ? null : _selectedCategory!.id),
      accountId: drift.Value(_selectedAccountId),
      toAccountId: drift.Value(_selectedToAccountId),
      note: drift.Value(
          _noteController.text.isEmpty ? null : _noteController.text),
      frequency: drift.Value(_frequency.value),
      interval: drift.Value(_interval),
      dayOfMonth: drift.Value(_dayOfMonth),
      startDate: drift.Value(_startDate),
      endDate: drift.Value(_endDate),
      enabled: drift.Value(_enabled),
      updatedAt: drift.Value(DateTime.now()),
    );

    try {
      if (_isEditing) {
        await service.updateRecurringTransaction(
            widget.recurring!.id, companion);
      } else {
        await service.createRecurringTransaction(companion);
      }

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e, stackTrace) {
      // 使用 logger 记录详细错误信息
      logger.error('周期账单保存', '保存失败', e, stackTrace);
      if (mounted) {
        showToast(context, '${l10n.commonError}: $e');
      }
    }
  }

  Future<void> _deleteRecurringTransaction() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).commonDelete),
        content: Text(
            AppLocalizations.of(context).recurringTransactionDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppLocalizations.of(context).commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(AppLocalizations.of(context).commonDelete),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final db = ref.read(databaseProvider);
      final service = RecurringTransactionService(db);
      await service.deleteRecurringTransaction(widget.recurring!.id);

      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }
}
