# Homologação comercial obrigatória — Sprint 8

Esta etapa deve ser executada em três estabelecimentos reais, cada um com ID próprio, durante um dia completo de operação. Não reutilize contas ou bancos entre os salões.

## Preparação

- [ ] Instalar o APK 1.4.0+4009 nos aparelhos.
- [ ] Aplicar a migração PostgreSQL 004 no backend de produção.
- [ ] Configurar HTTPS e as três variáveis AUTOMATION_PROVIDER_* no cofre.
- [ ] Criar três estabelecimentos distintos e confirmar login permanente.
- [ ] Fazer uma cópia de segurança antes do início do dia.
- [ ] Registrar horário, aparelho, versão Android e responsável de cada salão.

## Cenário mínimo em cada salão

- [ ] Cadastrar ou editar profissionais e clientes.
- [ ] Criar atendimentos para o mesmo dia e para o dia seguinte.
- [ ] Confirmar, reagendar e cancelar atendimentos.
- [ ] Criar recorrência, bloqueio e tentativa de conflito.
- [ ] Vender pacote, agendar sessões e concluir somente a sessão realizada.
- [ ] Registrar falta/cancelamento de sessão e conferir devolução/consumo conforme regra.
- [ ] Cadastrar produto por scanner e por catálogo; usar manual apenas como fallback.
- [ ] Fazer entrada, saída, inventário e transferência entre operacional e loja.
- [ ] Vender produto da loja e conferir baixa; validar consignado separadamente.
- [ ] Abrir Comprar Agora e conferir ordenação por preço, avaliação, prazo e frete.
- [ ] Conferir lembrete das 16h e lembrete de duas horas antes.
- [ ] Conferir aniversário da proprietária às 8h e da cliente às 9h.
- [ ] Confirmar que a mesma cliente não recebe aniversário duas vezes no ano.
- [ ] Abrir a central de aniversários e testar todas as ações.
- [ ] Fechar e reabrir o aplicativo durante o dia; confirmar sessão e dados.
- [ ] Operar temporariamente offline, reconectar e conferir sincronização.

## Evidências por salão

- [ ] Captura do painel no início e no fim do dia.
- [ ] Contagem inicial/final de clientes, agenda, pacotes e estoque.
- [ ] IDs de mensagens e status de entrega no histórico.
- [ ] Registro dos cancelamentos e reagendamentos.
- [ ] Registro de conflitos ou erros, com horário.
- [ ] Exportação ou consulta final confirmando que nenhum dado sumiu.

## Critério de aprovação

Aprovar apenas se os três salões completarem o dia, nenhuma informação for perdida, os lembretes e aniversários forem entregues pelo provedor real, e os módulos de pacotes, estoque, agenda e persistência permanecerem consistentes. Qualquer falha deve ser registrada e corrigida antes de encerrar a Sprint 8. Não iniciar escopo posterior automaticamente.
