import 'package:flutter/material.dart';

import '../models/domain/universal_reader.dart';
import '../repositories/consignacao_conferencia_repository.dart';
import '../models/domain/scanner_product_draft.dart';
import 'vision_scanner_page.dart';

class ConsignacaoConferenciaPage extends StatefulWidget {
  final String remessaId;
  final String finalidade;

  const ConsignacaoConferenciaPage({
    super.key,
    required this.remessaId,
    required this.finalidade,
  });

  @override
  State<ConsignacaoConferenciaPage> createState() =>
      _ConsignacaoConferenciaPageState();
}

class _ConsignacaoConferenciaPageState
    extends State<ConsignacaoConferenciaPage> {
  final repository = ConsignacaoConferenciaRepository();
  String? id;
  Map<String, Object?>? state;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final conferenceId =
        id ??
        await repository.iniciar(
          remessaId: widget.remessaId,
          finalidade: widget.finalidade,
        );
    final value = await repository.carregar(conferenceId);
    if (!mounted) return;
    setState(() {
      id = conferenceId;
      state = value;
    });
  }

  Future<void> _scan() async {
    if (id == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VisionScannerPage(
          policy: ReaderContextPolicy.forContext(
            ReaderContext.conferenciaRemessa,
          ),
          onContinuousItem: (result) async {
            final draft = result.draft ?? ScannerProductDraft();
            final code = draft.referenciaComercial?.value ?? draft.gtin?.value;
            if (code == null) return false;

            final choices = await repository.resolverCodigo(id!, code);
            if (choices.isEmpty || !mounted) return false;

            var piece = choices.first;
            if (choices.length > 1) {
              final selected = await showDialog<Map<String, Object?>>(
                context: context,
                builder: (dialogContext) => SimpleDialog(
                  title: Text('Escolha uma ocorrência de $code'),
                  children: choices
                      .map(
                        (item) => SimpleDialogOption(
                          onPressed: () => Navigator.pop(dialogContext, item),
                          child: Text('${item['nome']} • ID ${item['id']}'),
                        ),
                      )
                      .toList(),
                ),
              );
              if (selected == null) return false;
              piece = selected;
            }

            await repository.conferirPeca(
              conferenciaId: id!,
              pecaId: piece['id'] as String,
              leituraOriginal: code,
            );
            return true;
          },
        ),
      ),
    );
    await _load();
  }

  Future<void> _finish() async {
    try {
      await repository.finalizar(id!);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('Conferência • ${widget.finalidade}'),
      actions: [
        IconButton(
          tooltip: 'Pausar',
          onPressed: id == null
              ? null
              : () async {
                  await repository.pausar(id!);
                  if (context.mounted) Navigator.pop(context);
                },
          icon: const Icon(Icons.pause_circle_outline),
        ),
      ],
    ),
    body: state == null
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Wrap(
                    spacing: 24,
                    children: [
                      Text('Esperadas: ${state!['esperado']}'),
                      Text('Conferidas: ${state!['conferido']}'),
                      Text('Pendentes: ${state!['pendente']}'),
                    ],
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: _scan,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Conferir por Bip'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: state!['pendente'] == 0 ? _finish : null,
                child: const Text('Finalizar conferência'),
              ),
              if ((state!['pendente'] as num).toInt() > 0)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Itens não lidos permanecem pendentes e nunca são classificados automaticamente.',
                  ),
                ),
            ],
          ),
  );
}
