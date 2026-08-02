# Auditoria Completa StudioFlow

Data da Auditoria: 30/07/2026
Versão Base: 1.4.0+4009

## 1. Resumo executivo

O StudioFlow possui uma vasta implementação de telas no Flutter e regras de negócio no SQLite (local), contando com 85 testes aprovados e dezenas de módulos visualmente completos. No entanto, o projeto opera de forma primariamente "offline-first" sem um backend hospedado. A infraestrutura de nuvem, sincronização, mensagens automáticas (WhatsApp) e catálogos externos estão simulados, mockados ou pendentes de credenciais. Há lacunas críticas na anamnese (placeholder) e na exclusão de agendamentos (sem restrições). O aplicativo não está pronto para publicação imediata, exigindo uma Sprint Final focada em conectar o Flutter ao backend real, tratar permissões, e resolver as integrações simuladas.

## 2. Arquitetura atual

- **Frontend:** Flutter (Dart), arquitetura baseada em serviços, repositórios e telas (feature-first e camadas). Gerenciamento de estado misto (AnimatedBuilder/SessionController).
- **Armazenamento Local:** SQLite genérico (sqflite) atuando como banco principal temporário.
- **Backend:** Servidor em Dart puro usando `shelf` e `shelf_router`, contendo rotas organizadas, webhooks e automação de mensagens (`worker`).
- **Banco de Dados Remoto:** PostgreSQL (preparado no backend via `postgres` driver), mas atualmente sem implantação na nuvem confirmada.
- **Sincronização:** Arquitetura de push/pull preparada (mutations), mas inativa em produção.

## 3. Estrutura do frontend

- `lib/core`: Constantes, temas e estilos.
- `lib/database`: `DatabaseService` e migrações SQLite.
- `lib/models`: Classes de domínio (agendamentos, clientes, estoque).
- `lib/repositories`: 35 repositórios fazendo CRUD majoritariamente direto no SQLite local.
- `lib/services`: Controladores de sessão, APIs, catálogos (muitos em estado de mock/incompletos).
- `lib/screens`: 44 telas implementadas.
- `lib/widgets`: Componentes visuais.

## 4. Estrutura do backend

- `backend/bin`: Contém `server.dart` (ponto de entrada) e `migrate.dart`.
- `backend/lib/src`: 
  - `api.dart`: Roteamento e controladores (Auth, Marketplace, Webhooks).
  - `automations.dart`: Filas e envios automáticos (WhatsApp).
  - `postgres_store.dart`: Implementação do repositório no PostgreSQL.
  - `models.dart`, `security.dart`, `config.dart`.
- Conta com autenticação JWT e criptografia `bcrypt`.

## 5. Mapa de módulos

| Módulo | Tipo | Status |
|---|---|---|
| Acesso/Login | Core | Funciona local; Remoto desconectado |
| Agenda | Core | Funciona local; Sem sincronização |
| Clientes/360 | Core | Funciona local |
| Serviços/Pacotes | Serviço | Funciona local |
| Profissionais | Equipe | Funciona local |
| Financeiro/Caixa | Finanças | Funciona local; Faltam regras transacionais de nuvem |
| Estoque/Produtos | Material | Funciona local |
| Anamnese | Ficha | Placeholder |
| Automações (WhatsApp)| Integração | Bloqueado por credenciais/Mockado no app |
| Catálogo (GTIN) | Integração | Backend preparado; Retorna Null (Mock) |

## 6. O que já funciona

Operações puramente locais no banco do telefone: 
- Criação e edição de Empresas, Usuários, Permissões.
- Fluxo de Agendamento (criar, editar, checar conflito local).
- Clientes, Serviços, Profissionais.
- Pacotes (venda, baixa de sessão).
- Caixa (abertura e fluxo de caixa), Financeiro, Comissões.
- Estoque operacional e vendas na loja.
- Relatórios sintéticos.

## 7. O que funciona parcialmente

- **Código de barras:** Lê o GTIN corretamente, busca no estoque local, mas a consulta externa falha/retorna null silenciosamente.
- **Cancelamento de Agenda:** Muda o status, mas não pede motivo e não cancela notificações já enfileiradas.
- **Exclusão de Agenda:** Deleta diretamente do banco sem auditoria, validação de permissão gerencial ou checagem de vínculo financeiro.
- **Backup Local:** Arquitetura de upgrade existe, mas não há um restore diário em nuvem funcional.

## 8. O que é mock ou placeholder

- **Anamnese:** Tela (`anamnese_page.dart`) é apenas um placeholder visual.
- **Assinatura/Pagamento:** Fluxos de pagamento do estabelecimento simulados (mocks diretos).
- **IA Conversacional/Online:** Respostas geradas por simulação.
- **Fila de WhatsApp local:** Marca o envio como `simulado`.
- **Catálogo Externo:** O provedor oficial de GTIN no backend não possui credenciais, retornando ausência para todos.

## 9. O que está quebrado

- Sincronização entre dois aparelhos.
- Recuperação de dados após desinstalação (dados são perdidos porque vivem no SQLite sem backup online ativo).
- Webhook do WhatsApp (servidor não está na internet).

## 10. Problemas críticos

- **Acesso/Persistência:** O login ocorre validando hashes no SQLite do aparelho. Se o app for deletado, os dados da empresa morrem, e o usuário não consegue "logar de novo" para recuperar os dados porque o backend não está integrado de fato.
- **Exclusão Insegura:** Apagar agendamentos que já movimentaram caixa e comissões quebra a integridade financeira (falta de soft-delete e auditoria).

## 11. Problemas de segurança

- **Transações:** Exclusões não autorizadas (qualquer um exclui sem log de auditoria no app local).
- A API do backend existe, mas como o app roda quase totalmente offline, a segurança de autorização multi-usuário depende da interface do Flutter, o que é frágil se o SQLite for modificado via root.
- Faltam credenciais reais em `backend/.env` gerando instabilidade.

## 12. Problemas de isolamento multiempresa

- O backend foi desenhado para multi-tenant (Isolamento por `businessId`), mas como o app funciona em modo SQLite local isolado, a verdadeira validação multiempresa nunca foi testada sob estresse ou com usuários compartilhados em concorrência na nuvem.

## 13. Problemas de Android

- APK de release compila, mas não tem variáveis de ambiente de produção (ex: endpoint da API). O `STUDIOFLOW_PUBLIC_BACKEND_URL` não está configurado para apontar para um servidor real. 

## 14. Problemas de iOS

- Necessidade de configuração de Entitlements (Câmera, Galeria) real.
- Falta de testes no TestFlight (testes em aparelhos físicos).

## 15. Problemas de backend

- Backend isolado. Não há hospedagem. Faltam logs estruturados externos. Não há monitoramento configurado. Os testes de integração multiempresa precisam de ambiente real (RDS, EC2, Cloud Run, etc).

## 16. Problemas de banco

- **PostgreSQL:** Não está provisionado na nuvem.
- **SQLite (Local):** Migrações locais não contemplam adequadamente regras de integridade transacional financeira (ON DELETE CASCADE perigoso na agenda e histórico).

## 17. Problemas de publicação

- Faltam URLs de Termos de Uso e Privacidade hospedadas para aprovação nas lojas (Google Play e App Store).
- A ausência de backend obriga o avaliador das lojas a usar o app como uma "agenda offline", o que pode causar rejeição se funções prometidas (como IA, Webhooks, Multi-aparelho) não puderem ser validadas.

## 18. Dependências externas

- **Dependências atuais:** `mobile_scanner`, `sqflite`, `http`, pacote backend `shelf`, driver `postgres`.

## 19. Credenciais ou aprovações externas necessárias

- WhatsApp Business API (Meta Developer) - Token, webhook, número aprovado.
- Hospedagem (AWS/GCP/Render/Heroku) para backend e PostgreSQL.
- Provedor de E-mail/SMS para recuperação de senhas.
- Conta de desenvolvedor Apple e Google confirmadas.
- Serviço oficial de base de dados GTIN para produtos.

## 20. Lista exata dos arquivos que precisarão ser modificados

1. `lib/screens/anamnese_page.dart` (Fazer real)
2. `lib/repositories/anamnese_repository.dart` (Criar)
3. `lib/screens/agenda_page.dart` (Ajustar remoções)
4. `lib/repositories/agenda_repository.dart` (Criar soft delete)
5. `lib/database/database_schema_latest.dart` (Ajustar restrições e criar anamnese)
6. `lib/screens/acesso_page.dart` e `lib/repositories/acesso_repository.dart` (Conectar login no backend)
7. `backend/lib/src/api.dart` (Ajustar retornos de GTIN e sync)
8. `lib/services/backend_sync_service.dart` (Ativar sincronização por padrão)
9. `backend/lib/src/automations.dart` (Injetar credenciais WhatsApp reais)
10. `android/app/build.gradle` & `ios/Runner/Info.plist` (Revisar variáveis de build)

## 21. Classificação P0, P1, P2 e P3

- **P0 (Crítico para funcionar):** Backend hospedado na nuvem, banco remoto provisionado, conexão do fluxo de Login/Persistência com a nuvem, remoção do soft-delete/exclusão perigosa da agenda.
- **P1 (Crítico para a operação do cliente):** Anamnese funcionando (gravar e editar); Sincronização multi-aparelho homologada e livre de conflitos.
- **P2 (Diferenciais / Contrato):** WhatsApp Automático (Worker + Credenciais), Consulta real de GTIN (Código de barras).
- **P3 (Perfumes):** Relatórios refinados, IA conversacional real, Módulos de comissão ultra-complexos.

## 22. Proposta de Sprint Final (Deploy & Sync)

**Objetivo:** Transformar o "app local funcional" em uma "plataforma SaaS mobile homologável em 2 aparelhos".

- **Dia 1-2:** Correção da Anamnese (Interface, Local DB) e Refatoração de Exclusão da Agenda (Soft-delete + Auditoria + Permissões).
- **Dia 3-4:** Infraestrutura de Nuvem: Subir servidor Dart + PostgreSQL e vincular `.env`. Configurar URLs.
- **Dia 5-6:** Login e Sincronização: Integrar a tela de acesso com a API real, garantindo resgate de dados em aparelho zerado. Realizar o teste de sincronização A/B entre dois celulares.
- **Dia 7-8:** Integrações: Colocar WhatsApp para disparar real (Webhook Meta) e plugar API oficial de GTIN.
- **Dia 9-10:** Builds Android e iOS com chaves de produção, teste em dispositivos físicos e submissão nas lojas.
