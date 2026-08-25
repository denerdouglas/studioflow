import 'package:flutter/material.dart';

import 'loja_areas_page.dart';
import 'vendas_loja_page.dart';
import 'assistente_gestao_page.dart';
import '../models/domain/centro_resultado.dart';


class LojaSalaoPage extends StatelessWidget {
  const LojaSalaoPage({super.key});

  Future<void> _open(BuildContext context, Widget page) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));

  Widget _area(
    BuildContext context, {
    required Key key,
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget page,
  }) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: ListTile(
      key: key,
      minVerticalPadding: 18,
      leading: CircleAvatar(child: Icon(icon)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _open(context, page),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Loja do Salão'),
      actions: [
        IconButton(
          tooltip: 'Assistente de Gestão',
          icon: const Icon(Icons.auto_awesome_outlined),
          onPressed: () => _open(
            context,
            const AssistenteGestaoPage(contexto: CentroResultado.loja),
          ),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        _area(
          context,
          key: const Key('loja_area_vender'),
          title: 'NOVA VENDA',
          subtitle: 'Venda produtos próprios ou consignados',
          icon: Icons.point_of_sale,
          page: const VendasLojaPage(),
        ),
        _area(
          context,
          key: const Key('loja_area_produtos'),
          title: 'PRODUTOS',
          subtitle: 'Pesquisar, cadastrar, importar e organizar',
          icon: Icons.inventory_2_outlined,
          page: const ProdutosAreaPage(),
        ),
        _area(
          context,
          key: const Key('loja_area_vendas'),
          title: 'VENDAS E RECEBIMENTOS',
          subtitle: 'Comandas, contas, histórico e estornos',
          icon: Icons.receipt_long_outlined,
          page: const VendasRecebimentosAreaPage(),
        ),
        _area(
          context,
          key: const Key('loja_area_estoque'),
          title: 'ESTOQUE E REPOSIÇÃO',
          subtitle: 'Estoque, consignação, fornecedores e compras',
          icon: Icons.warehouse_outlined,
          page: const EstoqueReposicaoAreaPage(),
        ),
      ],
    ),
  );
}
