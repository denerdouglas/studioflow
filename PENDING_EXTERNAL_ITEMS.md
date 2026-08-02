# Itens Externos Pendentes (StudioFlow V1.0)

Para que a aplicação seja 100% operacional sem fallback ou recusa, as seguintes credenciais reais e recursos externos precisarão ser injetados pelo cliente em produção.

## 1. Meta / WhatsApp Cloud API
Os templates e envios estão implementados via automação (`backend/lib/src/automations.dart`).
**Pendência:**
- Cadastrar número oficial no Meta for Developers.
- Configurar webhook apontando para `https://[SUA_URL]/v1/webhooks/whatsapp`.
- Fornecer `STUDIOFLOW_WHATSAPP_PHONE_ID`.
- Fornecer `STUDIOFLOW_WHATSAPP_ACCESS_TOKEN`.
- Submeter e aprovar os templates de mensagem (`agendamento_criado`, `agendamento_cancelado`, etc).

## 2. Provedor GTIN (Catálogo de Código de Barras)
A `OfficialProductCatalogProvider` foi modelada e está acoplada à estrutura.
**Pendência:**
- Definir qual provedor final será consumido no backend (ex: Cosmos, GS1, etc.).
- Informar chave de API `STUDIOFLOW_GTIN_API_KEY` ao backend.

## 3. Hospedagem Backend e Domínio
As URLs precisam de HTTPS.
**Pendência:**
- Implantar backend no provedor definitivo (ex: AWS, Google Cloud, DigitalOcean).
- Apontar domínio (ex: api.meusalao.com.br).
- Substituir o uso da flag `--dart-define=STUDIOFLOW_PUBLIC_BACKEND_URL` nas pipelines pelo domínio estabelecido.

## 4. Assinatura de Código e Lojas Oficiais (Apple / Google)
Os builds foram configurados para assimilar as credenciais.
**Pendência:**
- Adquirir/renovar a licença Apple Developer.
- Adquirir/renovar conta no Google Play Console.
- Inserir `storeFile` real do Android.
