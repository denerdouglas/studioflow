import 'package:flutter/material.dart';

import '../models/domain/acesso.dart';
import '../models/domain/loja.dart';
import '../models/domain/scanner_product_draft.dart';
import '../repositories/loja_repository.dart';
import '../services/session_controller.dart';
import 'vision_scanner_page.dart';
import 'catalogos_loja_page.dart';
import 'central_reposicao_completa_page.dart';
import 'comandas_loja_page.dart';
import 'joias_consignadas_page.dart';
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
  Future<void> abrir(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) setState(() {}); // Força rebuild caso algum item precise
  }

  Future<void> scanner() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const VisionScannerPage()),
    );
    if (!mounted || result == null) return;
    
    try {
      final ScannerProductDraft draft = result['draft'];
      final String finalidade = result['finalidade'];
      
      final String? codigo = draft.gtin?.value;
      if (codigo == null || codigo.isEmpty) {
        // Criar produto totalmente manual baseado no draft
        await abrir(ProdutoFormPage(draftInicial: draft, finalidadeInicial: finalidade));
        return;
      }

      final produto = await LojaRepository().buscarCodigo(codigo);
      if (!mounted) return;
      if (produto == null) {
        // Criar produto novo
        await abrir(ProdutoFormPage(codigoInicial: codigo, draftInicial: draft, finalidadeInicial: finalidade));
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

  Widget _buildGroupTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildItem(String titulo, String subtitulo, IconData icone, AcaoPermissao permissao, VoidCallback acao) {
    if (!SessionController.instance.usuario!.podeAcao(permissao)) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: Icon(icone, color: Theme.of(context).colorScheme.primary),
        title: Text(titulo),
        subtitle: Text(subtitulo),
        trailing: const Icon(Icons.chevron_right),
        onTap: acao,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Loja do Salão')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Card(
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
                    Text('Produto → estoque → alerta → comparação → ordem → recebimento.'),
                  ],
                ),
              ),
            ),
          ),
          
          _buildGroupTitle('PRODUTOS E CATÁLOGOS'),
          _buildItem('Catálogos', 'Agrupe produtos para facilitar a venda', Icons.storefront_outlined, AcaoPermissao.visualizarEstoque, () => abrir(const CatalogosLojaPage())),
          _buildItem('Produtos à venda', 'Cadastro, pesquisa e detalhes', Icons.inventory_2_outlined, AcaoPermissao.visualizarEstoque, () => abrir(const ProdutosLojaPage())),
          _buildItem('Ler produto', 'Localizar ou cadastrar rapidamente', Icons.barcode_reader, AcaoPermissao.visualizarEstoque, scanner),

          _buildGroupTitle('VENDAS'),
          _buildItem('Nova venda', 'Carrinho, desconto e pagamento', Icons.point_of_sale, AcaoPermissao.realizarVenda, () => abrir(const VendasLojaPage())),
          _buildItem('Comandas', 'Venda em andamento', Icons.receipt_long, AcaoPermissao.realizarVenda, () => abrir(const ComandasLojaPage())),
          _buildItem('Contas a receber', 'Pendentes e vencidas', Icons.account_balance_wallet_outlined, AcaoPermissao.acessarFinanceiro, () => abrir(const ContasReceberPage())),
          _buildItem('Histórico de vendas', 'Resumo e estorno', Icons.receipt_long_outlined, AcaoPermissao.realizarVenda, () => abrir(const HistoricoVendasPage())),

          _buildGroupTitle('CONSIGNAÇÃO'),
          _buildItem('Produtos consignados', 'Itens próprios de terceiros', Icons.handshake_outlined, AcaoPermissao.acessarConsignacao, () => abrir(const ProdutosLojaPage(modalidade: ModalidadeProduto.consignado))),
          _buildItem('Lotes e acertos', 'Maletas e devoluções', Icons.assignment_turned_in_outlined, AcaoPermissao.acessarConsignacao, () => abrir(const JoiasConsignadasPage())),

          _buildGroupTitle('REPOSIÇÃO'),
          _buildItem('Fornecedores', 'Cadastro e condições', Icons.local_shipping_outlined, AcaoPermissao.cadastrarFornecedor, () => abrir(const FornecedoresPage())),
          _buildItem('Estoque baixo', 'Alertas de quantidade', Icons.warning_amber, AcaoPermissao.visualizarEstoque, () => abrir(const ProdutosLojaPage(somenteBaixo: true))),
          _buildItem('Ordens de compra', 'Aprovação e recebimento', Icons.shopping_cart_checkout, AcaoPermissao.criarPedido, () => abrir(const OrdensCompraPage())),
          _buildItem('Comparador de reposição', 'Ofertas salvas', Icons.compare_arrows, AcaoPermissao.visualizarEstoque, () => abrir(const ComparadorReposicaoPage())),

          const Padding(
            padding: EdgeInsets.all(12),
            child: Card(
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Marketplaces externos'),
                subtitle: Text('A compra é concluída externamente. O StudioFlow não armazena senhas nem executa compra automática.'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
