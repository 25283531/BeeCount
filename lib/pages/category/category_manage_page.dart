import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import '../../providers.dart';
import '../../providers/database_providers.dart';
import '../../widgets/ui/ui.dart';
import '../../data/db.dart' as db;
import '../../services/category_service.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/category_utils.dart';
import '../../styles/tokens.dart';
import 'category_edit_page.dart';

class CategoryManagePage extends ConsumerStatefulWidget {
  final int initialTabIndex; // 0: 支出, 1: 收入

  const CategoryManagePage({
    super.key,
    this.initialTabIndex = 0,
  });

  @override
  ConsumerState<CategoryManagePage> createState() => _CategoryManagePageState();
}

class _CategoryManagePageState extends ConsumerState<CategoryManagePage> with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _tabController.addListener(() {
      setState(() {}); // 重新构建以更新按钮状态
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesWithCountAsync = ref.watch(categoriesWithCountProvider);

    return Scaffold(
      body: Column(
        children: [
          PrimaryHeader(
            title: AppLocalizations.of(context).categoryTitle,
            showBack: true,
            actions: [
              IconButton(
                onPressed: () => _addCategory(),
                icon: const Icon(Icons.add),
                tooltip: AppLocalizations.of(context).categoryNew,
              ),
            ],
          ),
          TabBar(
            controller: _tabController,
            labelColor: BeeTokens.textPrimary(context),
            unselectedLabelColor: BeeTokens.textSecondary(context),
            tabs: [
              Tab(text: AppLocalizations.of(context).categoryExpense),
              Tab(text: AppLocalizations.of(context).categoryIncome),
            ],
          ),
          Expanded(
            child: categoriesWithCountAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(child: Text(AppLocalizations.of(context).categoryLoadFailed(error.toString()))),
              data: (categoriesWithCount) {
                return Column(
                  children: [
                    // 提示信息
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      color: BeeTokens.isDark(context) ? Colors.blue[900]!.withValues(alpha: 0.3) : Colors.blue[50],
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 16, color: BeeTokens.isDark(context) ? Colors.blue[300] : Colors.blue[700]),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              AppLocalizations.of(context).categoryReorderTip,
                              style: TextStyle(
                                fontSize: 12,
                                color: BeeTokens.isDark(context) ? Colors.blue[300] : Colors.blue[700],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _CategoryGridView(
                            categoriesWithCount: categoriesWithCount,
                            kind: 'expense',
                          ),
                          _CategoryGridView(
                            categoriesWithCount: categoriesWithCount,
                            kind: 'income',
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _addCategory() async {
    final kind = _tabController.index == 0 ? 'expense' : 'income';
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CategoryEditPage(kind: kind),
      ),
    );
  }
}

class _CategoryGridView extends ConsumerStatefulWidget {
  final List<({db.Category category, int transactionCount})> categoriesWithCount;
  final String kind;

  const _CategoryGridView({
    required this.categoriesWithCount,
    required this.kind,
  });

  @override
  ConsumerState<_CategoryGridView> createState() => _CategoryGridViewState();
}

class _CategoryGridViewState extends ConsumerState<_CategoryGridView> {
  List<_CategoryItem> _flatList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(_CategoryGridView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.categoriesWithCount != oldWidget.categoriesWithCount ||
        widget.kind != oldWidget.kind) {
      _loadData();
    }
  }

  /// 加载数据：只构建一级分类列表，从已有数据判断是否有子分类
  void _loadData() {
    // 获取当前类型的一级分类
    final topLevelCategories = widget.categoriesWithCount
        .where((item) =>
            item.category.kind == widget.kind &&
            item.category.level == 1)
        .toList();

    // 按 sortOrder 排序
    topLevelCategories.sort((a, b) => a.category.sortOrder.compareTo(b.category.sortOrder));

    // 构建父分类ID集合，用于快速判断是否有子分类
    final parentIds = widget.categoriesWithCount
        .where((item) => item.category.parentId != null)
        .map((item) => item.category.parentId!)
        .toSet();

    final flatList = <_CategoryItem>[];

    for (final topItem in topLevelCategories) {
      // 直接从内存数据判断是否有子分类
      final hasSubCategories = parentIds.contains(topItem.category.id);

      flatList.add(_CategoryItem(
        category: topItem.category,
        transactionCount: topItem.transactionCount,
        isDefault: false,
        isSubCategory: false,
        hasSubCategories: hasSubCategories,
      ));
    }

    setState(() {
      _flatList = flatList;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 数据还未加载完成
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // 过滤出一级分类
    final topLevelCategories = _flatList
        .where((item) => !item.isSubCategory && !item.isActionButtons)
        .toList();

    if (topLevelCategories.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.category_outlined,
              size: 64,
              color: BeeTokens.textTertiary(context),
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).categoryEmpty,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: BeeTokens.textSecondary(context),
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ReorderableGridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1,
          ),
          itemCount: topLevelCategories.length,
          onReorder: (oldIndex, newIndex) {
            _onReorderTopLevel(oldIndex, newIndex, topLevelCategories);
          },
          itemBuilder: (context, index) {
            final item = topLevelCategories[index];
            return _CategoryCard(
              key: ValueKey(item.category.id),
              item: item,
              onTap: () => _onCategoryTap(item),
            );
          },
        ),
      ],
    );
  }

  Future<void> _onReorderTopLevel(int oldIndex, int newIndex, List<_CategoryItem> topLevelCategories) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }

    // 1. 立即更新本地状态（乐观更新），避免UI闪回
    final reorderedItems = List<_CategoryItem>.from(topLevelCategories);
    final movedItem = reorderedItems.removeAt(oldIndex);
    reorderedItems.insert(newIndex, movedItem);

    // 重建 _flatList，保持一级分类的新顺序
    setState(() {
      _flatList = reorderedItems;
    });

    // 2. 批量保存到数据库
    final database = ref.read(databaseProvider);
    await database.batch((batch) {
      for (var i = 0; i < reorderedItems.length; i++) {
        final category = reorderedItems[i].category;
        batch.update(
          database.categories,
          db.CategoriesCompanion(sortOrder: drift.Value(i)),
          where: (c) => c.id.equals(category.id),
        );
      }
    });

    // 3. 刷新 provider 以同步其他地方的数据
    ref.invalidate(categoriesWithCountProvider);
  }


  void _onCategoryTap(_CategoryItem item) async {
    if (item.isSubCategory) {
      await _onEditCategory(item.category);
    } else {
      if (item.hasSubCategories) {
        // 有子分类：弹出对话框
        await _showSubcategoryDialog(item.category);
      } else {
        // 无子分类：直接编辑
        await _onEditCategory(item.category);
      }
    }
  }

  /// 显示子分类对话框
  Future<void> _showSubcategoryDialog(db.Category parentCategory) async {
    await showDialog(
      context: context,
      builder: (dialogContext) => _SubcategoryDialog(
        parentCategory: parentCategory,
        categoriesWithCount: widget.categoriesWithCount,
        onSubCategoryTap: (cat) {
          Navigator.pop(dialogContext);
          _onEditCategory(cat);
        },
        onAddSubCategory: () {
          Navigator.pop(dialogContext);
          _onAddSubCategory(parentCategory);
        },
        onEditParentCategory: () {
          Navigator.pop(dialogContext);
          _onEditCategory(parentCategory);
        },
      ),
    );
  }

  Future<void> _onEditCategory(db.Category category) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CategoryEditPage(
          category: category,
          kind: category.kind,
        ),
      ),
    );
  }

  Future<void> _onAddSubCategory(db.Category parent) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CategoryEditPage(
          kind: parent.kind,
          parentCategory: parent,
        ),
      ),
    );
    _loadData();
  }
}

class _CategoryItem {
  final db.Category category;
  final int transactionCount;
  final bool isDefault;
  final bool isSubCategory;
  final db.Category? parent;
  final bool hasSubCategories;
  final bool isActionButtons; // 是否为操作按钮项

  _CategoryItem({
    required this.category,
    required this.transactionCount,
    required this.isDefault,
    required this.isSubCategory,
    this.parent,
    this.hasSubCategories = false,
    this.isActionButtons = false,
  });
}

class _CategoryCard extends ConsumerWidget {
  final _CategoryItem item;
  final VoidCallback onTap;

  const _CategoryCard({
    super.key,
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 二级分类：使用浅色背景
    final backgroundColor = item.isSubCategory
        ? Colors.orange[50]
        : Theme.of(context).colorScheme.surface;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: item.isSubCategory
                ? Colors.orange.withValues(alpha: 0.3)
                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: item.isSubCategory ? 28 : 32,
                    height: item.isSubCategory ? 28 : 32,
                    decoration: BoxDecoration(
                      color: item.isSubCategory
                          ? Colors.orange.withValues(alpha: 0.2)
                          : Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      CategoryService.getCategoryIcon(item.category.icon),
                      color: item.isSubCategory
                          ? Colors.orange[700]
                          : Theme.of(context).colorScheme.primary,
                      size: item.isSubCategory ? 16 : 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      CategoryUtils.getDisplayName(item.category.name, context),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontSize: item.isSubCategory ? 10 : 12,
                            color: item.isSubCategory ? Colors.orange[900] : null,
                          ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppLocalizations.of(context).categoryMigrationTransactionLabel(item.transactionCount),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: item.isSubCategory
                              ? Colors.orange[700]
                              : Theme.of(context).colorScheme.outline,
                          fontSize: item.isSubCategory ? 9 : 10,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            // 有子分类的一级分类：右下角显示指示器
            if (!item.isSubCategory && item.hasSubCategories)
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.more_horiz,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 子分类对话框
class _SubcategoryDialog extends ConsumerStatefulWidget {
  final db.Category parentCategory;
  final List<({db.Category category, int transactionCount})> categoriesWithCount;
  final Function(db.Category) onSubCategoryTap;
  final VoidCallback onAddSubCategory;
  final VoidCallback onEditParentCategory;

  const _SubcategoryDialog({
    required this.parentCategory,
    required this.categoriesWithCount,
    required this.onSubCategoryTap,
    required this.onAddSubCategory,
    required this.onEditParentCategory,
  });

  @override
  ConsumerState<_SubcategoryDialog> createState() => _SubcategoryDialogState();
}

class _SubcategoryDialogState extends ConsumerState<_SubcategoryDialog> {
  List<({db.Category category, int transactionCount})>? _subCategories;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSubCategories();
  }

  Future<void> _loadSubCategories() async {
    final repo = ref.read(repositoryProvider);
    final subCategories = await repo.getSubCategories(widget.parentCategory.id);

    final result = <({db.Category category, int transactionCount})>[];
    for (final subCat in subCategories) {
      final subCount = widget.categoriesWithCount
          .firstWhere(
            (item) => item.category.id == subCat.id,
            orElse: () => (category: subCat, transactionCount: 0),
          )
          .transactionCount;
      result.add((category: subCat, transactionCount: subCount));
    }

    if (mounted) {
      setState(() {
        _subCategories = result;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final l10n = AppLocalizations.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.85,
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题栏
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    CategoryService.getCategoryIcon(widget.parentCategory.icon),
                    color: primaryColor,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    CategoryUtils.getDisplayName(widget.parentCategory.name, context),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 内容区域
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1,
                ),
                itemCount: (_subCategories?.length ?? 0) + 2, // 子分类 + 添加 + 编辑
                itemBuilder: (context, index) {
                  final subCategories = _subCategories ?? [];
                  // 添加按钮
                  if (index == subCategories.length) {
                    return _DialogActionButton(
                      onTap: widget.onAddSubCategory,
                      icon: Icons.add,
                      label: l10n.commonAdd,
                    );
                  }
                  // 编辑按钮
                  if (index == subCategories.length + 1) {
                    return _DialogActionButton(
                      onTap: widget.onEditParentCategory,
                      icon: Icons.edit_outlined,
                      label: l10n.commonEdit,
                    );
                  }
                  // 子分类
                  final item = subCategories[index];
                  return _DialogSubCategoryCard(
                    category: item.category,
                    transactionCount: item.transactionCount,
                    onTap: () => widget.onSubCategoryTap(item.category),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// 对话框中的操作按钮
class _DialogActionButton extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  final String label;

  const _DialogActionButton({
    required this.onTap,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final isDark = BeeTokens.isDark(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: BeeTokens.surface(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? BeeTokens.border(context) : Colors.grey[300]!,
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: primaryColor, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: primaryColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 对话框中的子分类卡片
class _DialogSubCategoryCard extends StatelessWidget {
  final db.Category category;
  final int transactionCount;
  final VoidCallback onTap;

  const _DialogSubCategoryCard({
    required this.category,
    required this.transactionCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final isDark = BeeTokens.isDark(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: BeeTokens.surface(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? BeeTokens.border(context) : Colors.grey[300]!,
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                CategoryService.getCategoryIcon(category.icon),
                color: primaryColor,
                size: 14,
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                CategoryUtils.getDisplayName(category.name, context),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 10),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              AppLocalizations.of(context).categoryMigrationTransactionLabel(transactionCount),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
                fontSize: 9,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

