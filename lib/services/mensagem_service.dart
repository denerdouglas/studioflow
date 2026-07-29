import '../models/domain/mensagem_modelo.dart';

class MensagemService {
  const MensagemService();

  String montar(String modelo, DadosMensagem dados) {
    final servicos = _servicos(dados.servicos);
    final produtos = _produtos(dados.produtos);
    final pendente = dados.valorPendente;
    final secaoServicos = dados.servicos.isEmpty
        ? ''
        : 'Serviços realizados:\n$servicos\n\nTotal dos serviços:\nR\$ ${_moeda(dados.totalServicos)}\n\n';
    final secaoProdutos = dados.produtos.isEmpty
        ? ''
        : 'Produtos adquiridos:\n$produtos\n\nTotal dos produtos:\nR\$ ${_moeda(dados.totalProdutos)}\n\n';
    final valores = <String, String>{
      '[cliente]': dados.cliente,
      '[salao]': dados.salao,
      '[servico]': dados.servico,
      '[localizacao]': dados.endereco,
      '[salão]': dados.salao,
      '[data]': dados.data,
      '[hora]': dados.hora,
      '[profissional]': dados.profissional,
      '[serviço]': dados.servico,
      '[lista_servicos]': servicos,
      '[lista_produtos]': produtos,
      '[quantidade_produtos]': dados.produtos
          .fold<int>(0, (t, i) => t + i.quantidade)
          .toString(),
      '[total_servicos]': _moeda(dados.totalServicos),
      '[total_produtos]': _moeda(dados.totalProdutos),
      '[total_geral]': _moeda(dados.totalGeral),
      '[valor_pago]': _moeda(dados.valorPago),
      '[valor_pendente]': _moeda(pendente),
      '[forma_pagamento]': dados.formaPagamento,
      '[valor_sinal]': _moeda(dados.valorSinal),
      '[pix]': dados.pix,
      '[nome_recebedor]': dados.nomeRecebedor,
      '[banco]': dados.banco,
      '[endereço]': dados.endereco,
      '[ponto_referencia]': dados.pontoReferencia,
      '[link_rota]': dados.linkRota,
      '[telefone_salao]': dados.telefoneSalao,
      '[secao_servicos]': secaoServicos,
      '[secao_produtos]': secaoProdutos,
      '[status_pagamento]': pendente > 0
          ? 'Valor pendente: R\$ ${_moeda(pendente)}'
          : 'Pagamento concluído.',
    };
    var texto = modelo;
    for (final item in valores.entries) {
      texto = texto.replaceAll(item.key, item.value);
    }
    return texto.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  String _servicos(List<ItemResumoMensagem> itens) => itens
      .map((item) {
        final profissional = item.profissional.trim().isEmpty
            ? ''
            : ' — ${item.profissional}';
        final desconto = item.desconto > 0
            ? ' (desconto R\$ ${_moeda(item.desconto)})'
            : '';
        return '${item.nome}$profissional — R\$ ${_moeda(item.subtotal)}$desconto';
      })
      .join('\n');

  String _produtos(List<ItemResumoMensagem> itens) => itens
      .map((item) {
        return '${item.quantidade}x ${item.nome} — R\$ ${_moeda(item.subtotal)}';
      })
      .join('\n');

  String _moeda(double valor) => valor.toStringAsFixed(2).replaceAll('.', ',');
}
