# StudioFlow V1.0 - Guia de Implantação e Build

Este documento cobre o passo a passo para gerar as versões finais em Android, iOS e implantar o backend de produção.

## 1. Configurando Variáveis Nativas no Build
As variáveis podem ser passadas pelo comando de build do Flutter, permitindo a separação de ambientes sem chaves "chumbadas".

### Build Android
1. Certifique-se de que o arquivo `key.properties` (opcionalmente) exista em `android/key.properties` contendo:
   ```properties
   storePassword=SUASENHA
   keyPassword=SUASENHA
   keyAlias=SUAALIAS
   storeFile=CAMINHO_PARA_O_KEYSTORE
   ```
2. Caso opte por CI/CD, as variáveis de ambiente `STUDIOFLOW_KEYSTORE_PATH`, etc., já estão configuradas no `build.gradle.kts`.
3. Gere o App Bundle de produção injetando a URL do backend:
   ```bash
   flutter build appbundle --release --dart-define=STUDIOFLOW_PUBLIC_BACKEND_URL=https://api.studioflowapp.com.br
   ```

### Build iOS
1. Abra `ios/Runner.xcworkspace` no Xcode.
2. Certifique-se de estar com a conta Apple vinculada e com o perfil de provisionamento assinado.
3. Gere o Archive injetando a variável:
   ```bash
   flutter build ipa --release --dart-define=STUDIOFLOW_PUBLIC_BACKEND_URL=https://api.studioflowapp.com.br
   ```

## 2. Implantação do Backend (Dart Shelf)
O backend foi desenhado para rodar num container simples via Docker e requer PostgreSQL nativo.

1. Configure as variáveis na máquina host ou orquestrador:
   - `STUDIOFLOW_DATABASE_URL=postgres://user:pass@host:5432/db`
   - `STUDIOFLOW_WHATSAPP_PHONE_ID=seu_id`
   - `STUDIOFLOW_WHATSAPP_ACCESS_TOKEN=seu_token`
   - `STUDIOFLOW_PORT=8080` (opcional)

2. Inicie via Docker (se existir um Dockerfile, gere a imagem do projeto):
   ```bash
   cd backend
   dart compile exe bin/server.dart -o server
   ./server
   ```
3. O servidor possui worker dinâmico integrado para varredura da fila e automações de disparo de mensagens, com intervalo nativo já configurado em `automations.dart`.
