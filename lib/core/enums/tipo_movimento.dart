enum TipoMovimento {
  entrada,
  saidaManual,
  ajuste,
  inventario,
  perda,
  avaria,
  quebra,
  derramamento,
  vencimento,
  contaminacao,
  extravio,
  transferencia,
  venda,
  vendaManual,
  consumoInterno,
  devolucao,
  recebimentoConsignado,
  devolucaoConsignada,
  cancelamentoVenda;

  String get chave => name;

  bool get isEntrada => const {
        TipoMovimento.entrada,
        TipoMovimento.inventario, // inventário default
        TipoMovimento.devolucao,
        TipoMovimento.recebimentoConsignado,
        TipoMovimento.cancelamentoVenda,
      }.contains(this);
}
