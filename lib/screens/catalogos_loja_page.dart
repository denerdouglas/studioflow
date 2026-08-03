import 'package:flutter/material.dart';

import '../models/domain/acesso.dart';
import '../models/domain/catalogo_loja.dart';
import '../repositories/catalogo_loja_repository.dart';
import '../services/session_controller.dart';
import '../services/undo_action_service.dart';
import '../widgets/context_action_menu.dart';
import 'comandas_loja_page.dart';
import 'estoque_page.dart';
import 'produtos_loja_page.dart';
import 'vision_scanner_page.dart';

class CatalogosLojaPage extends StatefulWidget {
  final bool abrirCriacao;

  const CatalogosLojaPage({super.key, this.abrirCriacao = false});

  @override
  State<CatalogosLojaPage> createState() => _CatalogosLojaPageState();
}

class _CatalogosLojaPageState extends State<CatalogosLojaPage> {
  final repo = CatalogoLojaRepository();
  final undo = UndoActionService();
  late Future<List<CatalogoLoja>> future = _load();

  Future<List<CatalogoLoja>> _load() =>
      repo.listar(unidadeId: SessionController.instance.unidadeAtiva);

  void reload() => setState(() => future = _load());

  @override
  void initState() {
    super.initState();
    if (widget.abrirCriacao) {
      WidgetsBinding.instance.addPostFrameCallback((_) => edit());
    }
  }

  Future<void> edit([CatalogoLoja? current]) async {
    final units = await repo.unidades();
    if (!mounted) return;
    final name = TextEditingController(text: current?.nome);
    final description = TextEditingController(text: current?.descricao);
    final cover = TextEditingController(text: current?.imagemCapa);
    var icon = current?.icone ?? 'storefront';
    var type = current?.tipoControle ?? TipoControleCatalogo.produtoComum;
    var active = current?.ativo ?? true;
    String? unitId =
        current?.unidadeId ??
        SessionController.instance.unidadeAtiva ??
        (units.isEmpty ? null : units.first['id'] as String);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(current == null ? 'Criar catálogo' : 'Editar catálogo'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Nome'),
                ),
                TextField(
                  controller: description,
                  decoration: const InputDecoration(
                    labelText: 'Descrição (opcional)',
                  ),
                ),
                TextField(
                  controller: cover,
                  decoration: const InputDecoration(
                    labelText: 'Imagem/capa (opcional)',
                  ),
                ),
                if (units.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: unitId,
                    decoration: const InputDecoration(labelText: 'Unidade'),
                    items: units
                        .map(
                          (unit) => DropdownMenuItem(
                            value: unit['id'] as String,
                            child: Text(unit['nome'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setDialog(() => unitId = value),
                  ),
                DropdownButtonFormField<TipoControleCatalogo>(
                  initialValue: type,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de controle',
                  ),
                  items: TipoControleCatalogo.values
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(item.nome),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setDialog(() => type = value!),
                ),
                DropdownButtonFormField<String>(
                  initialValue: icon,
                  decoration: const InputDecoration(labelText: 'Ícone'),
                  items:
                      const {
                            'storefront': 'Loja',
                            'diamond': 'Joias',
                            'local_cafe': 'Cafeteria',
                            'checkroom': 'Roupas',
                            'spa': 'Cosméticos',
                            'inventory': 'Produtos',
                          }.entries
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          )
                          .toList(),
                  onChanged: (value) => setDialog(() => icon = value!),
                ),
                SwitchListTile(
                  value: active,
                  title: const Text('Catálogo ativo'),
                  onChanged: (value) => setDialog(() => active = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) return;
    if (current == null) {
      await repo.criar(
        nome: name.text,
        descricao: description.text,
        imagemCapa: cover.text,
        icone: icon,
        unidadeId: unitId,
        tipoControle: type,
        ativo: active,
      );
    } else {
      await repo.editar(
        CatalogoLoja(
          id: current.id,
          comercioId: current.comercioId,
          unidadeId: unitId,
          nome: name.text,
          descricao: description.text,
          imagemCapa: cover.text,
          icone: icon,
          tipoControle: type,
          ativo: active,
          ordem: current.ordem,
          criadoEm: current.criadoEm,
          atualizadoEm: DateTime.now().toUtc(),
        ),
      );
    }
    reload();
  }

  Future<void> toggle(CatalogoLoja catalog) async {
    final next = !catalog.ativo;
    await undo.perform(
      context,
      UndoableAction(
        message: next ? 'Catálogo ativado.' : 'Catálogo inativado.',
        entity: 'catalogo_loja',
        entityId: catalog.id,
        action: next ? 'ativar' : 'inativar',
        previousState: {'ativo': catalog.ativo},
        newState: {'ativo': next},
        execute: () => repo.alterarStatus(catalog.id, next),
        undo: () async {
          await repo.alterarStatus(catalog.id, catalog.ativo);
          reload();
        },
      ),
    );
    reload();
  }

  Future<void> remove(CatalogoLoja catalog) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir catálogo vazio?'),
        content: const Text(
          'Catálogos com produtos ou histórico não podem ser excluídos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await repo.excluir(catalog.id);
      reload();
    }
  }

  List<ContextMenuAction> actions(CatalogoLoja catalog) {
    final user = SessionController.instance.usuario!;
    final canEdit = user.podeAcao(AcaoPermissao.editarProduto);
    final canCreate = user.podeAcao(AcaoPermissao.cadastrarProduto);
    return [
      ContextMenuAction(
        id: 'add',
        label: 'Adicionar produto',
        icon: Icons.add_box_outlined,
        enabled: canCreate && catalog.ativo,
        onSelected: () async => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CatalogoProdutosPage(catalog: catalog),
          ),
        ),
      ),
      ContextMenuAction(
        id: 'edit',
        label: 'Editar catálogo',
        icon: Icons.edit_outlined,
        enabled: canEdit,
        onSelected: () => edit(catalog),
      ),
      ContextMenuAction(
        id: 'up',
        label: 'Mover para cima',
        icon: Icons.arrow_upward,
        enabled: canEdit && catalog.ordem > 0,
        onSelected: () async {
          final old = catalog.ordem;
          await undo.perform(
            context,
            UndoableAction(
              message: 'Ordem do catálogo alterada.',
              entity: 'catalogo_loja',
              entityId: catalog.id,
              action: 'ordenar',
              previousState: {'ordem': old},
              newState: {'ordem': old - 1},
              execute: () => repo.ordenar(catalog.id, old - 1),
              undo: () async {
                await repo.ordenar(catalog.id, old);
                reload();
              },
            ),
          );
          reload();
        },
      ),
      ContextMenuAction(
        id: 'stock',
        label: 'Ver estoque',
        icon: Icons.inventory_2_outlined,
        onSelected: () async => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EstoquePage()),
        ),
      ),
      ContextMenuAction(
        id: 'status',
        label: catalog.ativo ? 'Inativar' : 'Ativar',
        icon: catalog.ativo ? Icons.visibility_off : Icons.visibility,
        enabled: canEdit,
        onSelected: () => toggle(catalog),
      ),
      ContextMenuAction(
        id: 'delete',
        label: 'Excluir catálogo vazio',
        icon: Icons.delete_outline,
        destructive: true,
        enabled: canEdit,
        onSelected: () => remove(catalog),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Catálogos da Loja')),
    floatingActionButton:
        SessionController.instance.usuario!.podeAcao(
          AcaoPermissao.cadastrarProduto,
        )
        ? FloatingActionButton.extended(
            onPressed: edit,
            icon: const Icon(Icons.add),
            label: const Text('Criar catálogo'),
          )
        : null,
    body: FutureBuilder<List<CatalogoLoja>>(
      future: future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return const Center(
            child: Text('Crie seu primeiro catálogo personalizado.'),
          );
        }
        return ListView(
          padding: const EdgeInsets.only(bottom: 90),
          children: snapshot.data!
              .map(
                (catalog) => Card(
                  child: ContextActionTile(
                    semanticLabel: 'Catálogo ${catalog.nome}',
                    leading: CircleAvatar(child: Icon(_icon(catalog.icone))),
                    title: Text(catalog.nome),
                    subtitle: Text(
                      '${catalog.tipoControle.nome}${catalog.ativo ? '' : ' • Inativo'}',
                    ),
                    actions: actions(catalog),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CatalogoProdutosPage(catalog: catalog),
                      ),
                    ).then((_) => reload()),
                  ),
                ),
              )
              .toList(),
        );
      },
    ),
  );
}

class CatalogoProdutosPage extends StatefulWidget {
  final CatalogoLoja catalog;

  const CatalogoProdutosPage({super.key, required this.catalog});

  @override
  State<CatalogoProdutosPage> createState() => _CatalogoProdutosPageState();
}

class _CatalogoProdutosPageState extends State<CatalogoProdutosPage> {
  final repo = CatalogoLojaRepository();
  final undo = UndoActionService();
  late Future<List<Map<String, Object?>>> future = _load();

  Future<List<Map<String, Object?>>> _load() =>
      repo.produtos(widget.catalog.id);
  void reload() => setState(() => future = _load());

  Future<void> chooseAdd() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Adicionar Produto')),
            for (final item in const {
              'barcode': ('Scanner Código de Barras', Icons.barcode_reader),
              'qr': ('Scanner QR Code', Icons.qr_code_scanner),
              'ocr': ('OCR', Icons.document_scanner_outlined),
              'manual': ('Cadastro Manual', Icons.edit_note),
              'bulk': ('Importar em Lote', Icons.upload_file),
            }.entries)
              ListTile(
                leading: Icon(item.value.$2),
                title: Text(item.value.$1),
                onTap: () => Navigator.pop(context, item.key),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'bulk') return importBulk();
    if (choice == 'manual') return editProduct();
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const VisionScannerPage()),
    );
    if (mounted && code != null) await editProduct(initialCode: code);
  }

  Future<void> editProduct({
    Map<String, Object?>? current,
    String? initialCode,
  }) async {
    final name = TextEditingController(text: current?['nome'] as String?);
    final description = TextEditingController(
      text: current?['descricao'] as String?,
    );
    final code = TextEditingController(
      text: initialCode ?? current?['codigo_barras'] as String?,
    );
    final cost = TextEditingController(
      text: (current?['custo_unitario'] as num? ?? 0).toString(),
    );
    final price = TextEditingController(
      text: (current?['preco_venda'] as num? ?? 0).toString(),
    );
    final quantity = TextEditingController(
      text: (current?['quantidade_atual'] as num? ?? 0).toString(),
    );
    final minimum = TextEditingController(
      text: (current?['estoque_minimo'] as num? ?? 0).toString(),
    );
    final supplier = TextEditingController(
      text: current?['fornecedor_principal_id'] as String?,
    );
    final lot = TextEditingController(text: current?['lote'] as String?);
    final validity = TextEditingController(
      text: current?['data_validade'] as String?,
    );
    final size = TextEditingController(text: current?['tamanho'] as String?);
    final color = TextEditingController(text: current?['cor'] as String?);
    final variation = TextEditingController(
      text: current?['variacao'] as String?,
    );
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(current == null ? 'Adicionar produto' : 'Editar produto'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              TextField(
                controller: description,
                decoration: const InputDecoration(labelText: 'Descrição'),
              ),
              TextField(
                controller: code,
                decoration: const InputDecoration(labelText: 'Código'),
              ),
              TextField(
                controller: cost,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Custo'),
              ),
              TextField(
                controller: price,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Preço'),
              ),
              TextField(
                controller: quantity,
                keyboardType: TextInputType.number,
                enabled: current == null,
                decoration: const InputDecoration(labelText: 'Quantidade'),
              ),
              TextField(
                controller: minimum,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Estoque mínimo'),
              ),
              if (widget.catalog.tipoControle ==
                  TipoControleCatalogo.produtoConsignado) ...[
                TextField(
                  controller: supplier,
                  decoration: const InputDecoration(labelText: 'Fornecedor'),
                ),
                TextField(
                  controller: lot,
                  decoration: const InputDecoration(labelText: 'Lote/maleta'),
                ),
              ],
              if ({
                TipoControleCatalogo.alimentoBebida,
                TipoControleCatalogo.produtoValidade,
              }.contains(widget.catalog.tipoControle)) ...[
                TextField(
                  controller: lot,
                  decoration: const InputDecoration(labelText: 'Lote'),
                ),
                TextField(
                  controller: validity,
                  decoration: const InputDecoration(
                    labelText: 'Validade (AAAA-MM-DD)',
                  ),
                ),
              ],
              TextField(
                controller: size,
                decoration: const InputDecoration(
                  labelText: 'Tamanho (opcional)',
                ),
              ),
              TextField(
                controller: color,
                decoration: const InputDecoration(labelText: 'Cor (opcional)'),
              ),
              TextField(
                controller: variation,
                decoration: const InputDecoration(
                  labelText: 'Variação (opcional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    double number(TextEditingController value) =>
        double.tryParse(value.text.replaceAll(',', '.')) ?? 0;
    if (current == null) {
      await repo.adicionarProduto(
        catalogoId: widget.catalog.id,
        nome: name.text,
        descricao: description.text,
        codigo: code.text,
        fornecedorId: supplier.text.isEmpty ? null : supplier.text,
        custo: number(cost),
        preco: number(price),
        quantidade: number(quantity),
        estoqueMinimo: number(minimum),
        lote: lot.text,
        validade: DateTime.tryParse(validity.text),
        tamanho: size.text,
        cor: color.text,
        variacao: variation.text,
      );
    } else {
      await repo.editarProduto(current['id'] as String, {
        'nome': name.text,
        'descricao': description.text,
        'codigo_barras': code.text,
        'codigo_interno': code.text,
        'custo_unitario': number(cost),
        'preco_venda': number(price),
        'estoque_minimo': number(minimum),
        'fornecedor_principal_id': supplier.text,
        'lote': lot.text,
        'data_validade': validity.text,
        'tamanho': size.text,
        'cor': color.text,
        'variacao': variation.text,
      });
    }
    reload();
  }

  Future<void> importBulk() async {
    final input = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Importar em lote'),
        content: TextField(
          controller: input,
          minLines: 5,
          maxLines: 12,
          decoration: const InputDecoration(
            labelText: 'Uma linha por produto',
            hintText: 'Nome;preço;quantidade;código',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Importar'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    final rows = input.text
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .map((line) {
          final parts = line.split(';');
          return <String, Object?>{
            'nome': parts.first.trim(),
            'preco': parts.length > 1
                ? double.tryParse(parts[1].replaceAll(',', '.')) ?? 0
                : 0,
            'quantidade': parts.length > 2
                ? double.tryParse(parts[2].replaceAll(',', '.')) ?? 0
                : 0,
            'codigo': parts.length > 3 ? parts[3].trim() : null,
          };
        })
        .toList();
    await repo.importarLote(widget.catalog.id, rows);
    reload();
  }

  Future<void> toggle(Map<String, Object?> product) async {
    final old = product['ativo'] == 1;
    await undo.perform(
      context,
      UndoableAction(
        message: old ? 'Produto inativado.' : 'Produto ativado.',
        entity: 'estoque',
        entityId: product['id'] as String,
        action: old ? 'inativar' : 'ativar',
        previousState: {'ativo': old},
        newState: {'ativo': !old},
        execute: () => repo.alterarStatusProduto(product['id'] as String, !old),
        undo: () async {
          await repo.alterarStatusProduto(product['id'] as String, old);
          reload();
        },
      ),
    );
    reload();
  }

  Future<void> remove(Map<String, Object?> product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir produto?'),
        content: const Text(
          'A exclusão física só será feita se não existir histórico.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await repo.excluirProduto(product['id'] as String);
      reload();
    }
  }

  List<ContextMenuAction> productActions(Map<String, Object?> product) {
    final canEdit = SessionController.instance.usuario!.podeAcao(
      AcaoPermissao.editarProduto,
    );
    return [
      ContextMenuAction(
        id: 'command',
        label: 'Abrir em Comandas',
        icon: Icons.receipt_long_outlined,
        onSelected: () async => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ComandasLojaPage()),
        ),
      ),
      ContextMenuAction(
        id: 'edit',
        label: 'Editar',
        icon: Icons.edit_outlined,
        enabled: canEdit,
        onSelected: () => editProduct(current: product),
      ),
      ContextMenuAction(
        id: 'duplicate',
        label: 'Duplicar',
        icon: Icons.copy,
        enabled: canEdit,
        onSelected: () async {
          await repo.duplicarProduto(product['id'] as String);
          reload();
        },
      ),
      ContextMenuAction(
        id: 'history',
        label: 'Histórico e movimentações',
        icon: Icons.history,
        onSelected: () async => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ProdutoDetalhePage(produtoId: product['id'] as String),
          ),
        ),
      ),
      ContextMenuAction(
        id: 'stock',
        label: 'Abrir no Estoque',
        icon: Icons.inventory_2_outlined,
        onSelected: () async => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EstoquePage()),
        ),
      ),
      ContextMenuAction(
        id: 'status',
        label: product['ativo'] == 1 ? 'Inativar' : 'Ativar',
        icon: product['ativo'] == 1 ? Icons.visibility_off : Icons.visibility,
        enabled: canEdit,
        onSelected: () => toggle(product),
      ),
      ContextMenuAction(
        id: 'delete',
        label: 'Excluir',
        icon: Icons.delete_outline,
        destructive: true,
        enabled: canEdit,
        onSelected: () => remove(product),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.catalog.nome)),
    floatingActionButton: widget.catalog.ativo
        ? FloatingActionButton.extended(
            onPressed: chooseAdd,
            icon: const Icon(Icons.add),
            label: const Text('Adicionar Produto'),
          )
        : null,
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return const Center(child: Text('Nenhum produto neste catálogo.'));
        }
        return ListView(
          padding: const EdgeInsets.only(bottom: 90),
          children: snapshot.data!
              .map(
                (product) => Card(
                  child: ContextActionTile(
                    semanticLabel: 'Produto ${product['nome']}',
                    leading: const CircleAvatar(
                      child: Icon(Icons.shopping_bag_outlined),
                    ),
                    title: Text(product['nome'] as String),
                    subtitle: Text(
                      '${product['quantidade_atual']} ${product['unidade']} • R\$ ${(product['preco_venda'] as num? ?? 0).toStringAsFixed(2)}${product['ativo'] == 1 ? '' : ' • Inativo'}',
                    ),
                    actions: productActions(product),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProdutoDetalhePage(
                          produtoId: product['id'] as String,
                        ),
                      ),
                    ).then((_) => reload()),
                  ),
                ),
              )
              .toList(),
        );
      },
    ),
  );
}

IconData _icon(String? value) => switch (value) {
  'diamond' => Icons.diamond_outlined,
  'local_cafe' => Icons.local_cafe_outlined,
  'checkroom' => Icons.checkroom,
  'spa' => Icons.spa_outlined,
  'inventory' => Icons.inventory_2_outlined,
  _ => Icons.storefront_outlined,
};
