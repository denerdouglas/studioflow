import 'package:flutter/material.dart';

import '../models/domain/acesso.dart';
import '../models/domain/loja.dart';
import '../repositories/loja_repository.dart';
import '../services/session_controller.dart';
import 'barcode_scanner_page.dart';
import 'central_reposicao_completa_page.dart';
import 'produtos_loja_page.dart';
import 'produto_fornecedores_page.dart';
import 'suprimentos_page.dart';
import 'vendas_loja_page.dart';

class LojaSalaoPage extends StatefulWidget {
  const LojaSalaoPage({super.key});
  @override
  State<LojaSalaoPage> createState() => _LojaSalaoPageState();
}

class _LojaSalaoPageState extends State<LojaSalaoPage> {
  Future<void> abrir(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  Future<void> scanner() async {
    final codigo = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );
    if (!mounted || codigo == null) return;
    try {
      final produto = await LojaRepository().buscarCodigo(codigo);
      if (!mounted) return;
      if (produto == null) {
        final novo = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Produto não encontrado'),
            content: Text('O código $codigo ainda não está cadastrado.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Cadastrar'),
              ),
            ],
          ),
        );
        if (novo == true) await abrir(ProdutoFormPage(codigoInicial: codigo));
      } else {
        await abrir(ProdutoDetalhePage(produtoId: produto.id));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final itens =
        <
          ({
            String titulo,
            String subtitulo,
            IconData icone,
            AcaoPermissao permissao,
            VoidCallback acao,
          })
        >[
          (
            titulo: 'Produtos',
            subtitulo: 'Cadastro, pesquisa, detalhes e histórico',
            icone: Icons.inventory_2_outlined,
            permissao: AcaoPermissao.visualizarEstoque,
            acao: () => abrir(const ProdutosLojaPage()),
          ),
          (
            titulo: 'Produtos e fornecedores',
            subtitulo: 'Preços, embalagens, prazos e fornecedores alternativos',
            icone: Icons.add_link,
            permissao: AcaoPermissao.cadastrarFornecedor,
            acao: () => abrir(const ProdutoFornecedoresPage()),
          ),
          (
            titulo: 'Ler código de barras',
            subtitulo: 'Localizar ou cadastrar rapidamente',
            icone: Icons.barcode_reader,
            permissao: AcaoPermissao.visualizarEstoque,
            acao: scanner,
          ),
          (
            titulo: 'Nova venda',
            subtitulo: 'Carrinho, desconto, pagamento e baixa',
            icone: Icons.point_of_sale,
            permissao: AcaoPermissao.realizarVenda,
            acao: () => abrir(const VendasLojaPage()),
          ),
          (
            titulo: 'Histórico de vendas',
            subtitulo: 'Resumo, cancelamento e estorno',
            icone: Icons.receipt_long_outlined,
            permissao: AcaoPermissao.realizarVenda,
            acao: () => abrir(const HistoricoVendasPage()),
          ),
          (
            titulo: 'Estoque baixo',
            subtitulo: 'Alertas e quantidade sugerida',
            icone: Icons.warning_amber,
            permissao: AcaoPermissao.visualizarEstoque,
            acao: () => abrir(const ProdutosLojaPage(somenteBaixo: true)),
          ),
          (
            titulo: 'Movimentações',
            subtitulo: 'Entradas, saídas, ajustes e perdas',
            icone: Icons.swap_vert,
            permissao: AcaoPermissao.movimentarEstoque,
            acao: () => abrir(const ProdutosLojaPage()),
          ),
          (
            titulo: 'Produtos consignados',
            subtitulo: 'Itens próprios de terceiros',
            icone: Icons.handshake_outlined,
            permissao: AcaoPermissao.acessarConsignacao,
            acao: () => abrir(
              const ProdutosLojaPage(modalidade: ModalidadeProduto.consignado),
            ),
          ),
          (
            titulo: 'Consignações',
            subtitulo: 'Recebimento e fechamento',
            icone: Icons.assignment_turned_in_outlined,
            permissao: AcaoPermissao.acessarConsignacao,
            acao: () => abrir(const ConsignacoesPage()),
          ),
          (
            titulo: 'Fornecedores',
            subtitulo: 'Cadastro e condições comerciais',
            icone: Icons.local_shipping_outlined,
            permissao: AcaoPermissao.cadastrarFornecedor,
            acao: () => abrir(const FornecedoresPage()),
          ),
          (
            titulo: 'Central de Reposição',
            subtitulo: 'Baixo estoque, aprovação e pedidos',
            icone: Icons.playlist_add_check_circle_outlined,
            permissao: AcaoPermissao.criarPedido,
            acao: () => abrir(const CentralReposicaoCompletaPage()),
          ),
          (
            titulo: 'Comparador de Reposição',
            subtitulo: 'Ofertas salvas e pesquisas externas',
            icone: Icons.compare_arrows,
            permissao: AcaoPermissao.visualizarEstoque,
            acao: () => abrir(const ComparadorReposicaoPage()),
          ),
          (
            titulo: 'Ordens de compra',
            subtitulo: 'Aprovação, conferência e recebimento',
            icone: Icons.shopping_cart_checkout,
            permissao: AcaoPermissao.criarPedido,
            acao: () => abrir(const OrdensCompraPage()),
          ),
        ];
    return Scaffold(
      appBar: AppBar(title: const Text('Loja do Salão')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Venda e reposição em um só fluxo',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Produto → estoque → alerta → comparação → ordem → recebimento.',
                  ),
                ],
              ),
            ),
          ),
          ...itens
              .where(
                (item) => SessionController.instance.usuario!.podeAcao(
                  item.permissao,
                ),
              )
              .map(
                (item) => Card(
                  child: ListTile(
                    leading: Icon(
                      item.icone,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(item.titulo),
                    subtitle: Text(item.subtitulo),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: item.acao,
                  ),
                ),
              ),
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Marketplaces externos'),
              subtitle: Text(
                'A compra é concluída no Mercado Livre, Shopee ou fornecedor. O StudioFlow não armazena senhas nem executa compra automática.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
