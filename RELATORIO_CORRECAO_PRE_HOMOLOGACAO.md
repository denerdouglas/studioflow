# StudioFlow — relatório da correção final pré-homologação

Data: 29/07/2026

Escopo: correção pré-homologação. Nenhuma Sprint 10/11 foi iniciada e nenhum APK foi gerado.

## Concluído no código

1. Anamnese completa: formulário por cliente, tipos de ficha, campos de saúde e preferências, detalhes condicionais, validação, confirmação, autorização, assinatura declaratória, usuário/data, vínculo multiempresa e histórico imutável por versões.
2. Cancelamento de agenda: motivo obrigatório, auditoria no histórico, integração com pacotes e cancelamento transacional de notificações/WhatsApp locais pendentes.
3. Exclusão de agenda: permissão granular `excluirAgendamento`, confirmação e motivo, diagnóstico de vínculos financeiros/comissões/cobranças/pacotes, bloqueio quando houver vínculo, exclusão lógica, snapshot e auditoria permanente. Os atalhos antigos de exclusão/cancelamento direto foram desativados.
4. Backend: configuração por ambiente, Compose, PostgreSQL 17, migração 005, cache/log GTIN, templates WhatsApp, webhook Meta assinado, e-mail Resend, runbook de servidor/DNS/banco/armazenamento/segredos.
5. Login: o login principal tenta autenticação online quando o APK possui `STUDIOFLOW_PUBLIC_BACKEND_URL`; após falha de rede, o offline só é liberado se a senha tiver sido validada pelo hash local. Um login online válido reconstrói a conta local após reinstalação e guarda tokens no armazenamento seguro.
6. Sincronização: push/pull autenticado, refresh rotativo, fila offline, recuperação do cursor, restauração simulada pós-reinstalação e cancelamento imediato das mensagens do agendamento no próprio push.
7. GTIN: consulta real somente pelo backend à API universal Open Beauty Facts/Open Products Facts, validação do código, `User-Agent`, timeout, cache positivo/negativo, logs, distinção entre ausente e indisponível, atribuição ODbL e preenchimento de nome, marca, categoria, descrição, imagem e volume.
8. WhatsApp oficial: consentimento obrigatório no worker, envio por template da Cloud API, token somente no backend, retries, idempotência, cancelamento de pendências, verificação GET do webhook, validação HMAC `X-Hub-Signature-256` e estados `sent/delivered/read/error`.

## Migrações

- SQLite v13: backup lógico de `anamneses` e `agendamentos`; versão/auditoria da anamnese; exclusão lógica da agenda; tabela `agendamento_exclusoes`; vínculo de fila WhatsApp ao agendamento; índices.
- PostgreSQL 005: `catalog_gtin_cache`, `catalog_gtin_logs`, `whatsapp_templates`, índices, RLS e registro em `schema_migrations`.

## Validação executada no disco D:

- `flutter pub get`: concluído.
- `dart pub get` no backend: concluído.
- `dart format --output=none --set-exit-if-changed lib test backend`: 192 arquivos verificados, 0 alterações.
- `flutter analyze --no-pub`: `No issues found`.
- `flutter test --no-pub`: 90 testes aprovados.
- `dart test` no backend: 20 testes aprovados.
- Docker/PostgreSQL local: não executado porque Docker não está instalado nesta máquina. A migração PostgreSQL ainda precisa ser aplicada em homologação.
- Build APK: deliberadamente não executado, conforme a ordem recebida.

## Bloqueado por infraestrutura/credenciais

- Implantação HTTPS real e aplicação da migração PostgreSQL 005.
- Teste físico de sincronização/restauração em dois celulares.
- Criação e aprovação dos templates Meta, WABA, número, token e webhook público.
- Conta Resend, domínio SPF/DKIM e chave restrita de envio.
- Bucket S3 e credenciais limitadas.
- DNS dos domínios beta/produção.
- Definição do `CATALOG_USER_AGENT` real e aceite operacional das obrigações ODbL.

## Estado para dois celulares

O código e os testes simulados estão preparados, mas o sistema **ainda não está pronto para ser declarado homologado em dois celulares reais**. Falta implantar o backend de homologação, aplicar as migrações, compilar um futuro APK com a URL HTTPS pública e executar o roteiro físico de comparação/sincronização/restauração.

Instruções completas: `backend/PRODUCTION_RUNBOOK.md`.