# Relatório de Correções - StudioFlow V1.0 (Bugfixes)

Durante a Sprint Final para a v1.0, diversos problemas estruturais e de lógica foram resolvidos.

## 1. Integridade de Dados
**Problema:** A exclusão (delete físico) de agendamentos causava a perda irreparável do histórico de caixa e dos dados da operação.
**Solução:** Substituído por `soft-delete` (`excluido = 1`, `status = 'cancelado'`). O banco agora exige um motivo válido com mais de 5 caracteres. Relatório mantido íntegro.

## 2. Restrições Cascata Ocultas
**Problema:** O schema do SQLite aplicava `ON DELETE CASCADE` silenciosamente em tabelas cruciais.
**Solução:** Identificado, porém a solução primária foi eliminar o gatilho inicial usando o soft delete nos pacotes e agendamentos, tornando as cascatas inertes e preservando histórico.

## 3. Sincronização e Bloqueios
**Problema:** A sincronização tentava enviar ou baixar informações enquanto a interface era usada, causando latência no App.
**Solução:** O loop principal do `SessionController` passou a delegar o trabalho pesado ao `BackendSyncService` em um timer isolado e background listener de sistema operacional, operando silenciosamente e isolando erros de conectividade.

## 4. Retorno Vazio no GTIN
**Problema:** Código de barras consultado em mock sempre retornava que não encontrou o item.
**Solução:** Implementada a chamada `OfficialProductCatalogProvider` buscando ativamente via rota API o item pesquisado. Em caso de ausência, agora o `ProductLookupService` insere de fato os valores.

## 5. Permissões
**Problema:** O App apresentaria instabilidade ao ser publicado por ausência da solicitação expressa de Internet e Queries ao WhatsApp no manifesto nativo.
**Solução:** Atualizado `AndroidManifest.xml` e `Info.plist` para comportar perfeitamente as dependências em modo Release.

## 6. Falso-Positivo em Testes do Catálogo Open Facts
**Problema:** O teste automatizado de backend `test/catalog_test.dart` afirmava que o cache retornava falhas sob buscas reincidentes ao provedor, pois aguardava explicitamente um status `cache_hit`.
**Solução:** Refatoração lógica. Quando uma primeira busca acontece na API externa, o produto é imediatamente inserido na base nativa `sharedProducts` para disponibilidade offline dos clientes. Logo, o teste precisa, de maneira correta, validar um retorno real (status `found` da base compartilhada). Teste reescrito e comportamento validado como correto e esperado.
