import 'package:flutter/material.dart';

import 'catalogos_loja_page.dart';
import 'comandas_loja_page.dart';
import 'estoque_page.dart';
import 'joias_consignadas_page.dart';
import 'produtos_loja_page.dart';
import 'suprimentos_page.dart';

abstract class _AreaPage extends StatelessWidget {
  const _AreaPage({super.key});

  String get title;
  List<Widget> destinations(BuildContext context);

  Future<void> open(BuildContext context, Widget page) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));

  Widget destination(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget page,
  }) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => open(context, page),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: ListView(
      padding: const EdgeInsets.all(12),
      children: destinations(context),
    ),
  );
}

class ProdutosAreaPage extends _AreaPage {
  const ProdutosAreaPage({super.key});

  @override
  String get title => 'Produtos';

  @override
  List<Widget> destinations(BuildContext context) => [
    destination(
      context,
      title: 'Pesquisar produtos',
      subtitle: 'Nome, código, GTIN, marca ou categoria',
      icon: Icons.search,
      page: const ProdutosLojaPage(),
    ),
    Card(
      child: ListTile(
        leading: const Icon(Icons.add_circle_outline),
        title: const Text('Adicionar produto'),
        subtitle: const Text('Escanear, importar ou cadastrar manualmente'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          builder: (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(title: Text('Adicionar produto')),
                ListTile(
                  leading: const Icon(Icons.document_scanner_outlined),
                  title: const Text('Escanear produto'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    open(context, const ProdutosLojaPage(abrirScanner: true));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.upload_file_outlined),
                  title: const Text('Importar produtos'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    open(
                      context,
                      const CatalogosLojaPage(abrirImportacao: true),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.edit_note),
                  title: const Text('Cadastro manual'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    open(context, const ProdutoFormPage());
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    destination(
      context,
      title: 'Categorias / Catálogos',
      subtitle: 'Organizar e importar produtos',
      icon: Icons.category_outlined,
      page: const CatalogosLojaPage(),
    ),
  ];
}

class VendasRecebimentosAreaPage extends _AreaPage {
  const VendasRecebimentosAreaPage({super.key});
  @override
  String get title => 'Vendas e recebimentos';
  @override
  List<Widget> destinations(BuildContext context) => [
    destination(
      context,
      title: 'Comandas',
      subtitle: 'Todas as vendas, abertas, pagas e canceladas',
      icon: Icons.receipt_long,
      page: const ComandasLojaPage(),
    ),
    destination(
      context,
      title: 'Contas a receber',
      subtitle: 'Pendentes, vencidas e recebimentos',
      icon: Icons.account_balance_wallet_outlined,
      page: const ContasReceberPage(),
    ),
  ];
}

class EstoqueReposicaoAreaPage extends _AreaPage {
  const EstoqueReposicaoAreaPage({super.key});
  @override
  String get title => 'Estoque e reposição';
  @override
  List<Widget> destinations(BuildContext context) => [
    destination(
      context,
      title: 'Estoque',
      subtitle: 'Saldos, movimentações, perdas e avarias',
      icon: Icons.inventory_2_outlined,
      page: const EstoquePage(),
    ),
    destination(
      context,
      title: 'Consignação',
      subtitle: 'Remessas, peças, acertos e devoluções',
      icon: Icons.handshake_outlined,
      page: const JoiasConsignadasPage(),
    ),
    destination(
      context,
      title: 'Fornecedores',
      subtitle: 'Pesquisar e manter fornecedores',
      icon: Icons.local_shipping_outlined,
      page: const FornecedoresPage(),
    ),
    destination(
      context,
      title: 'Compras',
      subtitle: 'Estoque baixo, comparação, ordens e recebimento',
      icon: Icons.shopping_cart_checkout,
      page: const ComprasReposicaoAreaPage(),
    ),
  ];
}

class ComprasReposicaoAreaPage extends _AreaPage {
  const ComprasReposicaoAreaPage({super.key});
  @override
  String get title => 'Compras e reposição';
  @override
  List<Widget> destinations(BuildContext context) => [
    destination(
      context,
      title: 'Estoque baixo',
      subtitle: 'Produtos que precisam de reposição',
      icon: Icons.warning_amber,
      page: const ProdutosLojaPage(somenteBaixo: true),
    ),
    destination(
      context,
      title: 'Comparador de reposição',
      subtitle: 'Comparar ofertas reais salvas',
      icon: Icons.compare_arrows,
      page: const ComparadorReposicaoPage(),
    ),
    destination(
      context,
      title: 'Ordens e recebimento',
      subtitle: 'Criar, aprovar, conferir e receber',
      icon: Icons.inventory_outlined,
      page: const OrdensCompraPage(),
    ),
  ];
}
