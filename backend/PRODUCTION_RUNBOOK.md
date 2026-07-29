# StudioFlow — implantação real do backend (pré-homologação)

Este runbook não contém dados reais, senhas ou tokens. Substitua apenas no cofre de segredos do servidor. Nunca coloque valores secretos no APK, no repositório ou no `compose.yaml`.

## Arquitetura necessária

- Servidor Linux x86-64, Ubuntu 24.04 LTS, Docker Engine + Compose v2, 2 vCPU, 4 GB RAM e 40 GB SSD como mínimo para beta. Produção comercial: 4 vCPU, 8 GB RAM, monitoramento e atualizações automáticas de segurança.
- PostgreSQL 17. Preferência: instância gerenciada na mesma região do servidor, com TLS obrigatório, PITR e backup diário. Alternativa de beta: serviço `postgres:17-alpine` do Compose, volume dedicado e cópia externa dos backups.
- Domínio: `api-beta.SEUDOMINIO.com.br` para homologação e `api.SEUDOMINIO.com.br` para produção. Criar registro DNS A/AAAA para o IP público. Somente portas 80/443 públicas; PostgreSQL não deve ficar público.
- Proxy TLS: Caddy ou Nginx, certificado Let's Encrypt, encaminhando HTTPS para `api:8080`. `PUBLIC_BASE_URL` precisa ser exatamente a URL HTTPS pública.
- Armazenamento: bucket S3 privado, versionado, criptografado e com lifecycle. Use bucket separado para homologação. O backend atual mantém upload local como fallback; a ativação do S3 exige as variáveis abaixo e teste de restauração antes de dados reais.
- E-mail transacional: Resend. Verifique um subdomínio como `updates.SEUDOMINIO.com.br`, publique SPF/DKIM e crie uma chave restrita a envio. O backend envia diretamente para `https://api.resend.com/emails`.
- Catálogo GTIN: API universal Open Beauty Facts / Open Products Facts (`product_type=all`). A base é ODbL 1.0: exibir atribuição, respeitar share-alike da base derivada, usar `User-Agent` identificável e observar rate limits. O backend mantém cache positivo de 30 dias, negativo de 24 horas e logs por comércio/usuário.
- WhatsApp: Meta WhatsApp Cloud API oficial, WABA próprio, número dedicado e templates aprovados. Tokens ficam somente no cofre do backend.

## Contas e credenciais que o proprietário deve criar

1. Conta do provedor do servidor e um projeto exclusivo para o StudioFlow.
2. Domínio próprio e acesso ao DNS.
3. Banco PostgreSQL 17: banco `studioflow`, usuário de migração e usuário de runtime com senhas diferentes; URL TLS do runtime.
4. Bucket S3 privado e credencial limitada ao prefixo do StudioFlow.
5. Conta Resend, subdomínio verificado e API key `sending_access`.
6. Meta Business verificada, app Meta, WABA, número exclusivo, `PHONE_NUMBER_ID`, token permanente de System User, `APP_SECRET` e token aleatório de verificação do webhook.
7. Três templates Meta em `pt_BR`, todos com um parâmetro de corpo `{{1}}`: `studioflow_lembrete_dia_anterior`, `studioflow_lembrete_duas_horas` e `studioflow_aniversario`.
8. Endereço público e e-mail técnico para o `CATALOG_USER_AGENT`.
9. Segredos aleatórios: `JWT_SECRET` com no mínimo 64 caracteres, senha do PostgreSQL, `AUTOMATION_WEBHOOK_TOKEN` e chave administrativa ROLG.

## Variáveis de ambiente

Obrigatórias para API e sincronização:

```dotenv
DATABASE_URL=postgresql://studioflow_runtime:SENHA@HOST:5432/studioflow?sslmode=require
JWT_SECRET=SEGREDO_ALEATORIO_COM_64_OU_MAIS_CARACTERES
PUBLIC_BASE_URL=https://api-beta.SEUDOMINIO.com.br
PORT=8080
ACCESS_TOKEN_MINUTES=15
REFRESH_TOKEN_DAYS=30
PASSWORD_RESET_BASE_URL=https://app.SEUDOMINIO.com.br
```

E-mail:

```dotenv
EMAIL_PROVIDER_URL=https://api.resend.com/emails
EMAIL_PROVIDER_TOKEN=CRIAR_NO_RESEND_COM_PERMISSAO_SOMENTE_ENVIO
EMAIL_FROM=StudioFlow <acesso@updates.SEUDOMINIO.com.br>
```

Catálogo:

```dotenv
CATALOG_BASE_URL=https://world.openfoodfacts.org
CATALOG_USER_AGENT=StudioFlow/1.0 (https://SEUDOMINIO.com.br; suporte@SEUDOMINIO.com.br)
```

WhatsApp oficial:

```dotenv
WHATSAPP_GRAPH_API_VERSION=VERSAO_SUPORTADA_NO_MOMENTO_DA_IMPLANTACAO
WHATSAPP_PHONE_NUMBER_ID=CRIAR_NA_META
WHATSAPP_ACCESS_TOKEN=TOKEN_PERMANENTE_DO_SYSTEM_USER
WHATSAPP_VERIFY_TOKEN=SEGREDO_ALEATORIO_PARA_VERIFICACAO
META_APP_SECRET=APP_SECRET_DA_META
WHATSAPP_TEMPLATE_DAY_BEFORE=studioflow_lembrete_dia_anterior
WHATSAPP_TEMPLATE_TWO_HOURS=studioflow_lembrete_duas_horas
WHATSAPP_TEMPLATE_BIRTHDAY=studioflow_aniversario
```

Armazenamento:

```dotenv
UPLOAD_DIRECTORY=/app/storage
UPLOAD_MAX_BYTES=10485760
S3_ENDPOINT=https://ENDPOINT_DO_PROVEDOR
S3_BUCKET=studioflow-beta-private
S3_ACCESS_KEY=CHAVE_LIMITADA
S3_SECRET_KEY=SEGREDO_NO_COFRE
```

## Implantação exata

1. Crie dois ambientes isolados: homologação e produção. Comece somente pela homologação.
2. Copie `backend/` para o servidor e crie `.env` fora do controle de versão com permissão `600`.
3. Suba apenas o PostgreSQL, se não usar banco gerenciado: `docker compose up -d postgres`.
4. Execute as migrações com a mesma imagem da API e o usuário de migração: `docker compose run --rm api dart run bin/migrate.dart`.
5. Suba API e backup: `docker compose up -d api backup`.
6. Configure o proxy HTTPS e confirme `GET https://api-beta.SEUDOMINIO.com.br/health` com status 200.
7. No painel Meta, configure callback `https://api-beta.SEUDOMINIO.com.br/v1/webhooks/whatsapp`, informe `WHATSAPP_VERIFY_TOKEN`, assine o campo `messages` e faça um envio para número de teste com consentimento.
8. Confirme que os status `sent`, `delivered`, `read` e `failed/error` aparecem em `/v1/messages/history` autenticado.
9. Faça um login, push/pull e recuperação em um segundo aparelho de teste sem dados pessoais.
10. Reinicie a API, restaure um backup em banco separado e repita health/login/pull antes de homologar.

## Build do aplicativo para homologação online

O APK futuro deverá receber somente a URL pública, nunca segredos:

```powershell
flutter build apk --release --target-platform android-arm64 --dart-define=STUDIOFLOW_ENV=staging --dart-define=STUDIOFLOW_PUBLIC_BACKEND_URL=https://api-beta.SEUDOMINIO.com.br
```

Este comando é apenas instrução. A correção pré-homologação proíbe gerar o APK antes de todas as validações.

## Critérios de liberação em dois celulares

- Backend público HTTPS e migrações 001–005 aplicadas.
- Primeiro aparelho autenticado online e sincronização sem pendências/conflitos.
- Segundo aparelho reinstalado, login online, restauração completa e comparação de contagens.
- Cancelamento no aparelho A cancela mensagens no backend antes do worker e aparece no B.
- Alteração simultânea gera conflito auditável, sem perda silenciosa.
- Templates Meta aprovados, consentimento presente e webhook validado.
- Backup PostgreSQL restaurado com sucesso em ambiente descartável.

Sem servidor e credenciais de homologação, o código está preparado, mas o sistema não pode ser declarado pronto para teste real em dois celulares.