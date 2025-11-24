import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:beecount/widgets/ui/wheel_date_picker.dart';
import '../../styles/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../services/note_history_service.dart';
import '../../data/db.dart';
import '../../providers.dart';
import 'note_picker_dialog.dart';
import 'account_selector.dart';

typedef AmountEditorResult = ({
  double amount,
  String? note,
  DateTime date,
  int? accountId
});

class AmountEditorSheet extends ConsumerStatefulWidget {
  final String categoryName; // 仅用于上层提交，不在UI展示
  final DateTime initialDate;
  final double? initialAmount;
  final String? initialNote;
  final int? initialAccountId;
  final bool showAccountPicker; // 是否显示账户选择
  final ValueChanged<AmountEditorResult> onSubmit;
  final BeeDatabase db;
  final int ledgerId;

  const AmountEditorSheet({
    super.key,
    required this.categoryName,
    required this.initialDate,
    this.initialAmount,
    this.initialNote,
    this.initialAccountId,
    this.showAccountPicker = false,
    required this.onSubmit,
    required this.db,
    required this.ledgerId,
  });

  @override
  ConsumerState<AmountEditorSheet> createState() => _AmountEditorSheetState();
}

class _AmountEditorSheetState extends ConsumerState<AmountEditorSheet> {
  late String _amountStr;
  late DateTime _date;
  int? _selectedAccountId;
  final bool _negative = false; // 显示用途，仅影响UI，不改变保存逻辑
  final TextEditingController _noteCtrl = TextEditingController();
  // 运算缓存：支持简单 + / - 键入累计
  double _acc = 0;
  String _op = '+'; // 最近一次运算符

  // 高频备注列表（包含使用次数）
  List<({String note, int count})> _frequentNotes = [];

  // 备注框焦点节点
  final FocusNode _noteFocusNode = FocusNode();
  bool _noteFieldHasFocus = false;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
    _selectedAccountId = widget.initialAccountId;
    // 保留原始小数（最多两位），避免编辑已有记录时小数被截断为整数
    final init = widget.initialAmount ?? 0;
    final s = init.toStringAsFixed(2);
    // 去除多余 0 和结尾的小数点
    final trimmed = s.contains('.')
        ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
        : s;
    _amountStr = trimmed.isEmpty ? '0' : trimmed;
    _noteCtrl.text = widget.initialNote ?? '';

    // 监听焦点变化
    _noteFocusNode.addListener(() {
      setState(() {
        _noteFieldHasFocus = _noteFocusNode.hasFocus;
      });
    });

    // 加载最近使用的备注
    _loadRecentNotes();
  }

  @override
  void dispose() {
    _noteFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadRecentNotes() async {
    final notes = await NoteHistoryService.getFrequentNotes(
      widget.db,
      widget.ledgerId,
      limit: 20,
    );
    setState(() {
      _frequentNotes = notes;
    });
  }

  void _append(String s) {
    setState(() {
      if (s == '.') {
        if (_amountStr.contains('.')) return;
      }
      // 限制两位小数
      if (_amountStr.contains('.')) {
        final dot = _amountStr.indexOf('.');
        final decimals = _amountStr.length - dot - 1;
        if (s != '.' && decimals >= 2) return;
      }
      // 去除前导 0
      if (_amountStr == '0' && s != '.') {
        _amountStr = s;
      } else if (_amountStr == '-0' && s != '.') {
        _amountStr = '-$s';
      } else {
        _amountStr += s;
      }
    });
    SystemSound.play(SystemSoundType.click);
  }

  void _backspace() {
    setState(() {
      if (_amountStr.isEmpty) return;
      _amountStr = _amountStr.substring(0, _amountStr.length - 1);
      if (_amountStr.isEmpty) _amountStr = '0';
    });
    SystemSound.play(SystemSoundType.click);
  }

  // 旧 _toggleSign 已废弃，符号由类别含义决定

  // _setToday 移除，改为点击日历按钮选择日期

  void _pickDate() async {
    // 关闭键盘，避免选择日期后键盘重新弹出
    FocusManager.instance.primaryFocus?.unfocus();

    // 等待键盘完全关闭
    await Future.delayed(const Duration(milliseconds: 100));

    if (!mounted) return;

    final showTime = ref.read(showTransactionTimeProvider);

    if (showTime) {
      // 显示时间功能开启时，使用两步选择器（先日期后时间）
      final res = await showWheelDateTimePicker(
        context,
        initial: _date,
        maxDate: DateTime.now(),
      );
      if (res != null) setState(() => _date = res);
    } else {
      // 普通模式，只选择日期
      final res = await showWheelDatePicker(
        context,
        initial: _date,
        mode: WheelDatePickerMode.ymd,
        maxDate: DateTime.now(),
      );
      if (res != null) setState(() => _date = res);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final text = Theme.of(context).textTheme;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    // 如果备注框有焦点且键盘弹出，固定增加100的padding
    final extraPadding = (_noteFieldHasFocus && keyboardHeight > 0) ? 100.0 : 0.0;

    double parsed() => double.tryParse(_amountStr) ?? 0.0;

    void applyOp(String op) {
      final cur = parsed();
      if (_op == '+') {
        _acc += cur;
      } else if (_op == '-') {
        _acc -= cur;
      }
      _op = op;
      _amountStr = '0';
      HapticFeedback.selectionClick();
      SystemSound.play(SystemSoundType.click);
      setState(() {});
    }

    Widget keyBtn(String label, {Color? bg, Color? fg, VoidCallback? onTap}) {
      return Padding(
        padding: const EdgeInsets.all(6),
        child: Material(
          color: bg ?? BeeTokens.surfaceKey(context),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              height: 60,
              alignment: Alignment.center,
              child: Text(
                label,
                style: text.titleMedium?.copyWith(
                  color: fg ?? BeeTokens.textPrimary(context),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      );
    }

    String fmtDate(DateTime d) => '${d.year}/${d.month}/${d.day}';
    String fmtTime(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';
    final showTime = ref.watch(showTransactionTimeProvider);

    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 100),
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          16 + extraPadding,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 金额单独一行（右对齐）
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // 运算状态符号（+ / -），更直观地展示当前累加/累减状态
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    _op == '-' ? '−' : '+',
                    style: text.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: BeeTokens.textPrimary(context),
                    ),
                  ),
                ),
                Text(
                  (_negative ? '-' : '') +
                      (() {
                        final cur = parsed();
                        final total = _op == '+' || _op == '-'
                            ? (_acc + (_op == '+' ? cur : -cur))
                            : cur;
                        // 不显示多余 0
                        final s = total.toStringAsFixed(2);
                        final r1 = s.contains('.')
                            ? s.replaceFirst(RegExp(r'0+$'), '')
                            : s;
                        final r2 = r1.endsWith('.')
                            ? r1.substring(0, r1.length - 1)
                            : r1;
                        return r2.isEmpty ? '0' : r2;
                      })(),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.0,
                    color: BeeTokens.textPrimary(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 备注输入区域 - 带历史备注图标前缀
            TextField(
              focusNode: _noteFocusNode,
              controller: _noteCtrl,
              style: TextStyle(color: BeeTokens.textPrimary(context)),
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context).commonNoteHint,
                hintStyle: TextStyle(color: BeeTokens.textTertiary(context)),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: BeeTokens.surfaceInput(context),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                // 历史备注图标作为前缀
                prefixIcon: _frequentNotes.isNotEmpty
                    ? GestureDetector(
                        onTap: () async {
                          await showDialog(
                            context: context,
                            builder: (context) => NotePickerDialog(
                              db: widget.db,
                              ledgerId: widget.ledgerId,
                              categoryId: null,
                              onNotePicked: (note) {
                                setState(() {
                                  _noteCtrl.text = note;
                                  _noteCtrl.selection = TextSelection.fromPosition(
                                    TextPosition(offset: note.length),
                                  );
                                });
                              },
                            ),
                          );
                        },
                        child: Icon(
                          Icons.history,
                          color: BeeTokens.iconSecondary(context),
                          size: 20,
                        ),
                      )
                    : null,
                prefixIconConstraints: _frequentNotes.isNotEmpty
                    ? const BoxConstraints(
                        minWidth: 40,
                        minHeight: 20,
                      )
                    : null,
              ),
            ),
            // 账户选择（仅在启用时显示）
            if (widget.showAccountPicker) ...[
              const SizedBox(height: 8),
              Consumer(
                builder: (context, ref, child) {
                  // 检查账户功能是否启用
                  final accountFeatureAsync =
                      ref.watch(accountFeatureEnabledProvider);
                  return accountFeatureAsync.when(
                    data: (enabled) {
                      if (!enabled) return const SizedBox.shrink();

                      // 使用新的横滑账户选择器
                      return AccountSelector(
                        db: widget.db,
                        selectedAccountId: _selectedAccountId,
                        ledgerId: widget.ledgerId,
                        onAccountSelected: (accountId) {
                          setState(() {
                            _selectedAccountId = accountId;
                          });
                        },
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  );
                },
              ),
            ],
            const SizedBox(height: 10),
            // 数字键盘
            LayoutBuilder(builder: (ctx, c) {
              final w = (c.maxWidth) / 4;
              Widget dateKey() => Padding(
                    padding: const EdgeInsets.all(6),
                    child: Material(
                      color: BeeTokens.surfaceKeySecondary(context),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          SystemSound.play(SystemSoundType.click);
                          _pickDate();
                        },
                        child: SizedBox(
                          height: 60,
                          child: Center(
                            child: showTime
                                ? Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        fmtDate(_date),
                                        style: text.labelSmall?.copyWith(
                                            color: BeeTokens.textPrimary(context),
                                            fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        fmtTime(_date),
                                        style: text.labelSmall?.copyWith(
                                            color: BeeTokens.textSecondary(context),
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  )
                                : Text(
                                    fmtDate(_date),
                                    style: text.labelMedium?.copyWith(
                                        color: BeeTokens.textPrimary(context),
                                        fontWeight: FontWeight.w600),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  );
              Widget closeKey() => Padding(
                    padding: const EdgeInsets.all(6),
                    child: Material(
                      color: BeeTokens.surfaceKey(context),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _backspace,
                        child: SizedBox(
                          height: 60,
                          child: Center(
                              child: Icon(Icons.backspace_outlined,
                                  color: BeeTokens.textPrimary(context))),
                        ),
                      ),
                    ),
                  );
              Widget doneKey() {
                // 计算当前总额以判断是否启用完成按钮
                final cur = parsed();
                double total = _acc;
                if (_op == '+') {
                  total += cur;
                } else if (_op == '-') {
                  total -= cur;
                } else {
                  total = cur;
                }
                final isEnabled = total.abs() > 0;

                return Padding(
                  padding: const EdgeInsets.all(6),
                  child: Material(
                    color: isEnabled ? primary : BeeTokens.surfaceDisabled(context),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: isEnabled
                          ? () async {
                              HapticFeedback.lightImpact();
                              SystemSound.play(SystemSoundType.click);
                              widget.onSubmit((
                                amount: total.abs(), // 始终正数
                                note: _noteCtrl.text.isEmpty
                                    ? null
                                    : _noteCtrl.text,
                                date: _date,
                                accountId: _selectedAccountId,
                              ));
                            }
                          : null,
                      child: SizedBox(
                        height: 60,
                        child: Center(
                          child: Text(
                            AppLocalizations.of(context).commonFinish,
                            style: TextStyle(
                                color: isEnabled ? Colors.white : BeeTokens.textTertiary(context),
                                fontSize: 16,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }

              return Column(
                children: [
                  Row(children: [
                    SizedBox(
                        width: w,
                        child: keyBtn('7', onTap: () => _append('7'))),
                    SizedBox(
                        width: w,
                        child: keyBtn('8', onTap: () => _append('8'))),
                    SizedBox(
                        width: w,
                        child: keyBtn('9', onTap: () => _append('9'))),
                    SizedBox(width: w, child: dateKey()),
                  ]),
                  const SizedBox(height: 2),
                  Row(children: [
                    SizedBox(
                        width: w,
                        child: keyBtn('4', onTap: () => _append('4'))),
                    SizedBox(
                        width: w,
                        child: keyBtn('5', onTap: () => _append('5'))),
                    SizedBox(
                        width: w,
                        child: keyBtn('6', onTap: () => _append('6'))),
                    SizedBox(
                        width: w,
                        child: keyBtn('+',
                            bg: BeeTokens.surfaceKeySecondary(context), onTap: () => applyOp('+'))),
                  ]),
                  const SizedBox(height: 2),
                  Row(children: [
                    SizedBox(
                        width: w,
                        child: keyBtn('1', onTap: () => _append('1'))),
                    SizedBox(
                        width: w,
                        child: keyBtn('2', onTap: () => _append('2'))),
                    SizedBox(
                        width: w,
                        child: keyBtn('3', onTap: () => _append('3'))),
                    SizedBox(
                        width: w,
                        child: keyBtn('-',
                            bg: BeeTokens.surfaceKeySecondary(context), onTap: () => applyOp('-'))),
                  ]),
                  const SizedBox(height: 2),
                  Row(children: [
                    SizedBox(
                        width: w,
                        child: keyBtn('.', onTap: () => _append('.'))),
                    SizedBox(
                        width: w,
                        child: keyBtn('0', onTap: () => _append('0'))),
                    SizedBox(width: w, child: closeKey()),
                    SizedBox(width: w, child: doneKey()),
                  ]),
                ],
              );
            })
          ],
        ),
      ),
    );
  }

}
