import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../repositories/comanda_loja_repository.dart';
import '../repositories/contas_receber_repository.dart';
import '../services/external_action_service.dart';
import '../services/purchase_receipt_service.dart';
import 'clientes_page.dart';
import 'vision_scanner_page.dart';

class ComandasLojaPage extends StatefulWidget {
  const ComandasLojaPage({super.key});
  @override
  State<ComandasLojaPage> createState() => _ComandasLojaPageState();
}

class _ComandasLojaPageState extends State<ComandasLojaPage> {
  final repo = ComandaLojaRepository();
  final pesquisa = TextEditingController();
  late Future<List<Map<String, Object?>>> future = repo.listar();
  void reload() => setState(() => future = repo.listar());

  @override
  void dispose() {
    pesquisa.dispose();
    super.dispose();
  }

  Future<void> create() async {
    final clients = await repo.clientesDisponiveis();
    if (!mounted) return;
    if (clients.isEmpty) {
      final open = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cadastre um cliente'),
          content: const Text(
            'A comanda precisa estar vinculada a um cliente real.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Abrir clientes'),
            ),
          ],
        ),
      );
      if (open == true && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ClientesPage()),
        );
      }
      return;
    }
    String selected = clients.first['id'] as String;
    final due = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Gerar comanda'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selected,
                items: clients
                    .map(
                      (client) => DropdownMenuItem(
                        value: client['id'] as String,
                        child: Text(client['nome'] as String),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setDialogState(() => selected = value!),
                decoration: const InputDecoration(labelText: 'Cliente'),
              ),
              TextField(
                controller: due,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Data de cobrança',
                ),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                  );
                  if (date != null) {
                    due.text = date.toIso8601String();
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Criar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final id = await repo.criar(
      clienteId: selected,
      vencimento: DateTime.tryParse(due.text),
    );
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ComandaDetalhePage(comandaId: id)),
    );
    reload();
  }

  Future<void> cancel(Map<String, Object?> command) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir comanda sem histórico?'),
        content: TextField(
          controller: reason,
          decoration: const InputDecoration(labelText: 'Motivo obrigatório'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await repo.cancelar(command['id'] as String, reason.text);
      reload();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Comandas da Loja'),
      actions: [
        IconButton(
          tooltip: 'Cadastrar cliente',
          icon: const Icon(Icons.person_add_alt),
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ClientesPage()),
            );
            reload();
          },
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: create,
      icon: const Icon(Icons.add),
      label: const Text('Gerar comanda'),
    ),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final query = pesquisa.text.trim().toLowerCase();
        final commands = snapshot.data!
            .where(
              (command) =>
                  query.isEmpty ||
                  '${command['numero']} ${command['cliente_nome']} ${command['status']}'
                      .toLowerCase()
                      .contains(query),
            )
            .toList();
        if (commands.isEmpty && query.isEmpty) {
          return const Center(child: Text('Nenhuma comanda cadastrada.'));
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: pesquisa,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Pesquisar cliente, status ou identificador',
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => reload(),
                child: ListView(
                  children: commands
                      .map(
                        (command) => Card(
                          child: ListTile(
                            title: Text(
                              '${command['numero']} • ${command['cliente_nome']}',
                            ),
                            subtitle: Text(
                              '${command['status']} • R\$ ${(command['total'] as num).toStringAsFixed(2)}',
                            ),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ComandaDetalhePage(
                                    comandaId: command['id'] as String,
                                  ),
                                ),
                              );
                              reload();
                            },
                            trailing: command['status'] == 'aberta'
                                ? IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () => cancel(command),
                                  )
                                : const Icon(Icons.chevron_right),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class ComandaDetalhePage extends StatefulWidget {
  final String comandaId;
  const ComandaDetalhePage({super.key, required this.comandaId});
  @override
  State<ComandaDetalhePage> createState() => _ComandaDetalhePageState();
}

class _ComandaDetalhePageState extends State<ComandaDetalhePage> {
  final repo = ComandaLojaRepository();
  late Future<List<Map<String, Object?>>> future = repo.itens(widget.comandaId);
  void reload() => setState(() => future = repo.itens(widget.comandaId));

  Future<void> changeClient() async {
    try {
      final clients = await repo.clientesDisponiveis();
      if (!mounted) return;
      final selected = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Trocar cliente'),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: clients
                  .map(
                    (client) => ListTile(
                      title: Text('${client['nome']}'),
                      onTap: () =>
                          Navigator.pop(context, client['id'] as String),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      );
      if (selected == null) return;
      await repo.editar(comandaId: widget.comandaId, clienteId: selected);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cliente da comanda atualizado.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> addCode([String? initial]) async {
    final code = TextEditingController(text: initial);
    final quantity = TextEditingController(text: '1');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Adicionar item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: code,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Código, QR ou produto',
              ),
            ),
            TextField(
              controller: quantity,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quantidade'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await repo.adicionarPorCodigo(
        widget.comandaId,
        code.text,
        quantidade: double.parse(quantity.text.replaceAll(',', '.')),
      );
      reload();
    }
  }

  Future<void> scan() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const VisionScannerPage()),
    );
    if (code != null && mounted) await addCode(code);
  }

  Future<void> discount() async {
    final value = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aplicar desconto'),
        content: TextField(
          controller: value,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Valor'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await repo.aplicarDesconto(
        widget.comandaId,
        double.parse(value.text.replaceAll(',', '.')),
      );
      reload();
    }
  }

  Future<void> finalize() async {
    final paid = TextEditingController(text: '0');
    final method = TextEditingController(text: 'pix');
    DateTime? due;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: const Text('Prévia da finalização'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: paid,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Pagamento inicial',
                ),
              ),
              TextField(
                controller: method,
                decoration: const InputDecoration(
                  labelText: 'Forma de pagamento',
                ),
              ),
              ListTile(
                title: Text(
                  due == null
                      ? 'Definir vencimento se houver saldo'
                      : due!.toLocal().toString().split(' ').first,
                ),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                  );
                  if (date != null) setD(() => due = date);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Editar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await repo.finalizar(
        widget.comandaId,
        pagamentoInicial: double.parse(paid.text.replaceAll(',', '.')),
        formaPagamento: method.text,
        vencimento: due,
      );
      if (!mounted) return;
      final action = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Venda finalizada com sucesso'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'whatsapp'),
              child: const Text('Enviar no WhatsApp'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'pdf'),
              child: const Text('Gerar PDF'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'close'),
              child: const Text('Fechar'),
            ),
          ],
        ),
      );
      if (action == 'whatsapp') await share(whatsapp: true);
      if (action == 'pdf') await sharePdf();
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> sharePdf() async {
    final data = await repo.comprovante(widget.comandaId);
    final bytes = await PurchaseReceiptService.pdfBytes(data);
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/comprovante_${widget.comandaId}.pdf');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        text: 'Comprovante de compra • StudioFlow',
      ),
    );
  }

  Future<void> share({bool whatsapp = false, bool copy = false}) async {
    const actions = ExternalActionService();
    final text = await repo.resumoCompartilhavel(widget.comandaId);
    if (copy) {
      await actions.copiar(text);
    } else if (whatsapp) {
      await actions.abrirWhatsApp(mensagem: text);
    } else {
      await actions.compartilhar(text);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Comanda'),
      actions: [
        IconButton(
          tooltip: 'Trocar cliente',
          onPressed: changeClient,
          icon: const Icon(Icons.person_outline),
        ),
        IconButton(
          onPressed: () => share(copy: true),
          icon: const Icon(Icons.copy),
        ),
        IconButton(
          onPressed: () => share(whatsapp: true),
          icon: const Icon(Icons.chat),
        ),
        IconButton(onPressed: share, icon: const Icon(Icons.share)),
      ],
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: discount,
                child: const Text('Desconto'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: finalize,
                child: const Text('Finalizar'),
              ),
            ),
          ],
        ),
      ),
    ),
    floatingActionButton: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.small(
          heroTag: 'scan',
          onPressed: scan,
          child: const Icon(Icons.qr_code_scanner),
        ),
        const SizedBox(height: 8),
        FloatingActionButton(
          heroTag: 'add',
          onPressed: addCode,
          child: const Icon(Icons.add),
        ),
      ],
    ),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return const Center(
            child: Text(
              'Adicione produtos por scanner, OCR, QR, código ou busca.',
            ),
          );
        }
        return ListView(
          children: snapshot.data!
              .map(
                (item) => ListTile(
                  title: Text(item['nome'] as String),
                  subtitle: Text(
                    '${item['quantidade']} × R\$ ${(item['valor_unitario'] as num).toStringAsFixed(2)} = R\$ ${(item['subtotal'] as num).toStringAsFixed(2)}',
                  ),
                  leading: IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: () async {
                      await repo.alterarQuantidade(
                        widget.comandaId,
                        item['id'] as String,
                        (item['quantidade'] as num).toDouble() - 1,
                      );
                      reload();
                    },
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await repo.removerItem(
                        widget.comandaId,
                        item['id'] as String,
                      );
                      reload();
                    },
                  ),
                ),
              )
              .toList(),
        );
      },
    ),
  );
}

class ContasReceberPage extends StatefulWidget {
  const ContasReceberPage({super.key});
  @override
  State<ContasReceberPage> createState() => _ContasReceberPageState();
}

class _ContasReceberPageState extends State<ContasReceberPage> {
  final repo = ContasReceberRepository();
  late Future<List<Map<String, Object?>>> future = load();
  String? status;
  Future<List<Map<String, Object?>>> load() async {
    await repo.atualizarVencidas();
    return repo.listar(status: status);
  }

  Future<void> receive(Map<String, Object?> account) async {
    final value = TextEditingController(
      text: (account['saldo'] as num).toStringAsFixed(2),
    );
    final method = TextEditingController(text: 'pix');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Registrar recebimento'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: value,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Valor'),
            ),
            TextField(
              controller: method,
              decoration: const InputDecoration(labelText: 'Forma'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await repo.registrarPagamento(
        account['id'] as String,
        double.parse(value.text.replaceAll(',', '.')),
        method.text,
      );
      setState(() => future = load());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Contas a receber'),
      actions: [
        PopupMenuButton<String>(
          onSelected: (value) => setState(() {
            status = value == 'todos' ? null : value;
            future = load();
          }),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'todos', child: Text('Todos')),
            PopupMenuItem(value: 'pendente', child: Text('Pendentes')),
            PopupMenuItem(value: 'parcialmente_paga', child: Text('Parciais')),
            PopupMenuItem(value: 'vencida', child: Text('Vencidas')),
            PopupMenuItem(value: 'paga', child: Text('Pagas')),
          ],
        ),
      ],
    ),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return const Center(child: Text('Nenhuma conta a receber.'));
        }
        return ListView(
          children: snapshot.data!
              .map(
                (account) => ListTile(
                  title: Text(account['cliente_nome'] as String),
                  subtitle: Text(
                    '${account['status']} • saldo R\$ ${(account['saldo'] as num).toStringAsFixed(2)} • vence ${account['vencimento']}',
                  ),
                  trailing: account['status'] == 'paga'
                      ? const Icon(Icons.check_circle)
                      : FilledButton(
                          onPressed: () => receive(account),
                          child: const Text('Receber'),
                        ),
                ),
              )
              .toList(),
        );
      },
    ),
  );
}
