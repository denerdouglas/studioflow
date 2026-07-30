import 'package:flutter/material.dart';

import '../repositories/catalog_registration_repository.dart';
import '../services/product_lookup_service.dart';

class CatalogRegistrationPage extends StatefulWidget {
  final CatalogProduct? product;
  final String? gtin;
  final bool productNotFound;

  const CatalogRegistrationPage({
    super.key,
    this.product,
    this.gtin,
    this.productNotFound = false,
  });

  @override
  State<CatalogRegistrationPage> createState() =>
      _CatalogRegistrationPageState();
}

class _CatalogRegistrationPageState extends State<CatalogRegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final _repository = CatalogRegistrationRepository();
  late final TextEditingController _gtin;
  late final TextEditingController _name;
  late final TextEditingController _brand;
  late final TextEditingController _description;
  late final TextEditingController _category;
  late final TextEditingController _image;
  final _unit = TextEditingController(text: 'un');
  final _cost = TextEditingController(text: '0');
  final _sale = TextEditingController(text: '0');
  final _quantity = TextEditingController(text: '0');
  final _minimum = TextEditingController(text: '0');
  final _batch = TextEditingController();
  final _notes = TextEditingController();
  InventoryDestination _destination = InventoryDestination.salon;
  CatalogContributionDecision _contribution =
      CatalogContributionDecision.sendForReview;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _gtin = TextEditingController(
      text: widget.product?.gtin ?? widget.gtin ?? '',
    );
    _name = TextEditingController(text: widget.product?.name ?? '');
    _brand = TextEditingController(text: widget.product?.brand ?? '');
    _description = TextEditingController(
      text: widget.product?.description ?? '',
    );
    _category = TextEditingController(text: widget.product?.category ?? '');
    _image = TextEditingController(text: widget.product?.imageUrl ?? '');
    _unit.text = widget.product?.unit ?? _unitFromQuantity(widget.product?.quantity);
  }

  @override
  void dispose() {
    for (final controller in [
      _gtin,
      _name,
      _brand,
      _description,
      _category,
      _image,
      _unit,
      _cost,
      _sale,
      _quantity,
      _minimum,
      _batch,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  static String _unitFromQuantity(String? quantity) {
    final match = RegExp(
      r'\b(ml|l|g|kg|un|und|unidades?)\b',
      caseSensitive: false,
    ).firstMatch(quantity ?? '');
    if (match == null) return 'un';
    final value = match.group(1)!.toLowerCase();
    return value.startsWith('un') ? 'un' : value;
  }

  double _number(TextEditingController controller) =>
      double.tryParse(controller.text.trim().replaceAll(',', '.')) ?? -1;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await _repository.save(
        LocalProductInput(
          gtin: _gtin.text,
          name: _name.text,
          brand: _brand.text,
          imageUrl: _image.text.trim().isEmpty ? null : _image.text.trim(),
          description: _description.text,
          category: _category.text,
          unit: _unit.text,
          costPrice: _number(_cost),
          salePrice: _number(_sale),
          quantity: _number(_quantity),
          minimumStock: _number(_minimum),
          batch: _batch.text,
          notes: _notes.text,
          destination: _destination,
          contribution: _contribution,
          source: widget.product?.source ?? 'manual',
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Produto salvo no estoque ${_destination == InventoryDestination.store ? 'da loja' : 'do salão'}.',
          ),
        ),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cadastrar produto local')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Dados gerais',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (widget.productNotFound)
              const Card(
                color: Color(0xFFFFF3CD),
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Produto não encontrado. Complete os dados para cadastrá-lo.',
                  ),
                ),
              ),
            _field(_gtin, 'GTIN (opcional)', keyboard: TextInputType.number),
            _field(_name, 'Nome *', required: true),
            _field(_brand, 'Marca'),
            _field(_description, 'Descrição', lines: 2),
            _field(_category, 'Categoria *', required: true),
            _field(_image, 'URL da imagem'),
            if (_image.text.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    _image.text.trim(),
                    height: 150,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const SizedBox(
                      height: 80,
                      child: Center(child: Text('Imagem indisponível')),
                    ),
                  ),
                ),
              ),
            if ((widget.product?.quantity ?? '').isNotEmpty)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('Volume/embalagem identificado'),
                subtitle: Text(widget.product!.quantity!),
              ),
            _field(_unit, 'Unidade *', required: true),
            const SizedBox(height: 10),
            const Text(
              'Dados privados deste comércio',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SegmentedButton<InventoryDestination>(
              segments: const [
                ButtonSegment(
                  value: InventoryDestination.salon,
                  icon: Icon(Icons.content_cut),
                  label: Text('Salão'),
                ),
                ButtonSegment(
                  value: InventoryDestination.store,
                  icon: Icon(Icons.storefront),
                  label: Text('Loja'),
                ),
              ],
              selected: {_destination},
              onSelectionChanged: (value) =>
                  setState(() => _destination = value.single),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _field(_cost, 'Custo', keyboard: TextInputType.number),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _field(
                    _sale,
                    _destination == InventoryDestination.store
                        ? 'Preço de venda'
                        : 'Preço (não usado)',
                    keyboard: TextInputType.number,
                    enabled: _destination == InventoryDestination.store,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _field(
                    _quantity,
                    'Quantidade',
                    keyboard: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _field(
                    _minimum,
                    'Estoque mínimo',
                    keyboard: TextInputType.number,
                  ),
                ),
              ],
            ),
            _field(_batch, 'Lote'),
            _field(_notes, 'Observações privadas', lines: 2),
            const SizedBox(height: 12),
            const Text(
              'Deseja enviar somente os dados gerais para análise do catálogo?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            RadioGroup<CatalogContributionDecision>(
              groupValue: _contribution,
              onChanged: (value) => setState(() => _contribution = value!),
              child: const Column(
                children: [
                  RadioListTile(
                    value: CatalogContributionDecision.sendForReview,
                    title: Text('Enviar para análise'),
                  ),
                  RadioListTile(
                    value: CatalogContributionDecision.doNotSend,
                    title: Text('Não enviar'),
                  ),
                  RadioListTile(
                    value: CatalogContributionDecision.askLater,
                    title: Text('Perguntar novamente depois'),
                  ),
                ],
              ),
            ),
            const Text(
              'Preços, estoque, fornecedor, lote e observações nunca são enviados.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save),
              label: Text(_saving ? 'Salvando...' : 'Confirmar cadastro'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = false,
    int lines = 1,
    TextInputType? keyboard,
    bool enabled = true,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      controller: controller,
      enabled: enabled,
      maxLines: lines,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator: required && controller.text.trim().isEmpty
          ? (_) => 'Campo obrigatório.'
          : null,
    ),
  );
}
