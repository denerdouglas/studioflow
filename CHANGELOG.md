# Changelog

## [1.4.6] - 2026-08-03

### Changed
- Corrige a navegação inferior para Início, Agenda, Loja e Mais; Loja abre a Loja do Salão.
- Move Clientes para Mais preservando o layout premium e os temas Light/Dark.
- Torna o Instagram obrigatório, normaliza o perfil e abre a URL exata salva.
- Ativa WhatsApp, Instagram e Telefone no detalhe premium e preserva edição e inativação lógica.
- Centraliza as entradas de scanner em código/QR, OCR, revisão e digitação manual.
- Conecta o agendamento público ao motor de agenda e ao cadastro principal, com confirmação, cancelamento, reagendamento, idempotência e sincronização.
- Substitui a IA local estática por conversa operacional com histórico, consultas reais, isolamento, permissões e ações com prévia.
- Entrega comandas de produtos com cliente, scanner/código, itens, desconto, comissão, estoque, pagamentos, compartilhamento e estorno.
- Entrega maletas de joias consignadas com peças únicas, estados, venda, devolução, conferência, arquivamento e histórico.
- Entrega contas a receber vinculadas às comandas, com vencimento configurável, filtros, pagamentos parciais/totais e estorno.
- Completa o catálogo administrativo de afiliados com ofertas, CSV, demandas sem resultado, cliques e redirect seguro.

### Fixed
- Remove respostas de sucesso simuladas do scanner HTTP, assinatura e marketplace quando a integração real não está configurada.
- Mantém as páginas públicas e legais existentes sem novo deploy nesta finalização local.

All notable changes to this project will be documented in this file.

## [1.4.5] - 2026-08-03

### Added
- Testes dedicados para edição, duplicidade de WhatsApp, exclusão lógica, preservação de histórico e permissão de clientes.
- Relatório consolidado da Sprint Única Final com separação entre entregas, validações e dependências externas.

### Changed
- Mutações de clientes agora exigem o módulo `Clientes` também no repositório, além da proteção de navegação existente.
- Assinaturas e cobranças não configuradas permanecem indisponíveis na interface de produção, sem simular operação real.
- Toolchain Android compatibilizada com AGP 8.13.2, Gradle 8.13 e limites de memória adequados ao ambiente de build.

### Fixed
- Exclusão de clientes reporta registros inexistentes e mantém inativação lógica para preservar históricos relacionados.
- Arquivos críticos normalizados em UTF-8 sem BOM e endpoint público corrigido para `https://api.studioflowapp.com.br`.
- Falha `:image_cropper:verifyReleaseResources` eliminada após alinhamento do toolchain e limpeza segura dos caches gerados.
- Links legais públicos validados com HTTP 200 após correção manual da VPS.

## [1.0.0] - 2026-07-30
### Added
- **Sincronização Resiliente em Background:** Adicionado timer e monitoramento do ciclo de vida do app para disparar o push e pull de dados silenciosamente através do `BackendSyncService`.
- **Gatilhos de WhatsApp Offline-First:** Integração do enfileiramento de mensagens via `WhatsappQueueService` para a tabela local `whatsapp_fila`, permitindo a automação do WhatsApp na criação e cancelamento de agendamentos.
- **Ficha de Anamnese Real:** Substituição do placeholder por armazenamento físico e persistente (`anamnese_repository.dart`) no SQLite.

### Changed
- **Soft-Delete Seguro em Agendamentos:** `AgendaCompletaRepository.excluirSeguro` modificado para não deletar os dados do banco, implementando um modelo de exclusão lógica que rastreia mensagens, vínculo financeiro e gera logs de auditoria (`agendamento_exclusoes`).
- **Autenticação Conectada:** Login local SQLite substituído pelo `BackendApiClient` consumindo o backend oficial e persistindo a sessão via `BackendTokenVault`.
- **Pesquisa de Produtos GTIN:** Conexão direta de buscas de código de barra no backend de fato, mapeando cache local e permitindo uso dinâmico.

### Fixed
- Evitada a exclusão "cascade" arbitrária no banco de dados local.
- Resolução do vazamento e falha de cache local durante buscas concorrentes.
- Corrigida a lógica de testes de catálogo e fluxo GTIN (`catalog_test.dart`) reconhecendo o preenchimento de `sharedProduct` para lookups globais do salão em consultas subsequentes à Open Facts.

### Added (Agenda)
- Inserida opção interativa `Enviar Lembrete` direto da lista de agendamentos diários. Os textos são preenchidos dinamicamente e podem ser enfileirados de forma offline na API Meta (`WhatsappQueueService`) ou abertos nativamente.
- Melhorada a clareza da opção de exclusão lógica para `Excluir agendamento` integrando perfeitamente ao histórico de auditoria transacional.
