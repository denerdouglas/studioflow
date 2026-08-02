#!/bin/bash
set -e

echo "=================================================="
echo " Preparando VPS para StudioFlow Cloud (Ubuntu 24.04)"
echo "=================================================="

# Atualiza pacotes e instala dependências básicas
apt-get update
apt-get upgrade -y
apt-get install -y curl wget git ufw certbot python3-certbot-nginx nginx unzip

# Configura o UFW (Firewall)
echo "Configurando Firewall (UFW)..."
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

# Instala Docker
if ! command -v docker &> /dev/null; then
    echo "Instalando Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
else
    echo "Docker já está instalado."
fi

# Cria diretórios do StudioFlow
echo "Criando diretório da aplicação..."
mkdir -p /opt/studioflow/backend
mkdir -p /opt/studioflow/painel

# Instala o arquivo de configuração do Nginx (stub)
echo "Copiando configuração do Nginx..."
cp nginx_api.conf /etc/nginx/sites-available/studioflow_api
ln -sf /etc/nginx/sites-available/studioflow_api /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Testa o Nginx
nginx -t
systemctl restart nginx

echo "Gerando Certificado SSL (Let's Encrypt) para a API..."
# O comando abaixo requer que o DNS (A record) de api.studioflowapp.com.br aponte para 72.62.96.241
certbot --nginx -d api.studioflowapp.com.br --non-interactive --agree-tos -m admin@studioflowapp.com.br

echo "=================================================="
echo " Configuração básica da VPS concluída!"
echo " Próximos passos:"
echo " 1. Copie os arquivos da pasta 'backend/' para '/opt/studioflow/backend/'"
echo " 2. Crie e preencha o arquivo '/opt/studioflow/backend/.env'"
echo " 3. Execute: cd /opt/studioflow/backend && docker compose up -d"
echo "=================================================="
