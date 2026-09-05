import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/helpers/app_formatters.dart';
import '../models/domain/commercial_campaign.dart';
import '../repositories/commercial_campaign_repository.dart';

class CommercialCampaignsPage extends StatefulWidget {
  final CommercialCampaignRepository repository;

  CommercialCampaignsPage({super.key, CommercialCampaignRepository? repository})
    : repository = repository ?? CommercialCampaignRepository();

  @override
  State<CommercialCampaignsPage> createState() =>
      _CommercialCampaignsPageState();
}

class _CommercialCampaignsPageState extends State<CommercialCampaignsPage> {
  late Future<List<CommercialCampaign>> _future;
  final Set<String> _impressed = {};

  @override
  void initState() {
    super.initState();
    _future = widget.repository.list();
  }

  void _recordImpression(CommercialCampaign item) {
    if (_impressed.add(item.id)) {
      widget.repository.impression(item.id).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ROLG Academy & Ofertas')),
    body: FutureBuilder<List<CommercialCampaign>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snapshot.data ?? const <CommercialCampaign>[];
        if (items.isEmpty) {
          return const Center(child: Text('Nenhuma oferta disponível agora.'));
        }
        return RefreshIndicator(
          onRefresh: () async {
            setState(() => _future = widget.repository.list());
            await _future;
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              _recordImpression(item);
              return _CampaignCard(
                item: item,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CommercialCampaignDetailPage(
                      item: item,
                      repository: widget.repository,
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    ),
  );
}

class CommercialCampaignDetailPage extends StatelessWidget {
  final CommercialCampaign item;
  final CommercialCampaignRepository repository;

  const CommercialCampaignDetailPage({
    super.key,
    required this.item,
    required this.repository,
  });

  Future<void> _open(BuildContext context) async {
    final uri = CommercialCampaign.safeDestination(item.destinationUrl);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link inválido ou inseguro.')),
      );
      return;
    }
    try {
      try {
        await repository.click(item.id);
      } catch (_) {
        // Analytics é auxiliar e não deve impedir o destino já validado.
      }
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('Não foi possível abrir o link.');
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível abrir esta oferta.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(item.disclosure)),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (item.imageUrl case final image?)
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.network(
              image,
              height: 220,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        const SizedBox(height: 16),
        Chip(label: Text(item.disclosure)),
        Text(item.title, style: Theme.of(context).textTheme.headlineSmall),
        if (item.subtitle != null) Text(item.subtitle!),
        const SizedBox(height: 16),
        Text(item.description),
        const SizedBox(height: 20),
        _CampaignPrice(item: item),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => _open(context),
          child: Text(item.ctaText),
        ),
      ],
    ),
  );
}

class _CampaignCard extends StatelessWidget {
  final CommercialCampaign item;
  final VoidCallback onTap;
  const _CampaignCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.all(14),
      leading: const CircleAvatar(child: Icon(Icons.school_outlined)),
      title: Text(item.title),
      subtitle: Text('${item.disclosure} • ${item.subtitle ?? item.category}'),
      trailing: const Icon(Icons.chevron_right),
    ),
  );
}

class _CampaignPrice extends StatelessWidget {
  final CommercialCampaign item;
  const _CampaignPrice({required this.item});

  @override
  Widget build(BuildContext context) {
    final price = item.priceCents;
    if (price == null) return const SizedBox.shrink();
    return Row(
      children: [
        if (item.originalPriceCents case final original?) ...[
          Text(
            AppFormatters.moeda(original / 100),
            style: const TextStyle(decoration: TextDecoration.lineThrough),
          ),
          const SizedBox(width: 8),
        ],
        Text(
          AppFormatters.moeda(price / 100),
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ],
    );
  }
}
