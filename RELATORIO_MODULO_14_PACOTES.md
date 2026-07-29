# StudioFlow — Relatório final do módulo 14

Data da validação: 29/07/2026  
Versão: `1.3.0+2011`  
Banco SQLite: versão 11

## Resultado

O módulo de Pacotes de Serviços e Agendamento Automático foi implementado
sem remover cadastros ou funcionalidades existentes. A migração é aditiva,
gera backup lógico antes do upgrade e mantém isolamento por comércio.

## Funcionalidades implementadas

- Modelos de pacote com um ou vários serviços, quantidades, ordem livre ou
  obrigatória, preço próprio, desconto calculado, validade, intervalos,
  duração, profissionais autorizados, parcelamento, sinal, regras de falta,
  comissão, transferência, observações e status.
- Venda vinculada obrigatoriamente ao cliente e vendedor, com valor
  contratado, pago e pendente, parcelas, sinal, forma de pagamento,
  referência de comanda e validade calculada.
- Saldo individual por venda. A venda cria créditos disponíveis, mas não
  consome sessões.
- Prévia de agendamento automático semanal, mensal ou por intervalo de dias.
  O cálculo respeita jornada, pausa, bloqueios, duração, conflitos, ordem,
  profissional autorizado e validade.
- Confirmação explícita antes de gravar os agendamentos, com indicação de
  horários alternativos e sessões não encaixadas.
- Reagendamento de uma sessão ou das próximas, troca de profissional e
  revalidação de jornada/conflitos, sem duplicar sessões ou agendamentos.
- Cancelamento de agendamento devolve o crédito não consumido; pacote pode
  ser pausado, retomado, cancelado, prorrogado ou transferido conforme regra.
- Baixa de crédito somente na conclusão do atendimento. Operação idempotente:
  concluir novamente não consome outro crédito.
- Regras de falta: manter, consumir, consumir parcialmente ou exigir
  aprovação administrativa.
- Financeiro integrado aos pagamentos efetivamente recebidos. Concluir
  sessões não cria nova receita.
- Comissões de vendedor e executor conforme modo integral, por sessão ou
  dividido, com prevenção de duplicidade.
- Materiais por serviço e baixa de estoque somente na conclusão da sessão.
  Estoque insuficiente bloqueia a conclusão.
- Alertas locais de vencimento e pagamento pendente; pacotes vencidos e
  créditos vencidos são atualizados no SQLite.
- Relatório local de vendas, valores recebidos/pendentes e situação das
  sessões.
- Área “Pacotes” no perfil 360 do cliente, com progresso, valores, validade e
  saldos.
- Fila offline para modelos, vendas e alterações de agenda, preparada para
  sincronização posterior.
- Auditoria das operações sensíveis.
- Onze permissões específicas, concedidas automaticamente ao dono e
  configuráveis individualmente para gerente/colaborador.

## Migração v11

Tabelas criadas:

- `pacotes_servicos`
- `pacote_servico_itens`
- `pacote_item_profissionais`
- `servico_materiais`
- `pacote_vendas`
- `pacote_venda_sessoes`
- `pacote_parcelas`
- `pacote_pagamentos`
- `pacote_comissoes`
- `pacote_auditoria`
- `pacote_alertas`

Campo adicionado:

- `agendamentos.pacote_venda_sessao_id`

O upgrade v10 → v11 executa backup lógico de serviços, agenda, financeiro,
comissões, estoque, movimentações e fila de sincronização antes das mudanças.

## Arquivos criados

- `lib/database/migrations/migration_v11.dart`
- `lib/models/domain/pacote_servico.dart`
- `lib/repositories/pacotes_repository.dart`
- `lib/screens/pacotes_page.dart`
- `test/sprint14_pacotes_test.dart`
- `test/sprint14_migration_test.dart`
- `RELATORIO_MODULO_14_PACOTES.md`

## Arquivos alterados

- `pubspec.yaml`
- `lib/core/constants/database_constants.dart`
- `lib/database/database_schema_latest.dart`
- `lib/models/domain/acesso.dart`
- `lib/repositories/agenda_repository.dart`
- `lib/repositories/agenda_completa_repository.dart`
- `lib/screens/mais_page.dart`
- `lib/screens/clientes_360_page.dart`

## Validação

- `flutter pub get`: concluído.
- `dart format`: concluído nos arquivos alterados.
- `flutter analyze`: **sem problemas**.
- Testes novos do módulo: **34 aprovados** (33 funcionais + 1 migração).
- Regressão completa: **82/82 testes aprovados**.
- Build: `flutter build apk --release --target-platform android-arm64 --split-per-abi`
  concluído.
- Arquitetura inspecionada dentro do APK: **somente `arm64-v8a`**.
- Tamanho: **35.382.261 bytes (33,74 MB)**.
- SHA-256:
  `BC62E33F1AB693D571414691976417FD57389A75A8E289556B0D4ED68EE95E3A`

## Como testar no celular

1. Instale o APK e entre com um comércio existente ou faça o primeiro
   cadastro.
2. Cadastre ao menos um cliente, serviço e profissional com jornada.
3. Abra **Mais recursos → Pacotes**.
4. Crie um modelo, selecione serviços/quantidades e informe preço/validade.
5. Use **Vender este pacote**, registre o pagamento e escolha **Agendar**.
6. Revise a prévia e confirme os horários.
7. Conclua o atendimento pela agenda e verifique saldo, financeiro,
   comissão e estoque.
8. Abra o perfil 360 do cliente para conferir o progresso do pacote.

## Limitações externas e de distribuição

- WhatsApp oficial e e-mail estão preparados como canais, mas o envio real
  exige provedores/backend configurados; nenhuma chave foi embutida no app.
- A integração com comanda usa uma referência auditável porque o projeto
  atual ainda não possui uma tabela única de comandas.
- O ambiente não possui credenciais privadas de publicação. O APK é release
  AOT, mas usa o fallback de assinatura debug já previsto no projeto; serve
  para instalação e homologação, não para publicação definitiva na Play
  Store.
- R8/minificação permanece desativado conforme a configuração de build já
  adotada no projeto para evitar falhas de memória/disco neste notebook.
- O build exibiu avisos não bloqueantes sobre futura migração de plugins para
  Kotlin integrado e diferença de versão XML das ferramentas Android.

Nenhum módulo posterior foi iniciado.

## APK

`D:\projeto salao\studioflow\artifacts\apk\StudioFlow-1.3.0-2011-arm64-v8a-release.apk`
