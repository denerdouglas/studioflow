# StudioFlow — Relatório Sprint 7 / Adendo de Estoque e Afiliados

Data da validação: 29/07/2026  
Versão do aplicativo: `1.2.1+2010`  
Banco SQLite: versão `10`

## Resultado

O adendo foi incorporado sem misturar os quatro domínios:

1. estoque operacional do salão (`estoque_destino = salao`);
2. estoque da Loja do Salão (`estoque_destino = loja`);
3. consignações (tabelas e fechamento próprios);
4. catálogo externo de compra (ofertas, links e métricas no backend).

Nenhuma integração externa foi simulada. Sem provedor e credenciais
configurados, a pesquisa retorna lista vazia e mensagem clara.

## Funcionalidades implementadas

- Scanner com EAN-8, EAN-13, UPC-A, UPC-E, ITF/GTIN e QR Code.
- Leitura por câmera ou digitação manual.
- Scanner no cadastro e na pesquisa do estoque operacional.
- Pesquisa de produto por nome, categoria, fornecedor ou código.
- Leitura já existente preservada na Loja do Salão, venda e recebimento.
- Leitura repetida na venda incrementa a quantidade do item no carrinho.
- Validação do dígito verificador de GTIN-8, UPC/GTIN-12, GTIN-13 e GTIN-14.
- Duplicidade de código isolada por comércio e estoque de destino.
- Busca inteligente na ordem: comércio local, cache público, catálogo
  StudioFlow, backend oficial permitido e contribuição comunitária aprovada.
- Produtos locais não são gravados no cache global.
- Catálogo colaborativo continua restrito a dados públicos do produto; custo,
  preço, margem, fornecedor, lote, observações e saldo não são enviados.
- Transferência explícita do salão para a Loja do Salão, com confirmação de
  quantidade e motivo.
- Transferência atômica com registro principal, saída na origem e entrada no
  destino. Não existe movimentação automática silenciosa entre estoques.
- Alertas de estoque baixo e comparação de ofertas reais existentes foram
  preservados.
- Cadastro manual completo permanece disponível como fallback.
- Backend para programas de afiliados, ofertas verificadas, cliques,
  conversões e comissões.
- Painel ROLG exposto somente por rotas administrativas protegidas por
  `ROLG_ADMIN_KEY`.
- O backend persiste somente `secret_reference`; token ou chave de marketplace
  não é aceito no aplicativo nem devolvido pelas APIs.
- URL de oferta exige HTTPS e domínio autorizado no programa.
- Ordenação neutra por custo total, com prazo como desempate.
- Divulgação transparente de possível comissão.
- Clique e conversão são métricas independentes.
- Comissão possui estados `estimada`, `confirmada` e `cancelada`.

## Arquivos criados

- `lib/database/migrations/migration_v10.dart`
- `lib/repositories/inventory_transfer_repository.dart`
- `test/sprint7_inventory_adendum_test.dart`
- `backend/lib/src/marketplace.dart`
- `backend/lib/src/marketplace_postgres_store.dart`
- `backend/migrations/003_marketplace_affiliates.sql`
- `backend/test/marketplace_test.dart`
- `RELATORIO_SPRINT_7_ADENDO_ESTOQUE_AFILIADOS.md`

## Arquivos alterados

- `pubspec.yaml`
- `android/gradle.properties`
- `android/app/build.gradle.kts`
- `lib/core/constants/database_constants.dart`
- `lib/database/database_schema_latest.dart`
- `lib/screens/barcode_scanner_page.dart`
- `lib/screens/estoque_page.dart`
- `lib/services/product_lookup_service.dart`
- `backend/.env.example`
- `backend/README.md`
- `backend/bin/server.dart`
- `backend/lib/studioflow_backend.dart`
- `backend/lib/src/api.dart`
- `backend/lib/src/config.dart`
- `backend/lib/src/memory_store.dart`

## Migrações

### SQLite v10

Cria `transferencias_estoque`, com:

- comércio;
- produto de origem e destino;
- origem e destino validados;
- quantidade positiva;
- motivo;
- usuário responsável;
- data.

Antes da migração é feito backup lógico de estoque, movimentações, ofertas,
catálogo e sugestões. A migração é aditiva e não reclassifica nem remove dados.

### PostgreSQL 003

Cria:

- `affiliate_programs`;
- `marketplace_offers`;
- `affiliate_clicks`;
- `affiliate_conversions`;
- índices e RLS para cliques por comércio.

## Rotas adicionadas

- `GET /v1/marketplace/offers?q=produto`
- `POST /v1/marketplace/offers/<id>/click`
- `GET /v1/admin/affiliate/programs`
- `PUT /v1/admin/affiliate/programs/<id>`
- `PUT /v1/admin/marketplace/offers/<id>`
- `POST /v1/admin/affiliate/conversions`
- `GET /v1/admin/affiliate/metrics`

## Validação

- `dart format`: concluído.
- `flutter analyze`: sem problemas.
- `dart analyze` do backend: sem problemas.
- Testes Flutter: 48 aprovados.
- Testes backend: 7 aprovados.
- Build: release AOT, ARM64 exclusivo, concluído.
- Version name: 1.2.1; version code base: 2010; split ARM64: 4010.
- ABI verificada: `arm64-v8a`.
- APK Signature Scheme v2: válido.
- Tamanho: 35.382.261 bytes.
- SHA-256:
  `E2149479E6B7BD7005A200954049E284F62A261B2FCD62DA7F527B120ED54021`

O R8 foi desativado neste artefato porque o disco C ficou sem espaço durante a
minificação e o heap conservador do notebook tornou a etapa inviável. O APK
continua sendo release AOT e mantém tree-shaking dos ícones, mas fica maior.

## Como testar no celular

1. Instalar o APK ARM64.
2. Entrar em um comércio existente ou fazer o primeiro cadastro.
3. Abrir Estoque e usar o ícone de código de barras na pesquisa.
4. Criar/editar um item e ler o código pela câmera.
5. Abrir as opções de um item com saldo e selecionar
   “Transferir para a Loja do Salão”.
6. Confirmar que o saldo diminuiu no salão e apareceu na Loja do Salão.
7. Conferir o histórico de movimentações.
8. Na venda da loja, ler o mesmo código repetidamente e conferir o incremento
   da quantidade.

## Dependências e limitações restantes

- Shopee, Mercado Livre, Amazon e outros provedores não possuem credenciais
  configuradas neste ambiente. Nenhum resultado foi inventado ou obtido por
  scraping.
- Para produção, cada provedor precisa de API/feed autorizado, credenciais em
  cofre e rotina backend de atualização das ofertas.
- O catálogo oficial remoto continua dependente de endpoint backend publicado.
- PostgreSQL e backend não foram implantados em nuvem neste notebook.
- O painel ROLG está disponível por API administrativa; uma interface web
  interna ainda pode ser construída sobre essas rotas.
- Não há webhook real de marketplace configurado; conversões só devem ser
  registradas por integração autorizada do servidor.
- O APK está assinado com a chave de desenvolvimento porque não existe keystore
  release configurado. Antes da publicação comercial é obrigatório fornecer
  uma keystore segura fora do repositório e proteger suas senhas.

## Artefatos

- APK:
  `D:\projeto salao\studioflow\artifacts\apk\StudioFlow-1.2.1-2010-arm64-v8a-release.apk`
- Backend:
  `D:\projeto salao\studioflow\artifacts\backend\studioflow-api.exe`

Nenhuma Sprint posterior foi iniciada.
