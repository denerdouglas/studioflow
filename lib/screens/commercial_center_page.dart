import 'package:flutter/material.dart';

import '../core/helpers/app_formatters.dart';

import '../repositories/commercial_repository.dart';
import 'barcode_scanner_page.dart';
import 'catalog_registration_page.dart';
import 'estoque_page.dart';
import 'produtos_loja_page.dart';
import '../services/product_lookup_service.dart';
import '../services/session_controller.dart';

class CommercialCenterPage extends StatefulWidget {
  const CommercialCenterPage({super.key});

  @override
  State<CommercialCenterPage> createState() => _CommercialCenterPageState();
}

class _CommercialCenterPageState extends State<CommercialCenterPage> {
  final _repository = CommercialRepository();
  final _lookup = ProductLookupService();
  final _code = TextEditingController();
  SubscriptionInfo? _subscription;
  Map<String, bool> _steps = const {};
  Map<String, bool> _flags = const {};
  ProductLookupResult? _lookupResult;
  bool _loading = true;
  bool _searching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait([
        _repository.subscription(),
        _repository.setupProgress(),
        _repository.featureFlags(),
      ]);
      if (!mounted) return;
      setState(() {
        _subscription = values[0] as SubscriptionInfo;
        _steps = values[1] as Map<String, bool>;
        _flags = values[2] as Map<String, bool>;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Não foi possível carregar a central comercial.';
      });
    }
  }

  Future<void> _scan() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );
    if (!mounted || code == null) return;
    _code.text = code;
    final result = await _search();
    if (!mounted || result == null) return;
    final product = result.product;
    if (product?.localProductId != null) {
      await _openExistingProduct(product!);
    } else {
      await _openRegistration(
        product: product,
        gtin: result.normalizedGtin,
        productNotFound: product == null,
      );
    }
  }

  Future<ProductLookupResult?> _search() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _lookupResult = null;
    });
    try {
      final result = await _lookup.lookup(
        _code.text,
        commerceId: SessionController.instance.usuario!.comercioId,
      );
      if (!mounted) return null;
      setState(() => _lookupResult = result);
      return result;
    } on FormatException catch (error) {
      _message(error.message);
    } on CatalogProviderUnavailable catch (error) {
      _message(error.message);
    } catch (_) {
      _message('A busca falhou. Tente novamente ou cadastre manualmente.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
    return null;
  }

  Future<void> _simulatePayment() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Simular assinatura?'),
        content: const Text(
          'Esta ação é apenas um teste local. Nenhum cartão será solicitado e nenhuma cobrança será realizada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Simular aprovação'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repository.simulateSubscription();
    await _load();
    _message('Assinatura mock ativada. Nenhuma cobrança real foi feita.');
  }

  Future<void> _openRegistration({
    CatalogProduct? product,
    String? gtin,
    bool productNotFound = false,
  }) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CatalogRegistrationPage(
          product: product,
          gtin: gtin,
          productNotFound: productNotFound,
        ),
      ),
    );
    if (saved == true) {
      _message('Cadastro concluído e mantido somente neste comércio.');
      if (_code.text.trim().isNotEmpty) {
        await _search();
      }
    }
  }

  Future<void> _openExistingProduct(CatalogProduct product) async {
    final id = product.localProductId;
    if (id == null) return;
    if (product.localDestination == 'loja') {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => ProdutoDetalhePage(produtoId: id)),
      );
      return;
    }
    _message('Produto já cadastrado no estoque do salão.');
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const EstoquePage()),
    );
  }

  Future<void> _showSubscriptionHistory() async {
    final history = await _repository.subscriptionHistory();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Histórico de pagamentos'),
        content: SizedBox(
          width: 360,
          child: history.isEmpty
              ? const Text('Nenhuma cobrança ou pagamento registrado.')
              : ListView(
                  shrinkWrap: true,
                  children: history
                      .map(
                        (event) => ListTile(
                          leading: const Icon(Icons.receipt_long_outlined),
                          title: Text(
                            "${event['status_anterior']?.toString() ?? 'início'} → ${event['status_novo']}",
                          ),
                          subtitle: Text(event['criado_em'].toString()),
                        ),
                      )
                      .toList(),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> _showSubscriptionTerms() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Termos da assinatura'),
      content: const Text(
        'O plano comercial custa R\$ 24,99 por mês após 30 dias gratuitos. '
        'Nesta versão o provedor é exclusivamente simulado: não há cobrança, '
        'renovação automática nem armazenamento de cartão. Uma cobrança real '
        'somente poderá ser ativada após aceite de termos e gateway seguro.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Entendi'),
        ),
      ],
    ),
  );
  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('StudioFlow Comercial 1.0')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: Text(_error!),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _brandCard(),
                  const SizedBox(height: 12),
                  _subscriptionCard(),
                  const SizedBox(height: 12),
                  _setupCard(),
                  const SizedBox(height: 12),
                  _catalogCard(),
                  const SizedBox(height: 12),
                  _futureFeaturesCard(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _brandCard() => Card(
    color: const Color(0xFF6D4ACB),
    child: const Padding(
      padding: EdgeInsets.all(20),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white,
            child: Icon(Icons.auto_awesome, color: Color(0xFF6D4ACB), size: 30),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'StudioFlow',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Seu salão organizado, do atendimento à venda.',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _subscriptionCard() {
    final item = _subscription!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Assinatura',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Plano único • ${AppFormatters.moeda(item.monthlyPrice)}/mês'),
            Text(
              item.status == SubscriptionStatus.trial
                  ? 'Período grátis: ${item.trialDaysRemaining} dia(s) restante(s)'
                  : 'Status: ${_statusLabel(item.status)}',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _simulatePayment,
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('Testar pagamento simulado'),
            ),
            const SizedBox(height: 8),
            const Text('Forma de pagamento: provedor mock (sem cartão).'),
            const Text(
              'Próxima cobrança: não agendada enquanto o mock estiver ativo.',
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _showSubscriptionHistory,
                  child: const Text('Histórico'),
                ),
                TextButton(
                  onPressed: _showSubscriptionTerms,
                  child: const Text('Termos'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Ambiente mock: sem cobrança e sem armazenamento de cartão.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _setupCard() {
    final completed = _steps.values.where((value) => value).length;
    final progress = _steps.isEmpty ? 0.0 : completed / _steps.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Primeiros passos',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 8),
            Text('$completed de ${_steps.length} etapas concluídas'),
            ..._steps.entries.map(
              (entry) => CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: entry.value,
                title: Text(_stepLabel(entry.key)),
                onChanged: (value) async {
                  await _repository.completeSetupStep(
                    entry.key,
                    value ?? false,
                  );
                  await _load();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _catalogCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Catálogo inteligente',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Consulte cache, produtos locais e catálogo StudioFlow. Dados de preço, custo e estoque nunca são compartilhados.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'GTIN / código de barras',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.qr_code_2),
              suffixIcon: IconButton(
                tooltip: 'Ler com a câmera',
                onPressed: _scan,
                icon: const Icon(Icons.document_scanner_outlined),
              ),
            ),
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _searching ? null : _search,
            icon: _searching
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search),
            label: const Text('Consultar produto'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _openRegistration(
              gtin: ProductLookupService.normalizeGtin(_code.text),
            ),
            icon: const Icon(Icons.add_box_outlined),
            label: const Text('Cadastrar manualmente'),
          ),
          if (_lookupResult case final result?) ...[
            const Divider(height: 28),
            if (result.product case final product?) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(child: Icon(Icons.inventory_2)),
                title: Text(product.name),
                subtitle: Text(
                  '${product.brand ?? 'Marca não informada'} • fonte: ${product.source}',
                ),
              ),
              Text('Confiança: ${(product.confidence * 100).round()}%'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: () => product.localProductId != null
                        ? _openExistingProduct(product)
                        : _openRegistration(product: product),
                    child: Text(
                      product.localProductId != null
                          ? 'Abrir produto existente'
                          : 'Usar estes dados',
                    ),
                  ),
                  TextButton(
                    onPressed: () => _message(
                      'A correção será registrada como sugestão e nunca substituirá o catálogo global automaticamente.',
                    ),
                    child: const Text('Dados incorretos'),
                  ),
                ],
              ),
            ] else
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.edit_note),
                title: Text('Produto não encontrado'),
                subtitle: Text(
                  'Cadastre manualmente no estoque desejado. Você poderá contribuir com o catálogo mediante consentimento.',
                ),
              ),
            Text(
              'Fontes consultadas: ${result.consultedProviders.join(' → ')}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _futureFeaturesCard() {
    const labels = {
      'customer_profile': 'Perfil do cliente',
      'customer_area': 'Área do cliente',
      'nearby_salons': 'Salões próximos',
      'whatsapp_official': 'WhatsApp oficial',
      'online_ai': 'IA online',
      'catalog_ocr': 'OCR de catálogo',
      'cloud_sync': 'Sincronização em nuvem',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Integrações e próximos recursos',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            ...labels.entries.map(
              (entry) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _flags[entry.key] == true
                      ? Icons.check_circle
                      : Icons.lock_clock,
                  color: _flags[entry.key] == true
                      ? Colors.green
                      : Colors.orange,
                ),
                title: Text(entry.value),
                subtitle: Text(
                  _flags[entry.key] == true
                      ? 'Disponível'
                      : 'Preparado, mas desativado até existir backend/serviço seguro.',
                ),
                onTap: _flags[entry.key] == true
                    ? null
                    : () => _message(
                        '${entry.value} depende de serviço externo seguro e permanece desativado.',
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(SubscriptionStatus status) => switch (status) {
    SubscriptionStatus.trial => 'Período grátis',
    SubscriptionStatus.active => 'Ativa',
    SubscriptionStatus.pending => 'Pendente',
    SubscriptionStatus.overdue => 'Em atraso',
    SubscriptionStatus.gracePeriod => 'Período de tolerância',
    SubscriptionStatus.suspended => 'Suspensa',
    SubscriptionStatus.canceled => 'Cancelada',
  };

  String _stepLabel(String step) => switch (step) {
    'dados_negocio' => 'Perfil do salão',
    'logomarca' => 'Logomarca',
    'profissionais' => 'Profissionais',
    'servicos' => 'Serviços',
    'horarios' => 'Horários',
    'agenda' => 'Agenda',
    'clientes' => 'Clientes',
    'estoque_salao' => 'Estoque do salão',
    'loja_salao' => 'Loja do Salão',
    'estoque_loja' => 'Estoque da loja',
    'fornecedores' => 'Fornecedores',
    'cardapio' => 'Cardápio',
    'ia' => 'StudioFlow IA',
    'pagamentos' => 'Pagamentos',
    'assinatura' => 'Assinatura',
    _ => step,
  };
}