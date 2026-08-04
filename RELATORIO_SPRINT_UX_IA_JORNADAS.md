# Relatório — UX, colaboradores, jornadas e IA operacional

Data: 04/08/2026
Escopo: conclusão exclusivamente local, sem VPS, deploy, APK, AAB, push ou alteração de versão do aplicativo.

## Implementado nesta Sprint

- Helloa Sophia passou a distinguir consulta de comando operacional e a exigir prévia e confirmação antes de gravar ou disparar ações.
- Lembrete em massa consulta a agenda real, valida telefone e consentimento, usa `WhatsappQueueService`, evita duplicidade, informa pendentes/falhas/ignorados e registra auditoria.
- Comandos locais criam itens/lotes de estoque, aumentam quantidade, criam serviços e vínculos profissionais, cadastram colaboradores com várias funções e registram saída financeira.
- Todas as gravações operacionais respeitam permissões, transação, idempotência e fila oficial de sincronização offline.
- Funções profissionais múltiplas e personalizadas foram separadas do perfil de acesso legado.
- A disponibilidade passou a exibir um card por profissional, selecionar vários dias e usar seletor visual para entrada, saída e intervalo.
- A Central de Atendimento passou a abrir a tela real de agendamento público, removendo do fluxo de produção a antiga tela de rascunho.
- Migração local V27 adiciona funções profissionais, vínculos função/profissional e função/serviço, controle idempotente de comandos e lotes criados pela IA.

## Já existente e apenas validado

- Motor de disponibilidade real com jornada, intervalo, duração do serviço, profissional habilitado, agendamentos e bloqueios.
- Cadastro e edição de colaboradores e serviços, relação muitos-para-muitos entre profissionais e serviços e importação do catálogo interno.
- Agendamento público real, incluindo criação, confirmação, cancelamento, reagendamento, conflito, idempotência e sincronização principal.
- Componente global de menu contextual: toque simples, pressão longa nativa, clique direito, teclado e feedback tátil.
- Política de cancelamento e configuração controlada de sinal, sem apresentar integração financeira inexistente como ativa.

## Dependência externa pendente

- O teste PostgreSQL descartável foi corretamente ignorado porque `POSTGRES_TEST_URL` não está configurada. Nenhum resultado positivo foi declarado para essa suíte.
- Envio efetivo pelo provedor WhatsApp depende das credenciais/configuração externa; localmente a operação entra na fila oficial real.

## Indisponível ou oculto em produção

- A tela legada que gerava “token do rascunho” continua no código apenas por compatibilidade, mas não é mais acessada pela Central de Atendimento.
- Pagamento de sinal permanece controlado pela configuração existente e não é apresentado como processado sem integração operacional.

## Validação executada

- `flutter analyze`: aprovado, sem ocorrências.
- `flutter test`: aprovado, 146 testes.
- `backend: dart analyze`: aprovado, sem ocorrências.
- `backend: dart test`: aprovado, 44 testes e 1 teste PostgreSQL ignorado por ausência de `POSTGRES_TEST_URL`.
- Teste direcionado novo: 7 cenários aprovados.

## Entrega e restrições respeitadas

- `pubspec.yaml` permanece em `1.4.7+4018`.
- Nenhum APK/AAB foi gerado.
- Nenhum acesso à VPS, deploy, push ou publicação na Play Store foi realizado.
