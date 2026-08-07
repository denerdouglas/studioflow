import 'dart:async';
import 'package:flutter/material.dart';

class SmartSelector<T> extends StatefulWidget {
  final String title;
  final String searchHint;
  final Future<List<T>> Function(String query, int offset, int limit) onSearch;
  final Widget Function(BuildContext, T) itemBuilder;
  final void Function(T) onSelected;
  final Widget? emptyState;
  final Future<T?> Function(BuildContext)? onCreateNew;
  final int pageSize;
  final Duration debounceDuration;

  const SmartSelector({
    super.key,
    required this.title,
    required this.searchHint,
    required this.onSearch,
    required this.itemBuilder,
    required this.onSelected,
    this.emptyState,
    this.onCreateNew,
    this.pageSize = 20,
    this.debounceDuration = const Duration(milliseconds: 300),
  });

  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required String searchHint,
    required Future<List<T>> Function(String query, int offset, int limit)
    onSearch,
    required Widget Function(BuildContext, T) itemBuilder,
    Widget? emptyState,
    Future<T?> Function(BuildContext)? onCreateNew,
    int pageSize = 20,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return SmartSelector<T>(
              title: title,
              searchHint: searchHint,
              onSearch: onSearch,
              itemBuilder: itemBuilder,
              onSelected: (item) => Navigator.of(context).pop(item),
              emptyState: emptyState,
              onCreateNew: onCreateNew,
              pageSize: pageSize,
            );
          },
        );
      },
    );
  }

  @override
  State<SmartSelector<T>> createState() => _SmartSelectorState<T>();
}

class _SmartSelectorState<T> extends State<SmartSelector<T>> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<T> _items = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  String _currentQuery = '';

  Timer? _debounce;
  int _searchRequestId = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _performSearch('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(widget.debounceDuration, () {
      if (mounted) {
        _performSearch(query);
      }
    });
  }

  Future<void> _performSearch(String query) async {
    _searchRequestId++;
    final int currentRequestId = _searchRequestId;

    setState(() {
      _isLoading = true;
      _currentQuery = query;
      _offset = 0;
    });

    try {
      final results = await widget.onSearch(query, _offset, widget.pageSize);

      if (!mounted || currentRequestId != _searchRequestId) return;

      setState(() {
        _items = results;
        _hasMore = results.length == widget.pageSize;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted || currentRequestId != _searchRequestId) return;
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao buscar resultados.')),
        );
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;

    setState(() {
      _isLoadingMore = true;
      _offset += widget.pageSize;
    });

    final int currentRequestId = _searchRequestId;

    try {
      final results = await widget.onSearch(
        _currentQuery,
        _offset,
        widget.pageSize,
      );

      if (!mounted || currentRequestId != _searchRequestId) return;

      setState(() {
        _items.addAll(results);
        _hasMore = results.length == widget.pageSize;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted || currentRequestId != _searchRequestId) return;
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _handleCreateNew() async {
    if (widget.onCreateNew != null) {
      final newItem = await widget.onCreateNew!(context);
      if (newItem != null && mounted) {
        widget.onSelected(newItem);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        _buildSearchBar(),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _buildList(),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              widget.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D2140),
              ),
            ),
          ),
          if (widget.onCreateNew != null)
            TextButton.icon(
              onPressed: _handleCreateNew,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Novo'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF70569A),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: widget.searchHint,
          prefixIcon: const Icon(Icons.search, color: Color(0xFF766A85)),
          filled: true,
          fillColor: const Color(0xFFF9F6FC),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_items.isEmpty) {
      return widget.emptyState ??
          const Center(
            child: Text(
              'Nenhum resultado encontrado.',
              style: TextStyle(color: Color(0xFF766A85)),
            ),
          );
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _items.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index == _items.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final item = _items[index];
        return InkWell(
          onTap: () => widget.onSelected(item),
          child: widget.itemBuilder(context, item),
        );
      },
    );
  }
}
