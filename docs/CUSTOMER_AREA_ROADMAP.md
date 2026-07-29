# Roadmap da Área do Cliente

Estruturas de perfil e carrinho foram preparadas. `customer_profile`, `customer_area` e `nearby_salons` permanecem desligadas.

Antes da ativação são necessários autenticação segura do cliente, recuperação de conta, consentimento LGPD, backend multiempresa, regras de visibilidade, publicação separada/rotas públicas e testes antifraude. O carrinho local já rejeita estoque operacional e baixa exclusivamente itens `estoque_destino='loja'`.

Busca de salões próximos exigirá permissão contextual de localização, política de retenção, ordenação transparente e opção manual por cidade; nenhuma permissão de localização existe nesta versão.
