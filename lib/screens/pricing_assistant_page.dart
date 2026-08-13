import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/helpers/app_formatters.dart';
import '../core/utils/id_generator.dart';
import '../database/database_service.dart';
import '../services/pricing_engine.dart';
import '../services/session_controller.dart';

class PricingAssistantPage extends StatefulWidget {
  final bool servico;
  const PricingAssistantPage({super.key, required this.servico});

  @override
  State<PricingAssistantPage> createState() => _PricingAssistantPageState();
}

class _PricingAssistantPageState extends State<PricingAssistantPage> {
  Map<String, Object?>? selected;
  PricingResult? result;
  final margin = TextEditingController(text: '30');
  final taxes = TextEditingController(text: '0');
  final extra = TextEditingController(text: '0');
  final hourly = TextEditingController();

  @override
  void dispose() {
    margin.dispose();
    taxes.dispose();
    extra.dispose();
    hourly.dispose();
    super.dispose();
  }

  Future<List<Map<String, Object?>>> _items() async {
    final db = await DatabaseService.instance.database;
    final commerce = SessionController.instance.usuario!.comercioId;
    if (widget.servico) {
      return db.query(
        'servicos',
        where: 'comercio_id=? AND ativo=1',
        whereArgs: [commerce],
        orderBy: 'nome COLLATE NOCASE',
      );
    }
    final own = await db.query(
      'estoque',
      columns: ['id', 'nome', 'preco_venda', 'custo_unitario'],
      where: "comercio_id=? AND ativo=1 AND estoque_destino='loja'",
      whereArgs: [commerce],
      orderBy: 'nome COLLATE NOCASE',
    );
    final consignments = await db.query(
      'pecas_unicas',
      columns: ['id', 'nome', 'preco', 'custo'],
      where: "comercio_id=? AND status='disponivel'",
      whereArgs: [commerce],
      orderBy: 'nome COLLATE NOCASE',
    );
    return [
      ...own.map((row) => {...row, 'origem': 'proprio'}),
      ...consignments.map((row) => {...row, 'origem': 'consignado'}),
    ];
  }

  Future<void> calculate() async {
    final item = selected;
    if (item == null) return;
    final db = await DatabaseService.instance.database;
    final price =
        ((widget.servico ? item['preco'] : item['preco_venda'] ?? item['preco'])
                    as num? ??
                0)
            .toDouble();
    final cost =
        ((widget.servico
                        ? item['custo_estimado']
                        : item['custo_unitario'] ?? item['custo'])
                    as num? ??
                0)
            .toDouble();
    final input = PricingInput(
      precoAtual: price,
      custoBase: cost <= 0 ? null : cost,
      custosMateriais: widget.servico
          ? (await db.rawQuery(
              '''SELECT sm.quantidade*e.custo_unitario custo
              FROM servico_materiais sm JOIN estoque e ON e.id=sm.estoque_id
              WHERE sm.servico_id=? AND sm.ativo=1''',
              [item['id']],
            )).map((row) => (row['custo'] as num).toDouble()).toList()
          : const [],
      comissaoPercentual: (item['comissao_percentual'] as num? ?? 0).toDouble(),
      taxasPercentual: _number(taxes.text),
      margemDesejadaPercentual: _number(margin.text),
      custoAdicional: _number(extra.text),
      duracaoMinutos: (item['duracao_minutos'] as num?)?.toInt(),
      custoHora: hourly.text.trim().isEmpty ? null : _number(hourly.text),
    );
    setState(() {
      result = widget.servico
          ? PricingEngine.calcularServico(input)
          : PricingEngine.calcularProduto(input);
    });
  }

  Future<void> apply() async {
    final value = result?.precoSugerido;
    final item = selected;
    if (value == null || item == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar alteração de preço'),
        content: Text(
          'Alterar ${item['nome']} para ${AppFormatters.moeda(value)}?\n\nO Assistente não executará sem sua confirmação.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Aplicar preço'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final db = await DatabaseService.instance.database;
    final user = SessionController.instance.usuario!;
    final table = widget.servico
        ? 'servicos'
        : item['origem'] == 'consignado'
        ? 'pecas_unicas'
        : 'estoque';
    final column = widget.servico
        ? 'preco'
        : item['origem'] == 'consignado'
        ? 'preco'
        : 'preco_venda';
    final old = widget.servico
        ? item['preco']
        : item['preco_venda'] ?? item['preco'];
    await db.transaction((tx) async {
      await tx.update(
        table,
        {column: value},
        where: 'id=? AND comercio_id=?',
        whereArgs: [item['id'], user.comercioId],
      );
      await tx.insert('undo_auditoria', {
        'id': IdGenerator.temporal(),
        'comercio_id': user.comercioId,
        'usuario_id': user.id,
        'entidade': widget.servico ? 'servico' : 'produto',
        'entidade_id': item['id'],
        'acao': 'aplicar_preco_assistente',
        'estado_anterior': jsonEncode({'preco': old}),
        'estado_novo': jsonEncode({'preco': value}),
        'criado_em': DateTime.now().toUtc().toIso8601String(),
      });
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preço atualizado e auditado.')),
      );
    }
  }

  static double _number(String value) =>
      double.tryParse(value.replaceAll('.', '').replaceAll(',', '.')) ?? 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.servico ? 'Precificar serviço' : 'Precificar produto'),
    ),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: _items(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                labelText: widget.servico ? 'Serviço' : 'Produto',
              ),
              items: snapshot.data!
                  .map(
                    (item) => DropdownMenuItem(
                      value: '${item['id']}',
                      child: Text('${item['nome']}'),
                    ),
                  )
                  .toList(),
              onChanged: (id) => setState(() {
                selected = snapshot.data!.firstWhere(
                  (item) => item['id'] == id,
                );
                result = null;
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: margin,
              decoration: const InputDecoration(
                labelText: 'Margem desejada (%)',
              ),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: taxes,
              decoration: const InputDecoration(
                labelText: 'Taxas conhecidas (%)',
              ),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: extra,
              decoration: const InputDecoration(labelText: 'Custo adicional'),
              keyboardType: TextInputType.number,
            ),
            if (widget.servico)
              TextField(
                controller: hourly,
                decoration: const InputDecoration(
                  labelText: 'Custo operacional por hora (opcional)',
                ),
                keyboardType: TextInputType.number,
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: calculate,
              child: const Text('Calcular sugestão'),
            ),
            if (result != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Preço atual: ${AppFormatters.moeda(result!.precoAtual)}',
                      ),
                      Text(
                        'Custo conhecido: ${result!.custoConhecido == null ? 'indisponível' : AppFormatters.moeda(result!.custoConhecido!)}',
                      ),
                      Text(
                        'Comissão: ${AppFormatters.moeda(result!.comissao)}',
                      ),
                      Text(
                        'Margem atual: ${result!.margemAtualPercentual?.toStringAsFixed(1) ?? 'indisponível'}%',
                      ),
                      Text(
                        'Equilíbrio: ${result!.precoEquilibrio == null ? 'indisponível' : AppFormatters.moeda(result!.precoEquilibrio!)}',
                      ),
                      Text(
                        'Sugerido: ${result!.precoSugerido == null ? 'indisponível' : AppFormatters.moeda(result!.precoSugerido!)}',
                      ),
                      for (final warning in result!.avisos)
                        Text(
                          warning,
                          style: const TextStyle(color: Colors.orange),
                        ),
                    ],
                  ),
                ),
              ),
              FilledButton(
                onPressed: result!.precoSugerido == null ? null : apply,
                child: const Text('Aplicar preço'),
              ),
              OutlinedButton(
                onPressed: () => setState(() => result = null),
                child: const Text('Editar manualmente'),
              ),
            ],
          ],
        );
      },
    ),
  );
}
