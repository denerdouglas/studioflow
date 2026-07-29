import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/utils/id_generator.dart';
import '../database/database_service.dart';
import '../models/domain/loja.dart';
import '../services/session_controller.dart';

abstract interface class MarketplaceProvider {
  String get nome;
  Future<List<OfertaReposicao>> pesquisar(String termo);
  Future<bool> abrirPesquisa(String termo);
  Future<bool> abrirOferta(String link);
}

abstract class PesquisaExternaProvider implements MarketplaceProvider {
  Uri uriPesquisa(String termo);

  @override
  Future<List<OfertaReposicao>> pesquisar(String termo) async => const [];

  @override
  Future<bool> abrirPesquisa(String termo) async {
    final uri = uriPesquisa(termo);
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return true;
    return launchUrl(uri, mode: LaunchMode.platformDefault);
  }

  @override
  Future<bool> abrirOferta(String link) async {
    final uri = Uri.tryParse(link);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) return false;
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return true;
    return launchUrl(uri, mode: LaunchMode.platformDefault);
  }
}

class MercadoLivreProvider extends PesquisaExternaProvider {
  @override
  String get nome => 'Mercado Livre';

  @override
  Uri uriPesquisa(String termo) => Uri.https(
    'lista.mercadolivre.com.br',
    '/${Uri.encodeComponent(termo.trim()).replaceAll('%20', '-')}',
  );
}

class ShopeeProvider extends PesquisaExternaProvider {
  @override
  String get nome => 'Shopee';

  @override
  Uri uriPesquisa(String termo) =>
      Uri.https('shopee.com.br', '/search', {'keyword': termo.trim()});
}

class FornecedorLocalProvider implements MarketplaceProvider {
  final DatabaseService databaseService;
  FornecedorLocalProvider({DatabaseService? databaseService})
    : databaseService = databaseService ?? DatabaseService.instance;

  @override
  String get nome => 'Fornecedores locais';

  @override
  Future<List<OfertaReposicao>> pesquisar(String termo) async {
    final usuario = SessionController.instance.usuario;
    if (usuario == null) return const [];
    final Database db = await databaseService.database;
    final maps = await db.rawQuery(
      '''SELECT pf.*, e.nome produto_nome,
      f.nome fornecedor_nome FROM produto_fornecedores pf
      JOIN estoque e ON e.id = pf.produto_id
      JOIN fornecedores f ON f.id = pf.fornecedor_id
      WHERE pf.comercio_id = ? AND f.ativo = 1
        AND (e.nome LIKE ? OR e.marca LIKE ? OR pf.codigo_fornecedor LIKE ?)''',
      [
        usuario.comercioId,
        '%${termo.trim()}%',
        '%${termo.trim()}%',
        '%${termo.trim()}%',
      ],
    );
    return maps
        .map(
          (m) => OfertaReposicao(
            id: 'local_${m['produto_id']}_${m['fornecedor_id']}',
            plataforma: nome,
            titulo: '${m['produto_nome']} — ${m['fornecedor_nome']}',
            quantidadeEmbalagem: (m['quantidade_embalagem'] as num).toDouble(),
            preco: (m['preco_recente'] as num).toDouble(),
            frete: 0,
            prazoDias: m['prazo_dias'] as int?,
            vendedor: m['fornecedor_nome'] as String,
            link: m['link'] as String?,
            habitual: true,
          ),
        )
        .toList();
  }

  @override
  Future<bool> abrirPesquisa(String termo) async => false;

  @override
  Future<bool> abrirOferta(String link) async {
    final uri = Uri.tryParse(link);
    if (uri == null) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class StudioFlowProvider implements MarketplaceProvider {
  @override
  String get nome => 'Loja StudioFlow (futuro)';
  @override
  Future<List<OfertaReposicao>> pesquisar(String termo) async => const [];
  @override
  Future<bool> abrirPesquisa(String termo) async => false;
  @override
  Future<bool> abrirOferta(String link) async => false;
}

OfertaReposicao ofertaManual({
  required String plataforma,
  required String titulo,
  required double preco,
  required double frete,
  required double quantidadeEmbalagem,
  int? prazoDias,
  String? link,
}) => OfertaReposicao(
  id: IdGenerator.temporal(),
  plataforma: plataforma,
  titulo: titulo,
  quantidadeEmbalagem: quantidadeEmbalagem,
  preco: preco,
  frete: frete,
  prazoDias: prazoDias,
  link: link,
);
