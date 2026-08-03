# Relatório da Sprint Única Final

Data: 03/08/2026
Versão: `1.4.7+4018`
Branch: `release/v1.4.4-final`

## Adendo final — Loja personalizável e padrões globais

### Implementado nesta Sprint

- A Loja atual foi refatorada para catálogos definidos pela dona do estabelecimento, isolados por comércio e unidade, sem categorias rígidas e sem criar uma Loja paralela.
- Catálogos suportam criação, edição, capa/ícone, tipo de controle, ordenação, ativação, inativação e exclusão física somente quando vazios.
- Produtos suportam cadastro manual, código de barras, QR, OCR e importação em lote, além de edição, duplicação, inativação e exclusão somente sem histórico.
- Foram conectados os tipos comum, consignado, item individual, alimento/bebida, validade, consumível e outro aos registros existentes de estoque, peças únicas, comandas, consignação e contas a receber.
- Uma comanda aceita itens de diferentes catálogos e mantém cálculo único de total.
- `ContextActionMenu` unifica menu contextual, pressão longa nativa, clique direito, teclado, acessibilidade e vibração tátil.
- `UndoActionService` registra estado anterior/novo, oferece sete segundos para desfazer, audita a reversão e enfileira sincronização idempotente da ação e da reversão.
- A migration local v26 cria somente as tabelas auxiliares necessárias e amplia o estoque principal; não duplica stores, estoque, comandas ou Loja.

### Já existente e apenas validado

- Scanner/QR/OCR, estoque principal, comandas, joias consignadas, contas a receber, fila de sincronização, permissões e auditorias de negócio já existiam e foram reutilizados.
- A baixa de estoque, comissão e pagamentos das comandas continuam no fluxo transacional principal já existente.

### Dependência externa pendente

- A suíte PostgreSQL descartável permanece condicionada a `POSTGRES_TEST_URL`; sem essa variável não há alegação de execução positiva.
- Publicação, VPS, Nginx e validação remota foram retirados do escopo por instrução explícita.

### Indisponível/oculto em produção

- Integrações externas sem credenciais continuam retornando configuração pendente/503 e não simulam sucesso.
- Nenhum APK ou AAB foi gerado nesta conclusão local.
## Resultado executivo

A Sprint Única Final foi concluída sem criar uma sprint adicional. O aplicativo e o backend passaram em análise estática e testes antes do versionamento. Os artefatos Android desta versão devem ser gerados com o backend público de produção `https://api.studioflowapp.com.br`.

As páginas legais foram corrigidas manualmente na VPS, com configuração Nginx válida e reload concluído. Status informado e posteriormente considerado na conclusão: `/privacy/`, `/politica-de-privacidade/`, `/excluir-conta/`, `/termos-de-uso/` e `/contato/` em HTTP 200.

## Implementado nesta Sprint

- Correção da cadeia Android que bloqueava `:image_cropper:verifyReleaseResources`: AGP 8.13.2, Gradle 8.13 e ajuste dos limites de heap/metaspace para o ambiente disponível.
- Normalização segura de arquivos críticos para UTF-8 sem BOM, preservando `STUDIOFLOW_PUBLIC_BACKEND_URL` e `https://api.studioflowapp.com.br`.
- Conversão segura de `backend/lib/src/memory_store_full.dart` de conteúdo textual indevidamente detectado como binário para Dart UTF-8 válido, sem remover a implementação.
- Remoção da operação simulada de assinatura na interface de produção; a tela agora informa `Configuração pendente` e não inicia compras.
- Ajustes funcionais e de segurança nos módulos Premium, Marketplace e Academy, incluindo validação de URLs HTTPS e tratamento explícito de conteúdo indisponível.
- Correções de consistência no backend de Academy/Marketplace, nos stores em memória/Postgres e nos contratos consumidos pelo aplicativo.
- Proteção defensiva das mutações de clientes no repositório pelo módulo `Clientes`.
- Exclusão lógica de clientes com erro explícito para registro inexistente e preservação de históricos relacionados.
- Cinco testes específicos de clientes: edição refletida imediatamente, rejeição de WhatsApp duplicado, inativação com histórico preservado, exclusão inexistente e bloqueio por permissão.
- Correção manual, fora do repositório, das permissões/configuração das páginas legais na VPS.

## Já existente e apenas validado

Os itens abaixo já existiam no código antes da conclusão atual; não são apresentados como implementações novas:

- Edição de contato após criação pela folha de edição da tela de clientes.
- Diálogo de confirmação antes da exclusão e retorno `excluido` para recarregar imediatamente a lista.
- Scanner local de código de barras com `mobile_scanner`, entrada manual e tratamento de permissão de câmera.
- OCR local no aparelho com ML Kit, sem dependência da rota mock `/v1/scanner/scan` do backend.
- Estoque inteligente: quantidades físicas, conteúdo por unidade, mínimos, movimentações e testes de fracionamento.
- Loja do Salão: catálogo, peças únicas, vendas, isolamento por estabelecimento e movimentação de estoque.
- Compras do Salão: pesquisa externa em Mercado Livre/Shopee e registro local de preço, frete e prazo; nenhum resultado externo é apresentado como simulado.
- Funcionários e permissões granulares por módulo/ação.
- Múltiplas unidades e isolamento por estabelecimento.
- Serviços, pacotes e seus fluxos persistentes.
- Detecção e resolução assistida de conflitos de agenda.
- Tema Light/Dark e aparência isolada por estabelecimento.
- Sincronização offline-first, fila local e recuperação de conta online.
- Preparação para testadores por meio de mensagens claras, estados vazios, indisponibilidade explícita e build release.

## Dependência externa pendente

- Cobranças/assinaturas reais: cadastro dos produtos na loja e verificação segura pela Google Play Developer API/GCP.
- WhatsApp oficial: credenciais Meta, número, templates e backend configurado; nenhuma credencial é embutida no aplicativo.
- IA online: provedor e credenciais mantidos exclusivamente em backend seguro.
- Resultados comerciais externos dependem da disponibilidade e das regras dos sites/provedores consultados.

Essas pendências não bloqueiam análise, testes ou build e não foram preenchidas com credenciais inventadas.

## Indisponível ou oculto em produção

- Compra/restauração de assinatura enquanto a validação oficial não estiver configurada.
- WhatsApp oficial automático sem credenciais; permanecem disponíveis somente compartilhamento/abertura manual e filas claramente identificadas.
- IA online; ficam disponíveis os recursos locais e o simulador explicitamente rotulado.
- Qualquer função mock permanece rotulada como simulação ou fora da interface operacional de produção.

## Validação de clientes e contatos

- Editar após criação: confirmado no código e em teste de persistência/consulta.
- Excluir após criação: confirmado por inativação `ativo = 0`.
- Confirmação: diálogo `Excluir cliente?` exige ação explícita.
- Histórico: agendamento relacionado permanece após inativação do cliente.
- Atualização imediata: detalhe atualiza por `setState`; retorno `atualizado`/`excluido` recarrega a lista.
- Permissões: navegação exige `ModuloPermissao.clientes` e o repositório bloqueia mutações sem o módulo.
- Testes: cinco casos dedicados adicionados em `test/cliente_edicao_exclusao_test.dart`.

## Validação automatizada antes do versionamento

- `flutter analyze`: sem issues.
- `flutter test`: 125 testes aprovados.
- `backend/dart analyze`: sem issues.
- `backend/dart test`: 38 testes aprovados.
- Formatação anterior: 228 arquivos Flutter e 31 arquivos backend, sem alterações pendentes de formatter.

## Segurança e higiene

- Nenhum `.bak` restante.
- Dump de JVM gerado foi excluído do diff.
- Nenhuma alteração em `.gitkeep` ficou pendente.
- APK/AAB e caches de build não são preparados para commit.
- Arquivos de chave, keystore e credenciais não são incluídos no commit.
- O diff final deve ser novamente verificado antes do commit.

## Artefatos

- APK: `build/app/outputs/flutter-apk/app-release.apk`
  - 119.509.422 bytes
  - SHA-256 `45C624A33008AB6B3FE998A085EC9032A5BF471B6A5068129D3C0FA5EA7FBCE9`
  - APK Signature Scheme v2 verificada; `apksigner` exit 0.
- AAB: `build/app/outputs/bundle/release/app-release.aab`
  - 89.874.586 bytes
  - SHA-256 `34D6E633B9114F2473B0382394081A24F7997868DE5B98C2B20196CBA33F738B`
  - `jar verified`; `jarsigner` exit 0.
- Certificado do signatário SHA-256: `E2FAAFB736D2951DF61E5EE4F19FD2D2A860C342AA5415699604E829A6AB6063`.
- Metadados internos do APK: `com.rolgsystems.studioflow`, `versionName=1.4.5`, `versionCode=4016`.

## HTTP final

- `/privacy/`: 200
- `/politica-de-privacidade/`: 200
- `/excluir-conta/`: 200
- `/termos-de-uso/`: 200
- `/contato/`: 200
