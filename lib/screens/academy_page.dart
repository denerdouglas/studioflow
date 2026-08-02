import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

import '../controllers/academy_controller.dart';
import '../models/domain/academy.dart';

class AcademyPage extends StatefulWidget {
  final AcademyController controller;

  const AcademyPage({super.key, required this.controller});

  @override
  State<AcademyPage> createState() => _AcademyPageState();
}

class _AcademyPageState extends State<AcademyPage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.controller.currentQuery;
    widget.controller.addListener(_onStateChanged);
    if (widget.controller.state == AcademyState.initial) {
      widget.controller.init();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onStateChanged);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _refresh() async {
    await widget.controller.fetchCategories();
    await widget.controller.search(
      query: _searchController.text,
      categoryId: widget.controller.currentCategoryId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('StudioFlow Acadêmico'),
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          key: const PageStorageKey('academy_scroll'),
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: _buildSearchBar(),
            ),
            if (widget.controller.categories != null && widget.controller.categories!.isNotEmpty)
              SliverToBoxAdapter(
                child: _buildCategories(),
              ),
            if (widget.controller.isOffline)
              SliverToBoxAdapter(
                child: _buildOfflineWarning(),
              ),
            _buildContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'O que você quer aprender? Ex: Gestão',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        onSubmitted: (val) {
          widget.controller.search(
            query: val,
            categoryId: widget.controller.currentCategoryId,
          );
        },
      ),
    );
  }

  Widget _buildCategories() {
    final categories = widget.controller.categories!;
    return SizedBox(
      height: 50,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: categories.length + 1,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            final isSelected = widget.controller.currentCategoryId == null;
            return ChoiceChip(
              label: const Text('Todos'),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  widget.controller.search(
                    query: _searchController.text,
                    categoryId: null,
                  );
                }
              },
            );
          }

          final category = categories[index - 1];
          final isSelected = widget.controller.currentCategoryId == category.id;
          return ChoiceChip(
            label: Text(category.name),
            selected: isSelected,
            onSelected: (selected) {
              if (selected) {
                widget.controller.search(
                  query: _searchController.text,
                  categoryId: category.id,
                );
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildOfflineWarning() {
    return Container(
      color: Colors.amber.shade100,
      padding: const EdgeInsets.all(12),
      child: const Row(
        children: [
          Icon(Icons.offline_bolt, color: Colors.amber),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Modo Offline. Exibindo cursos cacheados. A matrícula online não está disponível no momento.',
              style: TextStyle(color: Colors.black87, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (widget.controller.state) {
      case AcademyState.initial:
        return const SliverToBoxAdapter(child: SizedBox.shrink());
      case AcademyState.loading:
        return _buildLoading();
      case AcademyState.empty:
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              children: const [
                Icon(Icons.school_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'Nenhum curso encontrado no momento.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(height: 8),
                Text(
                  'Tente outra pesquisa ou volte mais tarde.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        );
      case AcademyState.error:
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text(widget.controller.errorMessage ?? 'Erro desconhecido', textAlign: TextAlign.center),
              ],
            ),
          ),
        );
      case AcademyState.found:
        return _buildResults(widget.controller.currentResult!.courses);
      case AcademyState.offline:
        return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
  }

  Widget _buildLoading() {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        },
        childCount: 5,
      ),
    );
  }

  Widget _buildResults(List<AcademyCourse> courses) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final course = courses[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: course.coverImageUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(course.coverImageUrl!, fit: BoxFit.cover),
                              )
                            : const Icon(Icons.menu_book, color: Colors.grey, size: 40),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              course.title,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (course.subtitle != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                course.subtitle!,
                                style: Theme.of(context).textTheme.bodySmall,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.timer_outlined, size: 14, color: Colors.grey),
                                const SizedBox(width: 4),
                                Text(
                                  '${course.durationMinutes} min',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                                ),
                                const SizedBox(width: 12),
                                const Icon(Icons.signal_cellular_alt, size: 14, color: Colors.grey),
                                const SizedBox(width: 4),
                                Text(
                                  course.difficultyLevel.toUpperCase(),
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                                ),
                              ],
                            ),
                            if (course.rating != null) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.star, size: 14, color: Colors.amber),
                                  const SizedBox(width: 4),
                                  Text(
                                    course.rating!.toStringAsFixed(1),
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '(${course.totalReviews})',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                                  ),
                                ],
                              ),
                            ]
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (course.price != null && course.price! > 0)
                        Text(
                          '${course.currency} ${course.price!.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        )
                      else
                        Text(
                          'GRÁTIS',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      _buildActionButtons(course),
                    ],
                  )
                ],
              ),
            ),
          );
        },
        childCount: courses.length,
      ),
    );
  }

  Widget _buildActionButtons(AcademyCourse course) {
    if (course.isComingSoon) {
      return FilledButton.tonalIcon(
        onPressed: null,
        icon: const Icon(Icons.access_time),
        label: const Text('Em breve'),
      );
    }
    
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.share_outlined),
          onPressed: () {
            SharePlus.instance.share(ShareParams(text: 'Confira o curso ${course.title} no StudioFlow Acadêmico!'));
          },
        ),
        FilledButton(
          onPressed: () async {
            if (widget.controller.isOffline) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não é possível matricular no modo offline.')));
              return;
            }
            if (course.clickId == null || course.clickId!.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Matrícula indisponível no momento.')));
              return;
            }
            final uri = Uri.tryParse('https://api.studioflowapp.com.br/academy/r/${course.clickId}');
            if (uri == null || uri.scheme != 'https' || uri.host != 'api.studioflowapp.com.br' || !uri.path.startsWith('/academy/r/')) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link de matrícula inválido ou inseguro.')));
              return;
            }
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          child: const Text('Matricular'),
        ),
      ],
    );
  }
}
