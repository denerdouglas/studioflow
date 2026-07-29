# Product Lookup Providers

Contrato: `ProductCatalogProvider.findByGtin`. Orquestrador: `ProductLookupService`.

| Provider | Origem | Estado v1.0 |
|---|---|---|
| `LocalProductCatalogProvider` | estoque do comércio autenticado | ativo |
| `StudioFlowCatalogProvider` | catálogo mestre SQLite/cache | ativo |
| `OfficialProductCatalogProvider` | backend/licenciado | adaptador, sem credencial |
| `CommunityProductCatalogProvider` | conteúdo aprovado | ativo local |
| `MockProductCatalogProvider` | testes determinísticos | testes |

O cache tem prioridade absoluta. Sem cache, todos os providers configurados são consultados e vence o resultado de maior confiança. Não há scraping. URLs e credenciais privadas não são embutidas.
