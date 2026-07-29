# Relatório técnico — StudioFlow Sprint 8

Data técnica da entrega: 29/07/2026
Versão: 1.4.0+4009
SQLite: versão 12
Plataforma do APK: Android ARM64-v8a release

## Resultado

A implementação técnica da Sprint 8 foi concluída, compilada e validada por testes automatizados. A homologação comercial obrigatória de três salões usando o sistema durante um dia inteiro permanece pendente, pois depende de instalação, pessoas e operação real fora do ambiente de desenvolvimento. A Sprint 9 não foi iniciada.

## Implementado

- Worker de mensagens no backend, independente do aplicativo aberto.
- Lembrete do dia seguinte agendado diariamente para 16h.
- Segundo lembrete exatamente duas horas antes do atendimento.
- Variáveis de cliente, estabelecimento, profissional, serviço, data, hora, localização, confirmação, reagendamento e cancelamento.
- Modelos automáticos editáveis por estabelecimento e sincronizados.
- Fila PostgreSQL com idempotência, tentativas, retentativa exponencial, erro terminal e histórico de entrega.
- Webhook autenticado para status enviado, entregue, lido ou erro.
- Isolamento RLS: worker usa contexto administrativo somente dentro de transações; histórico usa o comércio autenticado.
- Alerta de aniversariantes para a proprietária às 8h.
- Mensagem automática para a cliente às 9h, sem duplicidade no mesmo ano.
- Central de aniversários no menu Mais, com idade, tempo como cliente, último atendimento, valor gasto e serviços favoritos.
- Ações de WhatsApp, parabéns, cupom/desconto, presente, link de imagem/agendamento, ligação e agendamento de contato.
- Contato agendado persistente no SQLite.
- Histórico de mensagens automáticas acessível na tela de modelos, com destino mascarado, status, horário, tentativas e erro.
- Mensagem clara quando backend ou provedor externo não estiver configurado.
- Auditoria confirmou os módulos já existentes de pacotes, estoque operacional/loja/consignado, scanner EAN/GTIN/UPC/QR, compras/afiliados, agenda e persistência; eles foram preservados e cobertos pela regressão.

## Arquivos criados

- backend/lib/src/automations.dart
- backend/migrations/004_message_automations.sql
- backend/test/automations_test.dart
- lib/database/migrations/migration_v12.dart
- lib/repositories/aniversarios_repository.dart
- lib/screens/aniversarios_page.dart
- test/sprint8_test.dart
- HOMOLOGACAO_COMERCIAL_SPRINT_8.md
- RELATORIO_SPRINT_8.md

## Arquivos alterados

- backend/bin/server.dart
- backend/lib/studioflow_backend.dart
- backend/lib/src/api.dart
- backend/lib/src/config.dart
- backend/.env.example
- backend/README.md
- lib/core/constants/database_constants.dart
- lib/database/database_schema_latest.dart
- lib/models/domain/mensagem_modelo.dart
- lib/screens/mais_sprint2_page.dart
- lib/screens/modelos_mensagens_page.dart
- lib/services/backend_api_client.dart
- lib/services/backend_sync_service.dart
- lib/services/external_action_service.dart
- lib/services/mensagem_service.dart
- pubspec.yaml

## Migrações

- PostgreSQL 004_message_automations.sql: outbound_messages, message_delivery_attempts, índices, idempotência e políticas RLS.
- SQLite v12: contatos_agendados e índice de pendências; antes do upgrade, cria backup lógico de clientes sem apagar registros.

## Validação

- flutter pub get: aprovado.
- dart format: aprovado.
- flutter analyze: aprovado, nenhum problema.
- flutter test: 85 testes aprovados.
- dart analyze do backend: aprovado, nenhum problema.
- dart test do backend: 13 testes aprovados.
- Simulação automatizada de três estabelecimentos: aprovada com isolamento de aniversários e automações.
- Regressão de pacotes: aprovada.
- Regressão de estoque, fornecedores, consignação, vendas e transferência: aprovada.
- Regressão de agenda, conflitos, cancelamento, reagendamento, recorrência/bloqueios e histórico: aprovada.
- Regressão de sessão, persistência offline e sincronização: aprovada.
- Build release ARM64: aprovado.

## APK

Caminho: D:\projeto salao\studioflow\artifacts\apk\StudioFlow-1.4.0-4009-arm64-v8a-release.apk
Tamanho: 35.382.533 bytes (33,7 MB no relatório do Flutter)
SHA-256: D35815CBF53426F7E117D41608CF8A704F1E97ECDAB5F08E32E3225217BDDFB5

## Instalação no aparelho de homologação

- Atualizado via ADB sem desinstalação e sem limpeza de dados.
- Pacote: com.example.studioflow.
- Versão exibida: 1.4.0.
- versionCode Android instalado: 6009 (inclui o deslocamento da ABI arm64 aplicado pelo split APK).
- firstInstallTime permaneceu em 13/07/2026, confirmando preservação da instalação.
- Processo iniciou sem FATAL EXCEPTION, SQLiteException ou E/flutter.

## Configuração necessária no backend de produção

1. Executar `dart run bin/migrate.dart` para aplicar a migração 004.
2. Definir DATABASE_URL e JWT_SECRET em cofre de segredos.
3. Definir AUTOMATION_PROVIDER_URL, AUTOMATION_PROVIDER_TOKEN e AUTOMATION_WEBHOOK_TOKEN em cofre de segredos.
4. Manter o processo do backend ativo continuamente.
5. Configurar HTTPS e monitoramento.

Nenhuma senha, token ou chave foi inserida no código. Sem um provedor real configurado, mensagens não são falsamente marcadas como enviadas: ficam com erro claro e retentativas no histórico.

## Avisos não bloqueantes do build

- O APK esta em modo release AOT, mas foi assinado pelo fallback Android Debug porque nao existe key.properties nem credenciais STUDIOFLOW_KEY_* no ambiente. Ele serve para instalacao e homologacao, mas nao deve ser publicado na Play Store. A chave comercial deve ser fornecida e mantida em cofre, fora do projeto.

- Flutter informou futura migração de plugins que ainda aplicam Kotlin Gradle Plugin (mobile_scanner e share_plus).
- As versões atuais compilam; a atualização deve ser planejada antes de uma futura versão do Flutter remover esse suporte.
- Houve aviso de diferença de versão XML entre Android Studio e command-line tools, sem impacto no APK gerado.

## Espaço em disco ao final

- C: 0,72 GB livres — crítico; evitar novos builds neste disco.
- D: 226,14 GB livres — build e artefatos mantidos aqui.

## Pendência externa obrigatória

Executar o roteiro HOMOLOGACAO_COMERCIAL_SPRINT_8.md em três salões durante um dia inteiro. Somente após receber os registros e confirmar ausência de perda de dados a Sprint 8 poderá ser considerada comercialmente encerrada. Até lá, o resultado é “implementação técnica aprovada; homologação de campo pendente”.
