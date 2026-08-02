# Implantação StudioFlow Cloud

Siga os passos abaixo para implantar o backend na VPS (Ubuntu 24.04).

## Passo 1: Copiar os arquivos para a VPS
Você precisa transferir a pasta `backend` e a pasta `deploy` para o servidor. Pode fazer isso via SCP:

Abra um terminal (no seu Windows) na raiz do projeto e execute:
```powershell
scp -r backend root@72.62.96.241:/opt/studioflow_backend
scp -r deploy root@72.62.96.241:/opt/studioflow_deploy
```

## Passo 2: Acessar a VPS
Acesse o servidor via SSH:
```powershell
ssh root@72.62.96.241
```

## Passo 3: Executar o script de Setup
Na VPS, navegue até a pasta de deploy e execute o script:
```bash
cd /opt/studioflow_deploy
chmod +x setup_vps.sh
./setup_vps.sh
```

*(O script instalará o Docker, Nginx, UFW, configurará os certificados Let's Encrypt para `api.studioflowapp.com.br` e copiará o arquivo do nginx)*.

## Passo 4: Mover e configurar o Backend
Na VPS, mova os arquivos do backend para o local correto:
```bash
mv /opt/studioflow_backend/* /opt/studioflow/backend/
cd /opt/studioflow/backend/
```

### Configurar Segredos do Ambiente
Copie o exemplo do `.env`:
```bash
cp .env.example .env
nano .env
```
Neste arquivo `.env`, preencha os segredos:
- `DATABASE_URL=postgresql://studioflow:SUA_SENHA_FORTE_AQUI@postgres:5432/studioflow` (troque a senha na string de conexão)
- `STUDIOFLOW_DB_PASSWORD=SUA_SENHA_FORTE_AQUI` (coloque a mesma senha forte)
- `JWT_SECRET=` (insira uma chave longa com no mínimo 64 caracteres)
- `PUBLIC_BASE_URL=https://api.studioflowapp.com.br`

## Passo 5: Iniciar o Banco e Rodar Migrações
Com o `.env` preenchido, inicialize o banco de dados:
```bash
docker compose up -d postgres
```
Aguarde alguns segundos e execute as migrações usando a imagem da API:
```bash
docker compose run --rm api dart run bin/migrate.dart
```

## Passo 6: Iniciar o Sistema Completo
```bash
docker compose up -d
```

Verifique se a API está online acessando:
`https://api.studioflowapp.com.br/health` (deve retornar um JSON com `"status": "ok"`).
