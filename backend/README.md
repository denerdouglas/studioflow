# StudioFlow Backend — Sprint 7 / Fase 1

Backend Dart separado do aplicativo Flutter, com API REST, PostgreSQL,
isolamento por estabelecimento, JWT curto, refresh token rotativo, auditoria e
sincronização offline-first.

## Segurança

- Segredos são lidos exclusivamente do ambiente.
- Senhas usam BCrypt com custo 12.
- Refresh tokens são opacos, rotacionados e armazenados somente como SHA-256.
- Todas as entidades sincronizadas carregam `business_id`.
- PostgreSQL possui Row Level Security como segunda barreira.
- Operações de sincronização são idempotentes por `operation_id`.
- Conflitos usam versão otimista e nunca sobrescrevem silenciosamente.

## Execução local

É necessário PostgreSQL 15 ou superior. Copie `.env.example` apenas como
referência e defina as variáveis no processo; não grave segredos no projeto.

```powershell
cd backend
$env:DATABASE_URL='postgresql://usuario:senha@localhost:5432/studioflow'
$env:JWT_SECRET='<64 ou mais caracteres aleatórios>'
dart pub get
dart run bin/migrate.dart
dart run bin/server.dart
```

`GET /health` deve responder `status: ok`.

## Rotas iniciais

- `POST /v1/auth/register-business`
- `POST /v1/auth/login`
- `POST /v1/auth/refresh`
- `POST /v1/auth/logout`
- `POST /v1/auth/password/request`
- `POST /v1/auth/password/reset`
- `POST /v1/sync/push`
- `GET /v1/sync/pull?cursor=0&limit=200`
- `GET /v1/marketplace/offers?q=produto`
- `POST /v1/marketplace/offers/<id>/click`
- `GET|PUT /v1/admin/affiliate/programs[/<id>]`
- `PUT /v1/admin/marketplace/offers/<id>`
- `POST /v1/admin/affiliate/conversions`
- `GET /v1/admin/affiliate/metrics`
- `GET /v1/messages/history`
- `POST /v1/webhooks/messages`

As rotas administrativas exigem `ROLG_ADMIN_KEY` no servidor e o cabeçalho
`x-rolg-admin-key`. Tokens dos marketplaces não são aceitos nas rotas nem
persistidos; o banco guarda somente `secret_reference`, apontando para o cofre.
Ofertas só são publicadas quando possuem URL HTTPS e programa habilitado. Um
clique é uma métrica independente e nunca cria conversão automaticamente.

Se um login pertencer a mais de um comércio, `/auth/login` devolve
`selectionRequired: true`; a segunda chamada inclui `businessId`.

## Deploy

`compose.yaml` oferece PostgreSQL, API e backup diário. Antes de produção:

1. configure TLS no proxy reverso;
2. use um cofre de segredos;
3. crie usuários distintos para migração, runtime e backup;
4. execute as migrações no pipeline;
5. teste restauração dos backups;
6. configure observabilidade, retenção e alertas;
7. configure provedores de e-mail/SMS, Meta e armazenamento de objetos.

O armazenamento local do container serve apenas a desenvolvimento. Produção
deve usar um provedor de objetos S3 compatível com versionamento e retenção.

## Automação de mensagens — Sprint 8

O worker roda no processo do backend e não depende do aplicativo aberto. Ele agenda lembretes do dia seguinte às 16h, lembretes duas horas antes, alerta a proprietária às 8h e envia aniversário à cliente às 9h, no horário de Brasília. A chave anual impede mensagem de aniversário duplicada.

Antes do deploy, execute `dart run bin/migrate.dart` para aplicar `004_message_automations.sql` e configure `AUTOMATION_PROVIDER_URL`, `AUTOMATION_PROVIDER_TOKEN` e `AUTOMATION_WEBHOOK_TOKEN` no cofre do ambiente. Sem provedor configurado, o worker mantém o histórico e registra erro claro com retentativas, sem simular envio.