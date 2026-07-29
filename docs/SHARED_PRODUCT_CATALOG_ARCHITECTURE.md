# Arquitetura do Catálogo Compartilhado

## Limites de dados

`catalogo_produtos` é global e guarda apenas descrição geral, GTIN, variação, imagem de referência, fonte e confiança. Nunca recebe `comercio_id`, custo, preço, margem, quantidade, lote, validade, fornecedor, vendas ou observações privadas.

O cadastro local continua em `estoque`, obrigatoriamente com `comercio_id` e `estoque_destino` (`salao` ou `loja`). O mesmo GTIN pode existir em vários comércios e destinos sem compartilhar dados privados.

## Fluxo

1. Normalizar e validar GTIN-8/12/13/14 e dígito verificador.
2. Consultar cache válido.
3. Consultar produto local do comércio.
4. Consultar catálogo StudioFlow.
5. Consultar adaptador oficial/backend e comunidade aprovada.
6. Comparar confiança, apresentar prévia e pedir confirmação.
7. Salvar somente após o usuário escolher o estoque e informar dados locais.
8. Se não houver resultado, oferecer cadastro manual e código interno.

Consultas conhecidas ficam em `catalogo_cache`. Sugestões offline entram em `fila_sincronizacao` com chave única por sugestão.

## Variações

GTIN é a identidade principal. Embalagem, volume, tamanho, sabor, cor e versão diferente devem possuir GTIN/registro próprio; nomes semelhantes não são mesclados automaticamente.
