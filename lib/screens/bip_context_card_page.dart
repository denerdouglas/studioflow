import 'package:flutter/material.dart';

import '../models/domain/universal_reader.dart';
import '../services/bip_context_service.dart';

class BipContextCardPage extends StatefulWidget {
  final BipResolvedItem item;
  final BipContextService service;

  BipContextCardPage({
    super.key,
    required this.item,
    BipContextService? service,
  }) : service = service ?? BipContextService();

  @override
  State<BipContextCardPage> createState() => _BipContextCardPageState();
}

class _BipContextCardPageState extends State<BipContextCardPage> {
  bool busy = false;
  late double stock = widget.item.product?.quantidadeAtual ?? 0;

  Future<void> move(bool incoming) async {
    setState(() => busy = true);
    try {
      if (incoming) {
        await widget.service.increment(widget.item);
        stock++;
      } else {
        await widget.service.decrement(widget.item);
        stock--;
      }
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.item.product;
    final own = widget.item.kind == BipItemKind.produtoProprio;
    final consigned = widget.item.kind == BipItemKind.pecaConsignada;
    return Scaffold(
      appBar: AppBar(title: const Text('Ficha rápida do Bip')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            product?.nome ?? widget.item.draft.nome?.value ?? 'Produto',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text(
            widget.item.draft.gtin?.value ??
                widget.item.draft.referenciaComercial?.value ??
                '',
          ),
          Text('Preço: R\$ ${(product?.precoVenda ?? 0).toStringAsFixed(2)}'),
          if (own) Text('Estoque atual: $stock'),
          if (consigned) ...[
            const Text('Tipo: peça consignada'),
            Text(
              'Status: ${product?.ativo == true ? 'Disponível' : 'Inativa'}',
            ),
          ],
          const SizedBox(height: 20),
          if (own)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: busy ? null : () => move(false),
                  child: const Text('-1'),
                ),
                OutlinedButton(
                  onPressed: busy ? null : () => move(true),
                  child: const Text('+1'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, ReaderAction.vender),
                  child: const Text('Vender'),
                ),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, ReaderAction.editar),
                  child: const Text('Editar'),
                ),
                OutlinedButton(
                  onPressed: () =>
                      Navigator.pop(context, ReaderAction.conferir),
                  child: const Text('Apenas conferir'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          await widget.service.deactivate(widget.item);
                          if (context.mounted) {
                            Navigator.pop(context, ReaderAction.inativar);
                          }
                        },
                  child: const Text('Inativar'),
                ),
              ],
            ),
          if (consigned)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: () => Navigator.pop(context, ReaderAction.vender),
                  child: const Text('Vender'),
                ),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, 'devolver'),
                  child: const Text('Devolver'),
                ),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, 'ocorrencia'),
                  child: const Text('Ocorrência'),
                ),
                OutlinedButton(
                  onPressed: () =>
                      Navigator.pop(context, ReaderAction.conferir),
                  child: const Text('Apenas conferir'),
                ),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, ReaderAction.editar),
                  child: const Text('Editar'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
