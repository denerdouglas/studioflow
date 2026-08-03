import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

import '../controllers/marketplace_controller.dart';
import '../repositories/recommendation_engine.dart';
import '../models/domain/marketplace.dart';

class MarketplacePage extends StatefulWidget {
  final MarketplaceController controller;

  const MarketplacePage({super.key, required this.controller});

  @override
  State<MarketplacePage> createState() => _MarketplacePageState();
}

class _MarketplacePageState extends State<MarketplacePage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.controller.currentQuery;
    widget.controller.addListener(_onStateChanged);
    if (widget.controller.state == MarketplaceState.initial) {
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
    await widget.controller.init();
    if (_searchController.text.isNotEmpty) {
      await widget.controller.search(_searchController.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Marketplace StudioFlow'), elevation: 0),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          key: const PageStorageKey('marketplace_scroll'),
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(child: _buildSearchBar()),
            SliverToBoxAdapter(child: _buildCategories()),
            if (widget.controller.recommendation != null)
              SliverToBoxAdapter(
                child: _buildRecommendation(widget.controller.recommendation!),
              ),
            if (widget.controller.isOffline)
              SliverToBoxAdapter(child: _buildOfflineWarning()),
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
          hintText: 'O que você procura? Ex: Shampoo',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        onSubmitted: (val) {
          widget.controller.search(val);
        },
      ),
    );
  }

  Widget _buildCategories() {
    final categories = [
      'Cosméticos',
      'Equipamentos',
      'Tecnologia',
      'Cursos',
      'Máquinas',
      'Promoções',
    ];
    return SizedBox(
      height: 50,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return ActionChip(
            label: Text(categories[index]),
            onPressed: () {
              _searchController.text = categories[index];
              widget.controller.search(categories[index]);
            },
          );
        },
      ),
    );
  }

  Widget _buildRecommendation(RecommendationMessage rec) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Card(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Sugestão Inteligente',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(rec.text),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: () {
                    _searchController.text = rec.suggestedQuery;
                    widget.controller.search(rec.suggestedQuery);
                  },
                  child: Text(rec.actionLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOfflineWarning() {
    final dt = widget.controller.currentResult?.fetchedAt;
    final timeStr = dt != null
        ? '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute}'
        : '';

    return Container(
      color: Colors.amber.shade100,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.offline_bolt, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Modo Offline. Última atualização em $timeStr.\nPreços e disponibilidade podem ter mudado.',
              style: const TextStyle(color: Colors.black87, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (widget.controller.state) {
      case MarketplaceState.initial:
        return const SliverToBoxAdapter(child: SizedBox.shrink());
      case MarketplaceState.loading:
        return _buildLoading();
      case MarketplaceState.empty:
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              children: const [
                Icon(Icons.search_off, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'Nenhuma oferta disponível para esta pesquisa no momento.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(height: 8),
                Text(
                  'Tente outro termo ou volte mais tarde.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        );
      case MarketplaceState.error:
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text(widget.controller.errorMessage ?? 'Erro desconhecido'),
              ],
            ),
          ),
        );
      case MarketplaceState.found:
        return _buildResults(widget.controller.currentResult!.results);
      case MarketplaceState.offline:
        return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
  }

  Widget _buildLoading() {
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
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
      }, childCount: 5),
    );
  }

  Widget _buildResults(List<MarketplaceProductGroup> groups) {
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final group = groups[index];
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
                      width: 80,
                      height: 80,
                      color: Colors.grey.shade200,
                      child: group.imageUrl != null
                          ? Image.network(group.imageUrl!, fit: BoxFit.cover)
                          : const Icon(Icons.image, color: Colors.grey),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${group.offers.length} oferta(s) encontrada(s)',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(),
                ...group.offers.map((offer) => _buildOffer(group, offer)),
              ],
            ),
          ),
        );
      }, childCount: groups.length),
    );
  }

  Widget _buildOffer(MarketplaceProductGroup group, MarketplaceOffer offer) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  offer.partner.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'R\$ ${(offer.priceCents / 100).toStringAsFixed(2)}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                if (offer.shippingCents != null)
                  Text(
                    'Frete: R\$ ${(offer.shippingCents! / 100).toStringAsFixed(2)}',
                  ),
                if (offer.badges.isNotEmpty)
                  Wrap(
                    spacing: 4,
                    children: offer.badges
                        .map(
                          (b) => Chip(
                            label: Text(
                              b,
                              style: const TextStyle(fontSize: 10),
                            ),
                            padding: EdgeInsets.zero,
                          ),
                        )
                        .toList(),
                  ),
              ],
            ),
          ),
          Column(
            children: [
              FilledButton(
                onPressed: () async {
                  if (widget.controller.isOffline) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Não é possível comprar no modo offline.',
                        ),
                      ),
                    );
                    return;
                  }
                  if (offer.clickId.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Oferta indisponível para compra.'),
                      ),
                    );
                    return;
                  }
                  final uri = Uri.tryParse(
                    'https://api.studioflowapp.com.br/r/${offer.clickId}',
                  );
                  if (uri == null ||
                      uri.scheme != 'https' ||
                      uri.host != 'api.studioflowapp.com.br' ||
                      !uri.path.startsWith('/r/')) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Link de compra inválido ou inseguro.'),
                      ),
                    );
                    return;
                  }
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: const Text('Comprar'),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.favorite_border),
                    onPressed: () {
                      // Implementar salvar favorito no DB local
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.share),
                    onPressed: () {
                      SharePlus.instance.share(
                        ShareParams(
                          text:
                              'Oferta de ${group.title} por ${offer.partner.name} encontrada no Marketplace StudioFlow!',
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
