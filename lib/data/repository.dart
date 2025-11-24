import 'package:drift/drift.dart' as d;

import 'db.dart';
import 'category_node.dart';
import '../services/logger_service.dart';

class BeeRepository {
  final BeeDatabase db;
  BeeRepository(this.db);

  Stream<List<Transaction>> recentTransactions(
      {required int ledgerId, int limit = 20}) {
    final q = (db.select(db.transactions)
          ..where((t) => t.ledgerId.equals(ledgerId))
          ..orderBy([
            (t) => d.OrderingTerm(
                expression: t.happenedAt, mode: d.OrderingMode.desc)
          ])
          ..limit(limit))
        .watch();
    return q;
  }

  // Lightweight counts for Settings header (performance-friendly)
  Future<int> ledgerCount() async {
    final row = await db.customSelect('SELECT COUNT(*) AS c FROM ledgers',
        readsFrom: {db.ledgers}).getSingle();
    final v = row.data['c'];
    if (v is int) return v;
    if (v is BigInt) return v.toInt();
    if (v is num) return v.toInt();
    return 0;
  }

  Future<({int dayCount, int txCount})> countsForLedger(
      {required int ledgerId}) async {
    final txRow = await db.customSelect(
        'SELECT COUNT(*) AS c FROM transactions WHERE ledger_id = ?1',
        variables: [d.Variable.withInt(ledgerId)],
        readsFrom: {db.transactions}).getSingle();
    // 计算记账天数：今天 - 第一笔记账日期 + 1
    final dayRow = await db.customSelect("""
      SELECT CASE
        WHEN MIN(happened_at) IS NULL THEN 0
        ELSE CAST(julianday('now', 'localtime') - julianday(MIN(happened_at), 'unixepoch', 'localtime') + 1 AS INTEGER)
      END AS c
      FROM transactions WHERE ledger_id = ?1
      """,
        variables: [d.Variable.withInt(ledgerId)],
        readsFrom: {db.transactions}).getSingle();

    int parse(dynamic v) {
      if (v is int) return v;
      if (v is BigInt) return v.toInt();
      if (v is num) return v.toInt();
      return 0;
    }

    return (dayCount: parse(dayRow.data['c']), txCount: parse(txRow.data['c']));
  }

  /// 全部账本的聚合统计：总笔数与记账天数（不同日期求去重）
  Future<({int dayCount, int txCount})> countsAll() async {
    final txRow = await db.customSelect(
      'SELECT COUNT(*) AS c FROM transactions',
      readsFrom: {db.transactions},
    ).getSingle();
    // 计算记账天数：今天 - 第一笔记账日期 + 1
    final dayRow = await db.customSelect(
      """
      SELECT CASE
        WHEN MIN(happened_at) IS NULL THEN 0
        ELSE CAST(julianday('now', 'localtime') - julianday(MIN(happened_at), 'unixepoch', 'localtime') + 1 AS INTEGER)
      END AS c
      FROM transactions
      """,
      readsFrom: {db.transactions},
    ).getSingle();

    int parse(dynamic v) {
      if (v is int) return v;
      if (v is BigInt) return v.toInt();
      if (v is num) return v.toInt();
      return 0;
    }

    return (dayCount: parse(dayRow.data['c']), txCount: parse(txRow.data['c']));
  }

  // Aggregation: totals by category for a period and type (income/expense)
  Future<List<({int? id, String name, String? icon, double total})>> totalsByCategory({
    required int ledgerId,
    required String type, // 'income' or 'expense'
    required DateTime start,
    required DateTime end,
  }) async {
    final q = (db.select(db.transactions)
          ..where((t) =>
              t.ledgerId.equals(ledgerId) &
              t.type.equals(type) &
              t.happenedAt.isBetweenValues(start, end)))
        .join([
      d.leftOuterJoin(db.categories,
          db.categories.id.equalsExp(db.transactions.categoryId)),
    ]);
    final rows = await q.get();
    final map = <int?, double>{}; // categoryId (nullable) -> total
    final names = <int?, String>{};
    final icons = <int?, String?>{};
    for (final r in rows) {
      final t = r.readTable(db.transactions);
      final c = r.readTableOrNull(db.categories);
      final id = c?.id;
      final name = c?.name ?? '未分类';
      final icon = c?.icon;
      names[id] = name;
      icons[id] = icon;
      map.update(id, (v) => v + t.amount, ifAbsent: () => t.amount);
    }
    final list = map.entries
        .map((e) => (id: e.key, name: names[e.key] ?? '未分类', icon: icons[e.key], total: e.value))
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    return list;
  }

  // Aggregation: totals by day for a period and type
  Future<List<({DateTime day, double total})>> totalsByDay({
    required int ledgerId,
    required String type, // 'income' or 'expense'
    required DateTime start,
    required DateTime end,
  }) async {
    final rows = await (db.select(db.transactions)
          ..where((t) =>
              t.ledgerId.equals(ledgerId) &
              t.type.equals(type) &
              t.happenedAt.isBetweenValues(start, end)))
        .get();
    final map = <DateTime, double>{};
    for (final t in rows) {
      final dt = t.happenedAt.toLocal();
      final day = DateTime(dt.year, dt.month, dt.day);
      map.update(day, (v) => v + t.amount, ifAbsent: () => t.amount);
    }
    // ensure full range continuity
    final result = <({DateTime day, double total})>[];
    for (DateTime d = DateTime(start.year, start.month, start.day);
        d.isBefore(end);
        d = d.add(const Duration(days: 1))) {
      result.add((day: d, total: map[d] ?? 0));
    }
    return result;
  }

  /// 统计指定账本、类型与时间范围内是否存在交易（返回记录条数）
  Future<int> countByTypeInRange({
    required int ledgerId,
    required String type, // 'income' | 'expense'
    required DateTime start,
    required DateTime end,
  }) async {
    final row = await db.customSelect(
      'SELECT COUNT(*) AS c FROM transactions WHERE ledger_id = ?1 AND type = ?2 AND happened_at >= ?3 AND happened_at < ?4',
      variables: [
        d.Variable<int>(ledgerId),
        d.Variable<String>(type),
        d.Variable<DateTime>(start),
        d.Variable<DateTime>(end),
      ],
      readsFrom: {db.transactions},
    ).getSingle();
    final v = row.data['c'];
    if (v is int) return v;
    if (v is BigInt) return v.toInt();
    if (v is num) return v.toInt();
    return 0;
  }

  // Transactions with category filter within a range (by categoryId and type)
  Stream<List<({Transaction t, Category? category})>>
      transactionsForCategoryInRange({
    required int ledgerId,
    required DateTime start,
    required DateTime end,
    int? categoryId,
    required String type, // 'income' or 'expense'
  }) {
    final base = (db.select(db.transactions)
          ..where((t) =>
              t.ledgerId.equals(ledgerId) &
              t.type.equals(type) &
              t.happenedAt.isBetweenValues(start, end))
          ..orderBy([
            (t) => d.OrderingTerm(
                expression: t.happenedAt, mode: d.OrderingMode.desc)
          ]))
        .join([
      d.leftOuterJoin(db.categories,
          db.categories.id.equalsExp(db.transactions.categoryId)),
    ]);
    if (categoryId == null) {
      base.where(db.transactions.categoryId.isNull());
    } else {
      base.where(db.transactions.categoryId.equals(categoryId));
    }
    return base.watch().map((rows) => rows
        .map((r) => (
              t: r.readTable(db.transactions),
              category: r.readTableOrNull(db.categories)
            ))
        .toList());
  }

  // Aggregation: totals by month for a year and type
  Future<List<({DateTime month, double total})>> totalsByMonth({
    required int ledgerId,
    required String type, // 'income' or 'expense'
    required int year,
  }) async {
    final start = DateTime(year, 1, 1);
    final end = DateTime(year + 1, 1, 1);
    final rows = await (db.select(db.transactions)
          ..where((t) =>
              t.ledgerId.equals(ledgerId) &
              t.type.equals(type) &
              t.happenedAt.isBetweenValues(start, end)))
        .get();
    final map = <int, double>{}; // month -> total
    for (final t in rows) {
      final dt = t.happenedAt.toLocal();
      map.update(dt.month, (v) => v + t.amount, ifAbsent: () => t.amount);
    }
    final result = <({DateTime month, double total})>[];
    for (int m = 1; m <= 12; m++) {
      result.add((month: DateTime(year, m, 1), total: map[m] ?? 0));
    }
    return result;
  }

  // Aggregation: totals by year (all years) for a type
  Future<List<({int year, double total})>> totalsByYearSeries({
    required int ledgerId,
    required String type, // 'income' or 'expense'
  }) async {
    final rows = await (db.select(db.transactions)
          ..where((t) => t.ledgerId.equals(ledgerId) & t.type.equals(type)))
        .get();
    if (rows.isEmpty) return const [];
    final map = <int, double>{};
    int minYear = 9999, maxYear = 0;
    for (final t in rows) {
      final y = t.happenedAt.toLocal().year;
      if (y < minYear) minYear = y;
      if (y > maxYear) maxYear = y;
      map.update(y, (v) => v + t.amount, ifAbsent: () => t.amount);
    }
    final out = <({int year, double total})>[];
    for (int y = minYear; y <= maxYear; y++) {
      out.add((year: y, total: map[y] ?? 0));
    }
    return out;
  }

  // Aggregation: income & expense totals for arbitrary range
  Future<(double income, double expense)> totalsInRange({
    required int ledgerId,
    required DateTime start,
    required DateTime end,
  }) async {
    final list = await (db.select(db.transactions)
          ..where((t) =>
              t.ledgerId.equals(ledgerId) &
              t.happenedAt.isBetweenValues(start, end)))
        .get();
    double income = 0, expense = 0;
    for (final t in list) {
      if (t.type == 'income') income += t.amount;
      if (t.type == 'expense') expense += t.amount;
    }
    return (income, expense);
  }

  Stream<List<Transaction>> transactionsInMonth(
      {required int ledgerId, required DateTime month}) {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    final q = (db.select(db.transactions)
          ..where((t) =>
              t.ledgerId.equals(ledgerId) &
              t.happenedAt.isBetweenValues(start, end))
          ..orderBy([
            (t) => d.OrderingTerm(
                expression: t.happenedAt, mode: d.OrderingMode.desc)
          ]))
        .watch();
    return q;
  }

  /// 获取账本统计信息（余额、交易数等）
  /// [accountFeatureEnabled] 是否已开启账户管理功能（v1.15.0已废弃，保留参数兼容）
  /// [transactions] 可选的已查询交易列表，避免重复查询
  ///
  /// 返回 record: (balance: 余额, transactionCount: 交易数)
  ///
  /// v1.15.0: 账户独立后，账本余额不再叠加账户初始余额
  Future<({double balance, int transactionCount})> getLedgerStats({
    required int ledgerId,
    bool accountFeatureEnabled = true,
    List<Transaction>? transactions,
  }) async {
    // 如果没有传入 transactions，则查询
    final rows = transactions ?? await (db.select(db.transactions)
          ..where((t) => t.ledgerId.equals(ledgerId)))
        .get();

    // 交易数
    final transactionCount = rows.length;

    // v1.15.0: 账户独立后，账本余额仅计算交易收支，不再叠加账户初始余额
    double balance = 0.0;

    // 加上所有交易的收支
    for (final t in rows) {
      if (t.type == 'income') {
        balance += t.amount;
      } else if (t.type == 'expense') {
        balance -= t.amount;
      }
      // transfer 不影响总余额
    }

    return (balance: balance, transactionCount: transactionCount);
  }

  Future<int> addTransaction({
    required int ledgerId,
    required String type, // expense / income / transfer
    required double amount,
    int? categoryId,
    int? accountId,
    int? toAccountId,
    required DateTime happenedAt,
    String? note,
  }) async {
    return db.into(db.transactions).insert(TransactionsCompanion.insert(
          ledgerId: ledgerId,
          type: type,
          amount: amount,
          categoryId: d.Value(categoryId),
          accountId: d.Value(accountId),
          toAccountId: d.Value(toAccountId),
          happenedAt: d.Value(happenedAt),
          note: d.Value(note),
        ));
  }

  /// 批量新增交易，单事务内插入，返回插入条数
  Future<int> insertTransactionsBatch(List<TransactionsCompanion> items) async {
    if (items.isEmpty) return 0;
    return db.transaction(() async {
      await db.batch((b) => b.insertAll(db.transactions, items));
      return items.length;
    });
  }

  // --- 去重与签名工具 ---

  /// 生成用于判重的签名（同一账本内）：
  /// type|amount|categoryId|null-safe|happenedAtEpochMs|note
  String txSignature({
    required String type,
    required double amount,
    required int? categoryId,
    required DateTime happenedAt,
    required String? note,
  }) {
    final ts = happenedAt.millisecondsSinceEpoch;
    final cat = categoryId?.toString() ?? '';
    final n = note ?? '';
    // 避免小数误差，amount 规范为最多 6 位小数
    final amt = amount.toStringAsFixed(6);
    return '$type|$amt|$cat|$ts|$n';
  }

  /// 获取某账本下所有交易的签名集合
  Future<Set<String>> signatureSetForLedger(int ledgerId) async {
    final rows = await (db.select(db.transactions)
          ..where((t) => t.ledgerId.equals(ledgerId)))
        .get();
    final set = <String>{};
    for (final t in rows) {
      set.add(txSignature(
          type: t.type,
          amount: t.amount,
          categoryId: t.categoryId,
          happenedAt: t.happenedAt,
          note: t.note));
    }
    return set;
  }

  /// 对指定账本执行去重：保留每个签名的最小 id，删除其它重复项。
  /// 返回删除的条数。
  Future<int> deduplicateLedgerTransactions(int ledgerId) async {
    final rows = await (db.select(db.transactions)
          ..where((t) => t.ledgerId.equals(ledgerId))
          ..orderBy([(t) => d.OrderingTerm(expression: t.id)]))
        .get();
    final firstIdForSig = <String, int>{};
    final toDelete = <int>[];
    for (final t in rows) {
      final sig = txSignature(
          type: t.type,
          amount: t.amount,
          categoryId: t.categoryId,
          happenedAt: t.happenedAt,
          note: t.note);
      final id = t.id;
      final existed = firstIdForSig[sig];
      if (existed == null) {
        firstIdForSig[sig] = id;
      } else {
        // 此签名已存在，视为重复，删除当前 id
        toDelete.add(id);
      }
    }
    if (toDelete.isEmpty) return 0;
    await (db.delete(db.transactions)..where((t) => t.id.isIn(toDelete))).go();
    return toDelete.length;
  }

  // Ledgers
  Stream<List<Ledger>> ledgers() => db.select(db.ledgers).watch();

  Future<int> createLedger(
      {required String name, String currency = 'CNY'}) async {
    return db.into(db.ledgers).insert(
        LedgersCompanion.insert(name: name, currency: d.Value(currency)));
  }

  Future<void> updateLedgerName({required int id, required String name}) async {
    await (db.update(db.ledgers)..where((tbl) => tbl.id.equals(id))).write(
      LedgersCompanion(name: d.Value(name)),
    );
  }

  Future<void> updateLedger(
      {required int id, String? name, String? currency}) async {
    final comp = LedgersCompanion(
      name: name != null ? d.Value(name) : const d.Value.absent(),
      currency: currency != null ? d.Value(currency) : const d.Value.absent(),
    );
    await (db.update(db.ledgers)..where((tbl) => tbl.id.equals(id)))
        .write(comp);
  }

  Future<void> deleteLedger(int id) async {
    // 先删除该账本下的所有交易，再删除账本本身
    await db.transaction(() async {
      await (db.delete(db.transactions)..where((t) => t.ledgerId.equals(id)))
          .go();
      await (db.delete(db.ledgers)..where((tbl) => tbl.id.equals(id))).go();
    });
  }

  /// 获取当前最大账本ID
  Future<int> maxLedgerId() async {
    final row = await db.customSelect(
        'SELECT IFNULL(MAX(id), 0) AS m FROM ledgers',
        readsFrom: {db.ledgers}).getSingle();
    final v = row.data['m'];
    if (v is int) return v;
    if (v is BigInt) return v.toInt();
    if (v is num) return v.toInt();
    return 0;
  }

  /// 取得下一个未占用的账本ID（通常为 max+1）
  Future<int> nextFreeLedgerId() async {
    final maxId = await maxLedgerId();
    return maxId + 1;
  }

  /// 将账本ID从 fromId 迁移到 toId（同时更新关联的 accounts/transactions）
  /// 要求 toId 在迁移前未被 ledgers 使用。
  Future<void> reassignLedgerId(
      {required int fromId, required int toId}) async {
    if (fromId == toId) return;
    final existsTo = await (db.select(db.ledgers)
          ..where((l) => l.id.equals(toId)))
        .getSingleOrNull();
    if (existsTo != null) {
      throw StateError('目标账本ID已存在: $toId');
    }
    await db.transaction(() async {
      // 先迁移子表中的外键引用
      await db.customUpdate(
        'UPDATE accounts SET ledger_id = ?1 WHERE ledger_id = ?2',
        variables: [d.Variable<int>(toId), d.Variable<int>(fromId)],
        updates: {db.accounts},
      );
      await db.customUpdate(
        'UPDATE transactions SET ledger_id = ?1 WHERE ledger_id = ?2',
        variables: [d.Variable<int>(toId), d.Variable<int>(fromId)],
        updates: {db.transactions},
      );
      // 再更新主表ID（SQLite 允许更新 INTEGER PRIMARY KEY 的值）
      await db.customUpdate(
        'UPDATE ledgers SET id = ?1 WHERE id = ?2',
        variables: [d.Variable<int>(toId), d.Variable<int>(fromId)],
        updates: {db.ledgers},
      );
    });
  }

  /// 清空指定账本的所有交易记录，返回删除的条数
  Future<int> clearLedgerTransactions(int ledgerId) async {
    final count = await (db.delete(db.transactions)
          ..where((t) => t.ledgerId.equals(ledgerId)))
        .go();
    return count;
  }

  // Monthly totals
  Future<(double income, double expense)> monthlyTotals(
      {required int ledgerId, required DateTime month}) async {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    final list = await (db.select(db.transactions)
          ..where((t) =>
              t.ledgerId.equals(ledgerId) &
              t.happenedAt.isBetweenValues(start, end)))
        .get();
    double income = 0, expense = 0;
    for (final t in list) {
      if (t.type == 'income') income += t.amount;
      if (t.type == 'expense') expense += t.amount;
    }
    return (income, expense);
  }

  Future<(double income, double expense)> yearlyTotals(
      {required int ledgerId, required int year}) async {
    final start = DateTime(year, 1, 1);
    final end = DateTime(year + 1, 1, 1);
    final list = await (db.select(db.transactions)
          ..where((t) =>
              t.ledgerId.equals(ledgerId) &
              t.happenedAt.isBetweenValues(start, end)))
        .get();
    double income = 0, expense = 0;
    for (final t in list) {
      if (t.type == 'income') income += t.amount;
      if (t.type == 'expense') expense += t.amount;
    }
    return (income, expense);
  }

  Future<int> upsertCategory(
      {required String name, required String kind}) async {
    final existing = await (db.select(db.categories)
          ..where((c) => c.name.equals(name) & c.kind.equals(kind)))
        .getSingleOrNull();
    if (existing != null) return existing.id;
    return db.into(db.categories).insert(CategoriesCompanion.insert(
        name: name, kind: kind, icon: const d.Value(null)));
  }

  // Join model for UI
  Stream<List<({Transaction t, Category? category})>>
      transactionsWithCategoryInMonth(
          {required int ledgerId, required DateTime month}) {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    final q = (db.select(db.transactions)
          ..where((t) =>
              t.ledgerId.equals(ledgerId) &
              t.happenedAt.isBetweenValues(start, end))
          ..orderBy([
            (t) => d.OrderingTerm(
                expression: t.happenedAt, mode: d.OrderingMode.desc)
          ]))
        .join([
      d.leftOuterJoin(db.categories,
          db.categories.id.equalsExp(db.transactions.categoryId)),
    ]);
    return q.watch().map((rows) => rows
        .map((r) => (
              t: r.readTable(db.transactions),
              category: r.readTableOrNull(db.categories)
            ))
        .toList());
  }

  Stream<List<({Transaction t, Category? category})>>
      transactionsWithCategoryInYear(
          {required int ledgerId, required int year}) {
    final start = DateTime(year, 1, 1);
    final end = DateTime(year + 1, 1, 1);
    final q = (db.select(db.transactions)
          ..where((t) =>
              t.ledgerId.equals(ledgerId) &
              t.happenedAt.isBetweenValues(start, end))
          ..orderBy([
            (t) => d.OrderingTerm(
                expression: t.happenedAt, mode: d.OrderingMode.desc)
          ]))
        .join([
      d.leftOuterJoin(db.categories,
          db.categories.id.equalsExp(db.transactions.categoryId)),
    ]);
    return q.watch().map((rows) => rows
        .map((r) => (
              t: r.readTable(db.transactions),
              category: r.readTableOrNull(db.categories)
            ))
        .toList());
  }

  Future<void> updateTransaction({
    required int id,
    required String type,
    required double amount,
    int? categoryId,
    String? note,
    DateTime? happenedAt,
    d.Value<int?>? accountId,
  }) async {
    await (db.update(db.transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        type: d.Value(type),
        amount: d.Value(amount),
        categoryId: d.Value(categoryId),
        note: d.Value(note),
        happenedAt:
            happenedAt != null ? d.Value(happenedAt) : const d.Value.absent(),
        accountId: accountId ?? const d.Value.absent(),
      ),
    );
  }

  /// 删除交易记录
  Future<void> deleteTransaction(int id) async {
    await (db.delete(db.transactions)..where((t) => t.id.equals(id))).go();
  }

  // All transactions joined with category, ordered by date desc
  Stream<List<({Transaction t, Category? category})>>
      transactionsWithCategoryAll({required int ledgerId}) {
    final q = (db.select(db.transactions)
          ..where((t) => t.ledgerId.equals(ledgerId))
          ..orderBy([
            (t) => d.OrderingTerm(
                expression: t.happenedAt, mode: d.OrderingMode.desc)
          ]))
        .join([
      d.leftOuterJoin(db.categories,
          db.categories.id.equalsExp(db.transactions.categoryId)),
    ]);
    return q.watch().map((rows) => rows
        .map((r) => (
              t: r.readTable(db.transactions),
              category: r.readTableOrNull(db.categories)
            ))
        .toList());
  }
  
  // Category CRUD operations
  Future<int> createCategory({
    required String name,
    required String kind,
    String? icon,
  }) async {
    return await db.into(db.categories).insert(
      CategoriesCompanion.insert(
        name: name,
        kind: kind,
        icon: d.Value(icon),
      ),
    );
  }
  
  Future<void> updateCategory(
    int id, {
    String? name,
    String? icon,
  }) async {
    await (db.update(db.categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(
        name: name != null ? d.Value(name) : const d.Value.absent(),
        icon: icon != null ? d.Value(icon) : const d.Value.absent(),
      ),
    );
  }
  
  Future<void> deleteCategory(int id) async {
    await (db.delete(db.categories)..where((c) => c.id.equals(id))).go();
  }
  
  Future<int> getTransactionCountByCategory(int categoryId) async {
    final result = await db.customSelect(
      'SELECT COUNT(*) AS count FROM transactions WHERE category_id = ?1',
      variables: [d.Variable.withInt(categoryId)],
      readsFrom: {db.transactions},
    ).getSingle();

    final count = result.data['count'];
    if (count is int) return count;
    if (count is BigInt) return count.toInt();
    if (count is num) return count.toInt();
    return 0;
  }

  /// 批量获取所有分类的交易数量（性能优化版本）
  Future<Map<int, int>> getAllCategoryTransactionCounts() async {
    final result = await db.customSelect(
      '''
      SELECT
        c.id as category_id,
        COALESCE(COUNT(t.id), 0) as transaction_count
      FROM categories c
      LEFT JOIN transactions t ON c.id = t.category_id
      GROUP BY c.id
      ''',
      readsFrom: {db.categories, db.transactions},
    ).get();

    final Map<int, int> counts = {};
    for (final row in result) {
      final categoryId = row.data['category_id'];
      final count = row.data['transaction_count'];

      if (categoryId is int) {
        int countInt = 0;
        if (count is int) {
          countInt = count;
        } else if (count is BigInt) {
          countInt = count.toInt();
        } else if (count is num) {
          countInt = count.toInt();
        }

        counts[categoryId] = countInt;
      }
    }

    return counts;
  }
  
  // 分类迁移：将fromCategoryId的所有交易迁移到toCategoryId
  Future<int> migrateCategory({
    required int fromCategoryId,
    required int toCategoryId,
  }) async {
    // 获取迁移前的数量
    final beforeCount = await getTransactionCountByCategory(fromCategoryId);
    
    // 执行迁移
    await (db.update(db.transactions)
      ..where((t) => t.categoryId.equals(fromCategoryId))).write(
      TransactionsCompanion(
        categoryId: d.Value(toCategoryId),
      ),
    );
    
    // 返回迁移的交易数量
    return beforeCount;
  }
  
  // 获取分类迁移信息（检查是否可以迁移）
  Future<({int transactionCount, bool canMigrate})> getCategoryMigrationInfo({
    required int fromCategoryId,
    required int toCategoryId,
  }) async {
    // 检查源分类的交易数量
    final transactionCount = await getTransactionCountByCategory(fromCategoryId);
    
    // 检查目标分类是否存在
    final targetCategory = await (db.select(db.categories)
      ..where((c) => c.id.equals(toCategoryId))).getSingleOrNull();
    
    final canMigrate = transactionCount > 0 && targetCategory != null && fromCategoryId != toCategoryId;
    
    return (transactionCount: transactionCount, canMigrate: canMigrate);
  }
  
  // 获取分类汇总信息
  Future<({int totalCount, double totalAmount, double averageAmount})> getCategorySummary(int categoryId) async {
    final result = await db.customSelect(
      '''
      SELECT 
        COUNT(*) as count,
        SUM(amount) as total,
        AVG(amount) as average
      FROM transactions 
      WHERE category_id = ?1
      ''',
      variables: [d.Variable.withInt(categoryId)],
      readsFrom: {db.transactions},
    ).getSingle();
    
    int parseCount(dynamic v) {
      if (v is int) return v;
      if (v is BigInt) return v.toInt();
      if (v is num) return v.toInt();
      return 0;
    }
    
    double parseAmount(dynamic v) {
      if (v == null) return 0.0;
      if (v is double) return v;
      if (v is int) return v.toDouble();
      if (v is BigInt) return v.toDouble();
      if (v is num) return v.toDouble();
      return 0.0;
    }
    
    final count = parseCount(result.data['count']);
    final total = parseAmount(result.data['total']);
    final average = parseAmount(result.data['average']);
    
    return (
      totalCount: count,
      totalAmount: total,
      averageAmount: average,
    );
  }
  
  // 获取分类下的所有交易记录（按时间倒序）
  Future<List<Transaction>> getTransactionsByCategory(int categoryId) async {
    return await (db.select(db.transactions)
      ..where((t) => t.categoryId.equals(categoryId))
      ..orderBy([
        (t) => d.OrderingTerm(
          expression: t.happenedAt,
          mode: d.OrderingMode.desc,
        )
      ])).get();
  }

  // 获取分类下的所有交易记录（支持自定义排序）
  Future<List<Transaction>> getTransactionsByCategoryWithSort(
    int categoryId, {
    String sortBy = 'time', // 'time' or 'amount'
    bool ascending = false,
  }) async {
    final query = db.select(db.transactions)..where((t) => t.categoryId.equals(categoryId));

    if (sortBy == 'amount') {
      query.orderBy([
        (t) => d.OrderingTerm(
          expression: t.amount,
          mode: ascending ? d.OrderingMode.asc : d.OrderingMode.desc,
        )
      ]);
    } else {
      query.orderBy([
        (t) => d.OrderingTerm(
          expression: t.happenedAt,
          mode: ascending ? d.OrderingMode.asc : d.OrderingMode.desc,
        )
      ]);
    }

    return await query.get();
  }

  /// 响应式监听分类下的交易变化
  Stream<List<Transaction>> watchTransactionsByCategory(int categoryId, {int? ledgerId}) {
    final query = db.select(db.transactions)
      ..where((t) => t.categoryId.equals(categoryId));

    // 如果指定了账本ID，则只返回该账本的交易
    if (ledgerId != null) {
      query.where((t) => t.ledgerId.equals(ledgerId));
    }

    query.orderBy([
      (t) => d.OrderingTerm(
        expression: t.happenedAt,
        mode: d.OrderingMode.desc,
      )
    ]);

    return query.watch();
  }

  /// 响应式监听分类信息变化
  Stream<Category?> watchCategory(int categoryId) {
    return (db.select(db.categories)
      ..where((c) => c.id.equals(categoryId))
    ).watchSingleOrNull();
  }

  /// 响应式监听所有分类及其交易数量变化
  Stream<List<({Category category, int transactionCount})>> watchCategoriesWithCount() {
    // 使用自定义查询监听分类和交易数量的变化
    return db.customSelect(
      '''
      SELECT
        c.id as category_id,
        c.name as category_name,
        c.kind as category_kind,
        c.icon as category_icon,
        c.sort_order as category_sort_order,
        c.parent_id as category_parent_id,
        c.level as category_level,
        COALESCE(COUNT(DISTINCT t.id), 0) as transaction_count
      FROM categories c
      LEFT JOIN transactions t ON (
        t.category_id = c.id
        OR t.category_id IN (
          SELECT id FROM categories WHERE parent_id = c.id
        )
      )
      GROUP BY c.id, c.name, c.kind, c.icon, c.sort_order, c.parent_id, c.level
      ORDER BY c.sort_order
      ''',
      readsFrom: {db.categories, db.transactions},
    ).watch().map((rows) {
      return rows.map((row) {
        final category = Category(
          id: row.read<int>('category_id'),
          name: row.read<String>('category_name'),
          kind: row.read<String>('category_kind'),
          icon: row.read<String?>('category_icon'),
          sortOrder: row.read<int>('category_sort_order'),
          parentId: row.read<int?>('category_parent_id'),
          level: row.read<int>('category_level'),
        );
        final transactionCount = row.read<int>('transaction_count');
        return (category: category, transactionCount: transactionCount);
      }).toList();
    });
  }

  // ========== Account Management ==========

  /// 获取指定账本下的所有账户
  Stream<List<Account>> accountsForLedger(int ledgerId) {
    return (db.select(db.accounts)
          ..where((a) => a.ledgerId.equals(ledgerId)))
        .watch();
  }

  /// 创建账户
  Future<int> createAccount({
    required int ledgerId,
    required String name,
    String type = 'cash',
    String currency = 'CNY',
    double initialBalance = 0.0,
  }) async {
    logger.info('AccountCreate', '📝 开始创建账户: name=$name, ledgerId=$ledgerId, type=$type, currency=$currency, initialBalance=$initialBalance');

    try {
      final companion = AccountsCompanion.insert(
        ledgerId: ledgerId,
        name: name,
        type: d.Value(type),
        currency: d.Value(currency),
        initialBalance: d.Value(initialBalance),
        createdAt: d.Value(DateTime.now()),  // v1.15.0: 显式设置创建时间
      );

      logger.info('AccountCreate', '📦 Companion 创建成功，准备插入数据库');

      final id = await db.into(db.accounts).insert(companion);

      logger.info('AccountCreate', '✅ 账户创建成功！ID=$id');
      return id;
    } catch (e, stack) {
      logger.error('AccountCreate', '❌ 创建账户失败', e, stack);
      rethrow;
    }
  }

  /// 更新账户
  Future<void> updateAccount(
    int id, {
    String? name,
    String? type,
    String? currency,
    double? initialBalance,
  }) async {
    await (db.update(db.accounts)..where((a) => a.id.equals(id))).write(
      AccountsCompanion(
        name: name != null ? d.Value(name) : const d.Value.absent(),
        type: type != null ? d.Value(type) : const d.Value.absent(),
        currency: currency != null ? d.Value(currency) : const d.Value.absent(),
        initialBalance: initialBalance != null ? d.Value(initialBalance) : const d.Value.absent(),
      ),
    );
  }

  /// 删除账户
  Future<void> deleteAccount(int id) async {
    await (db.delete(db.accounts)..where((a) => a.id.equals(id))).go();
  }

  /// 获取账户余额（收入 - 支出 + 转入 - 转出）
  Future<double> getAccountBalance(int accountId) async {
    // 获取账户初始资金
    final account = await (db.select(db.accounts)
          ..where((a) => a.id.equals(accountId)))
        .getSingleOrNull();

    double balance = account?.initialBalance ?? 0.0;

    // 收入和支出
    final normalTxs = await (db.select(db.transactions)
          ..where((t) => t.accountId.equals(accountId)))
        .get();

    for (final t in normalTxs) {
      if (t.type == 'income') {
        balance += t.amount;
      } else if (t.type == 'expense') {
        balance -= t.amount;
      } else if (t.type == 'transfer') {
        // 作为转出账户
        balance -= t.amount;
      }
    }

    // 作为转入账户的转账
    final transfersIn = await (db.select(db.transactions)
          ..where((t) => t.toAccountId.equals(accountId) & t.type.equals('transfer')))
        .get();

    for (final t in transfersIn) {
      balance += t.amount;
    }

    return balance;
  }

  /// 批量获取所有账户余额
  Future<Map<int, double>> getAllAccountBalances(int ledgerId) async {
    final accounts = await (db.select(db.accounts)
          ..where((a) => a.ledgerId.equals(ledgerId)))
        .get();

    final Map<int, double> balances = {};
    for (final account in accounts) {
      balances[account.id] = await getAccountBalance(account.id);
    }

    return balances;
  }

  /// 获取账户的交易数量
  Future<int> getTransactionCountByAccount(int accountId) async {
    // 统计作为主账户的交易数
    final mainCount = await db.customSelect(
      'SELECT COUNT(*) AS count FROM transactions WHERE account_id = ?1',
      variables: [d.Variable.withInt(accountId)],
      readsFrom: {db.transactions},
    ).getSingle();

    // 统计作为转入账户的交易数
    final toCount = await db.customSelect(
      'SELECT COUNT(*) AS count FROM transactions WHERE to_account_id = ?1',
      variables: [d.Variable.withInt(accountId)],
      readsFrom: {db.transactions},
    ).getSingle();

    int parseCount(dynamic v) {
      if (v is int) return v;
      if (v is BigInt) return v.toInt();
      if (v is num) return v.toInt();
      return 0;
    }

    return parseCount(mainCount.data['count']) + parseCount(toCount.data['count']);
  }

  /// 账户迁移：将fromAccountId的所有交易迁移到toAccountId
  Future<int> migrateAccount({
    required int fromAccountId,
    required int toAccountId,
  }) async {
    final beforeCount = await getTransactionCountByAccount(fromAccountId);

    // 迁移作为主账户的交易
    await (db.update(db.transactions)
          ..where((t) => t.accountId.equals(fromAccountId)))
        .write(TransactionsCompanion(accountId: d.Value(toAccountId)));

    // 迁移作为转入账户的交易
    await (db.update(db.transactions)
          ..where((t) => t.toAccountId.equals(fromAccountId)))
        .write(TransactionsCompanion(toAccountId: d.Value(toAccountId)));

    return beforeCount;
  }

  /// 获取单个账户信息
  Future<Account?> getAccount(int accountId) async {
    return await (db.select(db.accounts)
          ..where((a) => a.id.equals(accountId)))
        .getSingleOrNull();
  }

  /// 响应式监听账户信息变化
  Stream<Account?> watchAccount(int accountId) {
    return (db.select(db.accounts)..where((a) => a.id.equals(accountId)))
        .watchSingleOrNull();
  }

  /// 获取单个账户的消费金额（支出总额，包括转账转出）
  Future<double> getAccountExpense(int accountId) async {
    double expense = 0.0;

    // 获取作为主账户的支出和转出
    final normalTxs = await (db.select(db.transactions)
          ..where((t) => t.accountId.equals(accountId)))
        .get();

    for (final t in normalTxs) {
      if (t.type == 'expense') {
        expense += t.amount;
      } else if (t.type == 'transfer') {
        // 作为转出账户
        expense += t.amount;
      }
    }

    return expense;
  }

  /// 获取单个账户的收入金额（收入总额，包括转账转入）
  Future<double> getAccountIncome(int accountId) async {
    double income = 0.0;

    // 获取作为主账户的收入
    final normalTxs = await (db.select(db.transactions)
          ..where((t) => t.accountId.equals(accountId)))
        .get();

    for (final t in normalTxs) {
      if (t.type == 'income') {
        income += t.amount;
      }
    }

    // 作为转入账户的转账
    final transfersIn = await (db.select(db.transactions)
          ..where((t) => t.toAccountId.equals(accountId) & t.type.equals('transfer')))
        .get();

    for (final t in transfersIn) {
      income += t.amount;
    }

    return income;
  }

  /// 获取单个账户的统计信息（余额、消费金额、收入金额）
  Future<({double balance, double expense, double income})> getAccountStats(int accountId) async {
    final balance = await getAccountBalance(accountId);
    final expense = await getAccountExpense(accountId);
    final income = await getAccountIncome(accountId);
    return (balance: balance, expense: expense, income: income);
  }

  /// 批量获取所有账户的统计信息
  /// v1.15.0: 不再限制账本，获取所有账户
  Future<Map<int, ({double balance, double expense, double income})>> getAllAccountStats() async {
    final accounts = await db.select(db.accounts).get();

    final Map<int, ({double balance, double expense, double income})> stats = {};
    for (final account in accounts) {
      stats[account.id] = await getAccountStats(account.id);
    }

    return stats;
  }

  /// 获取所有账户的汇总统计（总余额、总支出、总收入）
  /// v1.15.0: 不再限制账本，获取所有账户
  /// 注意：总收入/支出不包含转账（转账是内部资金流转，不是真实收支）
  Future<({double totalBalance, double totalExpense, double totalIncome})> getAllAccountsTotalStats() async {
    final accounts = await db.select(db.accounts).get();

    // 总余额 = 所有账户余额之和（这个是正确的，转账不影响总余额）
    double totalBalance = 0.0;
    for (final account in accounts) {
      final balance = await getAccountBalance(account.id);
      totalBalance += balance;
    }

    // 总收入/支出：直接从交易表查询，排除转账类型
    // 只统计有账户关联的交易（账户功能范围内）
    final accountIds = accounts.map((a) => a.id).toSet();

    final allTxs = await (db.select(db.transactions)
          ..where((t) => t.accountId.isNotNull()))
        .get();

    double totalIncome = 0.0;
    double totalExpense = 0.0;

    for (final t in allTxs) {
      // 只统计属于已有账户的交易
      if (t.accountId != null && accountIds.contains(t.accountId)) {
        if (t.type == 'income') {
          totalIncome += t.amount;
        } else if (t.type == 'expense') {
          totalExpense += t.amount;
        }
        // 转账类型不计入总收入/支出
      }
    }

    return (totalBalance: totalBalance, totalExpense: totalExpense, totalIncome: totalIncome);
  }

  /// 获取账户相关的所有交易（包括作为主账户和作为转入账户的交易）
  Stream<List<Transaction>> watchAccountTransactions(int accountId) {
    // 注意：这里只获取作为主账户的交易
    // 转入交易通过 toAccountId 关联，需要在UI层额外处理
    return (db.select(db.transactions)
          ..where((t) => t.accountId.equals(accountId) | t.toAccountId.equals(accountId))
          ..orderBy([
            (t) => d.OrderingTerm(
                expression: t.happenedAt, mode: d.OrderingMode.desc)
          ]))
        .watch();
  }

  /// 获取指定账本的所有账户初始资金总额
  Future<double> getTotalInitialBalance(int ledgerId) async {
    final accounts = await (db.select(db.accounts)
          ..where((a) => a.ledgerId.equals(ledgerId)))
        .get();

    double total = 0.0;
    for (final account in accounts) {
      total += account.initialBalance;
    }
    return total;
  }

  // ============================================
  // v1.15.0 账户独立相关方法
  // ============================================

  /// 获取所有账户（不限账本）
  Future<List<Account>> getAllAccounts() async {
    return await db.select(db.accounts).get();
  }

  /// 监听所有账户（不限账本）- Stream 版本
  Stream<List<Account>> watchAllAccounts() {
    return db.select(db.accounts).watch();
  }

  /// 获取账本可用的账户（通过币种过滤）
  ///
  /// v1.15.0: 账户独立后，根据账本币种自动过滤可用账户
  Future<List<Account>> getAvailableAccountsForLedger(int ledgerId) async {
    // 获取账本信息
    final ledger = await (db.select(db.ledgers)
          ..where((l) => l.id.equals(ledgerId)))
        .getSingle();

    // 通过币种过滤账户
    return await (db.select(db.accounts)
          ..where((a) => a.currency.equals(ledger.currency)))
        .get();
  }

  /// 获取某币种的所有账户
  Future<List<Account>> getAccountsByCurrency(String currency) async {
    return await (db.select(db.accounts)
          ..where((a) => a.currency.equals(currency)))
        .get();
  }

  /// 检查账户是否有交易记录
  ///
  /// 用于判断账户币种是否可以修改
  Future<bool> hasTransactions(int accountId) async {
    final count = await db.customSelect(
      'SELECT COUNT(*) as count FROM transactions WHERE account_id = ? OR to_account_id = ?',
      variables: [d.Variable.withInt(accountId), d.Variable.withInt(accountId)],
      readsFrom: {db.transactions},
    ).getSingle();

    final c = count.data['count'];
    if (c is int) return c > 0;
    if (c is BigInt) return c > BigInt.zero;
    if (c is num) return c > 0;
    return false;
  }

  /// 获取账户全局余额（跨所有账本）
  ///
  /// v1.15.0: 账户独立后，可以查看账户在所有账本中的总余额
  Future<double> getAccountGlobalBalance(int accountId) async {
    final account = await (db.select(db.accounts)
          ..where((a) => a.id.equals(accountId)))
        .getSingle();

    // 获取所有交易
    final transactions = await (db.select(db.transactions)
          ..where((t) => t.accountId.equals(accountId) | t.toAccountId.equals(accountId)))
        .get();

    double balance = account.initialBalance;

    for (final tx in transactions) {
      if (tx.accountId == accountId) {
        // 作为主账户
        if (tx.type == 'income') {
          balance += tx.amount;
        } else if (tx.type == 'expense') {
          balance -= tx.amount;
        } else if (tx.type == 'transfer') {
          balance -= tx.amount;
        }
      } else if (tx.toAccountId == accountId) {
        // 作为转入账户（转账）
        balance += tx.amount;
      }
    }

    return balance;
  }

  /// 获取账户在某账本的余额
  ///
  /// v1.15.0: 查看账户在特定账本中的余额（不包含初始余额）
  Future<double> getAccountBalanceInLedger(int accountId, int ledgerId) async {
    final transactions = await (db.select(db.transactions)
          ..where((t) =>
              (t.accountId.equals(accountId) | t.toAccountId.equals(accountId)) &
              t.ledgerId.equals(ledgerId)))
        .get();

    double balance = 0.0;

    for (final tx in transactions) {
      if (tx.accountId == accountId) {
        // 作为主账户
        if (tx.type == 'income') {
          balance += tx.amount;
        } else if (tx.type == 'expense') {
          balance -= tx.amount;
        } else if (tx.type == 'transfer') {
          balance -= tx.amount;
        }
      } else if (tx.toAccountId == accountId) {
        // 作为转入账户（转账）
        balance += tx.amount;
      }
    }

    return balance;
  }

  /// 按币种分组获取账户统计
  ///
  /// 返回：Map<币种, 账户列表>
  Future<Map<String, List<Account>>> getAccountsGroupedByCurrency() async {
    final allAccounts = await getAllAccounts();
    final Map<String, List<Account>> grouped = {};

    for (final account in allAccounts) {
      grouped.putIfAbsent(account.currency, () => []).add(account);
    }

    return grouped;
  }

  /// 获取账户在多个账本中的使用情况
  ///
  /// 返回：Map<账本ID, 交易数量>
  Future<Map<int, int>> getAccountUsageInLedgers(int accountId) async {
    final result = await db.customSelect(
      '''
      SELECT ledger_id, COUNT(*) as count
      FROM transactions
      WHERE account_id = ? OR to_account_id = ?
      GROUP BY ledger_id
      ''',
      variables: [d.Variable.withInt(accountId), d.Variable.withInt(accountId)],
      readsFrom: {db.transactions},
    ).get();

    final Map<int, int> usage = {};
    for (final row in result) {
      final ledgerId = row.data['ledger_id'] as int;
      final count = row.data['count'];

      int countInt = 0;
      if (count is int) {
        countInt = count;
      } else if (count is BigInt) {
        countInt = count.toInt();
      } else if (count is num) {
        countInt = count.toInt();
      }

      usage[ledgerId] = countInt;
    }

    return usage;
  }

  // ============================================
  // 二级分类相关方法
  // ============================================

  /// 获取所有一级分类（level=1, parentId=null）
  Future<List<Category>> getTopLevelCategories(String kind) async {
    return await (db.select(db.categories)
          ..where((c) => c.kind.equals(kind) & c.level.equals(1) & c.parentId.isNull())
          ..orderBy([(c) => d.OrderingTerm(expression: c.sortOrder)]))
        .get();
  }

  /// 获取可用于记账的分类（叶子分类）
  ///
  /// 可用分类 = 没有子分类的分类
  /// 用于 AI 记账时匹配和提示词生成
  Future<List<Category>> getUsableCategories(String kind) async {
    final allCategories = await (db.select(db.categories)
          ..where((c) => c.kind.equals(kind))
          ..orderBy([(c) => d.OrderingTerm(expression: c.sortOrder)]))
        .get();
    return CategoryHierarchy.getUsableCategories(allCategories);
  }

  /// 获取指定一级分类下的所有二级分类
  Future<List<Category>> getSubCategories(int parentId) async {
    return await (db.select(db.categories)
          ..where((c) => c.parentId.equals(parentId) & c.level.equals(2))
          ..orderBy([(c) => d.OrderingTerm(expression: c.sortOrder)]))
        .get();
  }

  /// 根据ID获取分类
  Future<Category?> getCategoryById(int categoryId) async {
    return await (db.select(db.categories)
          ..where((c) => c.id.equals(categoryId)))
        .getSingleOrNull();
  }

  /// 创建二级分类
  Future<int> createSubCategory({
    required int parentId,
    required String name,
    required String kind,
    String? icon,
    int? sortOrder,
  }) async {
    return await db.into(db.categories).insert(
      CategoriesCompanion.insert(
        name: name,
        kind: kind,
        icon: d.Value(icon),
        parentId: d.Value(parentId),
        level: d.Value(2),
        sortOrder: d.Value(sortOrder ?? 0),
      ),
    );
  }

  /// 检查分类是否有子分类
  Future<bool> hasSubCategories(int categoryId) async {
    final count = await db.customSelect(
      'SELECT COUNT(*) as count FROM categories WHERE parent_id = ?',
      variables: [d.Variable.withInt(categoryId)],
      readsFrom: {db.categories},
    ).getSingle();

    final c = count.data['count'];
    if (c is int) return c > 0;
    if (c is BigInt) return c > BigInt.zero;
    if (c is num) return c > 0;
    return false;
  }

  /// 获取分类的子分类数量
  Future<int> getSubCategoryCount(int categoryId) async {
    final result = await db.customSelect(
      'SELECT COUNT(*) as count FROM categories WHERE parent_id = ?',
      variables: [d.Variable.withInt(categoryId)],
      readsFrom: {db.categories},
    ).getSingle();

    final count = result.data['count'];
    if (count is int) return count;
    if (count is BigInt) return count.toInt();
    if (count is num) return count.toInt();
    return 0;
  }

  /// 迁移分类下的所有交易和子分类
  /// 返回: (迁移的交易数, 迁移的子分类数)
  Future<({int migratedTransactions, int migratedSubCategories})> migrateCategoryTransactions({
    required int fromCategoryId,
    required int toCategoryId,
  }) async {
    return await db.transaction(() async {
      final fromCategory = await (db.select(db.categories)
            ..where((c) => c.id.equals(fromCategoryId)))
          .getSingle();

      int migratedTransactions = 0;
      int migratedSubCategories = 0;

      if (fromCategory.level == 1) {
        // 一级分类：处理子分类
        final subCategories = await getSubCategories(fromCategoryId);

        if (subCategories.isNotEmpty) {
          for (final sub in subCategories) {
            // 检查目标分类是否已有同名子分类
            final existingSub = await (db.select(db.categories)
                  ..where((c) =>
                      c.parentId.equals(toCategoryId) &
                      c.name.equals(sub.name) &
                      c.kind.equals(sub.kind)))
                .getSingleOrNull();

            if (existingSub != null) {
              // 合并到已有的同名子分类
              final count = await (db.update(db.transactions)
                    ..where((t) => t.categoryId.equals(sub.id)))
                  .write(TransactionsCompanion(
                categoryId: d.Value(existingSub.id),
              ));
              migratedTransactions += count;

              // 删除源子分类
              await (db.delete(db.categories)..where((c) => c.id.equals(sub.id))).go();
            } else {
              // 将子分类移动到新的父分类下
              await (db.update(db.categories)..where((c) => c.id.equals(sub.id)))
                  .write(CategoriesCompanion(
                parentId: d.Value(toCategoryId),
              ));
              migratedSubCategories++;
            }
          }
        }

        // 迁移一级分类自身的交易
        final directCount = await (db.update(db.transactions)
              ..where((t) => t.categoryId.equals(fromCategoryId)))
            .write(TransactionsCompanion(
          categoryId: d.Value(toCategoryId),
        ));
        migratedTransactions += directCount;
      } else {
        // 二级分类：直接迁移交易
        final count = await (db.update(db.transactions)
              ..where((t) => t.categoryId.equals(fromCategoryId)))
            .write(TransactionsCompanion(
          categoryId: d.Value(toCategoryId),
        ));
        migratedTransactions = count;
      }

      return (
        migratedTransactions: migratedTransactions,
        migratedSubCategories: migratedSubCategories,
      );
    });
  }

  /// 批量更新分类排序
  Future<void> updateCategorySortOrders(List<({int id, int sortOrder})> updates) async {
    await db.transaction(() async {
      for (final update in updates) {
        await (db.update(db.categories)..where((c) => c.id.equals(update.id)))
            .write(CategoriesCompanion(sortOrder: d.Value(update.sortOrder)));
      }
    });
  }

  /// 监听分类及其子分类的变化
  Stream<List<Category>> watchCategoryWithSubs(int categoryId) {
    return db.customSelect(
      '''
      SELECT * FROM categories
      WHERE id = ? OR parent_id = ?
      ORDER BY level, sort_order
      ''',
      variables: [d.Variable.withInt(categoryId), d.Variable.withInt(categoryId)],
      readsFrom: {db.categories},
    ).watch().map((rows) {
      return rows.map((row) {
        return Category(
          id: row.read<int>('id'),
          name: row.read<String>('name'),
          kind: row.read<String>('kind'),
          icon: row.read<String?>('icon'),
          sortOrder: row.read<int>('sort_order'),
          parentId: row.read<int?>('parent_id'),
          level: row.read<int>('level'),
        );
      }).toList();
    });
  }

  /// 获取分类的完整路径名称（一级/二级）
  Future<String> getCategoryFullName(int categoryId) async {
    final category = await (db.select(db.categories)
          ..where((c) => c.id.equals(categoryId)))
        .getSingle();

    if (category.level == 1 || category.parentId == null) {
      return category.name;
    }

    final parent = await (db.select(db.categories)
          ..where((c) => c.id.equals(category.parentId!)))
        .getSingle();

    return '${parent.name} / ${category.name}';
  }

  /// 按分类统计（支持二级分类展开）
  /// 返回: List<(分类ID, 分类名称, 图标, 父分类ID, 层级, 总额)>
  Future<List<({int? id, String name, String? icon, int? parentId, int level, double total})>> totalsByCategoryWithHierarchy({
    required int ledgerId,
    required String type,
    required DateTime start,
    required DateTime end,
  }) async {
    final q = (db.select(db.transactions)
          ..where((t) =>
              t.ledgerId.equals(ledgerId) &
              t.type.equals(type) &
              t.happenedAt.isBetweenValues(start, end)))
        .join([
      d.leftOuterJoin(db.categories,
          db.categories.id.equalsExp(db.transactions.categoryId)),
    ]);

    final rows = await q.get();
    final map = <int?, double>{}; // categoryId -> total
    final categoryInfo = <int?, ({String name, String? icon, int? parentId, int level})>{};

    for (final r in rows) {
      final t = r.readTable(db.transactions);
      final c = r.readTableOrNull(db.categories);
      final id = c?.id;

      if (c != null) {
        categoryInfo[id] = (
          name: c.name,
          icon: c.icon,
          parentId: c.parentId,
          level: c.level,
        );
      } else {
        categoryInfo[id] = (
          name: '未分类',
          icon: null,
          parentId: null,
          level: 1,
        );
      }

      map.update(id, (v) => v + t.amount, ifAbsent: () => t.amount);
    }

    final list = map.entries.map((e) {
      final info = categoryInfo[e.key]!;
      return (
        id: e.key,
        name: info.name,
        icon: info.icon,
        parentId: info.parentId,
        level: info.level,
        total: e.value,
      );
    }).toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    return list;
  }
}
