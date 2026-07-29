# Auditoria obrigatória do StudioFlow antes da homologação real

Data: 29/07/2026
Versão auditada: 1.4.0+4009 (split ARM64 instalado como versionCode Android 6009)
Escopo: código Flutter, SQLite, backend Dart/PostgreSQL, testes automatizados, artefatos e evidências anteriores de instalação em um aparelho.

## 1. Resumo executivo

O StudioFlow possui uma base local extensa e 85 testes Flutter aprovados. Cadastro/login local, empresas, usuários, permissões, clientes, agenda principal, serviços, profissionais, pacotes, caixa, financeiro, comissões, estoques, loja, consignação, configurações, relatórios-resumo e IA local possuem operações reais no SQLite e testes automatizados em diferentes níveis.

Isso não equivale a uma plataforma em nuvem concluída. O login do aplicativo consulta o SQLite, não o backend. Há API, PostgreSQL, JWT, refresh token e sincronização genérica implementados e testados em memória/ambiente local, porém não existe URL hospedada confirmada, o APK não possui endpoint público compilado e não houve teste real em dois aparelhos. Recuperação após reinstalação não está comprovada.

Três lacunas críticas impedem a homologação solicitada:

1. Anamnese: tela placeholder, sem preenchimento ou salvamento.
2. Exclusão de agendamento: exclusão direta sem autorização específica, motivo, auditoria ou diagnóstico prévio de vínculos.
3. Persistência entre aparelhos: bloqueada por ausência de backend hospedado/configurado e teste real.

A busca de código de barras é parcial: lê e valida GTIN, consulta estoque e catálogos SQLite, mas o provedor externo oficial retorna sempre `null`. O cadastro manual está disponível antes de qualquer busca e imagem/unidade/volume não são preenchidos de ponta a ponta.

WhatsApp automático está implementado como arquitetura de backend, fila, webhook e retentativas, mas não há provedor, credenciais, número ou templates aprovados confirmados. Portanto mensagens automáticas reais estão bloqueadas. A fila local existente usa status `simulado` e o envio manual abre WhatsApp/compartilhamento.

Nenhuma Sprint 10 ou 11 foi implementada. Nenhum código funcional foi alterado nesta auditoria.

## 2. Evidências e limites desta auditoria

- `flutter test`: 85 testes aprovados.
- `dart test` no backend: 13 testes aprovados.
- Última análise estática anterior à auditoria: sem problemas.
- APK 1.4.0 instalado anteriormente em um aparelho ARM64 sem desinstalar; dados da instalação foram preservados.
- O aparelho ficou desconectado durante a etapa de inspeção privada; o banco do telefone não foi extraído.
- Não havia segundo aparelho disponível.
- Não foi fornecida URL real, acesso ao servidor, PostgreSQL hospedado ou credenciais externas.
- Testes automatizados comprovam regras isoladas; não comprovam envio externo, disponibilidade 24/7 ou sincronização real entre celulares.

## 3. Anamnese

### Código existente

- Tela: `lib/screens/anamnese_page.dart`.
- Entrada pela cliente: `lib/screens/clientes_page.dart`, método `_abrirAnamnese`.
- Tabela antiga: `anamneses` em `lib/database/database_schema.dart`.
- Modelo não conectado à persistência: `FichaAnamnese` em `lib/models/domain/cliente.dart`.
- A tabela recebeu `comercio_id` na migração multiempresa, mas não há repositório de anamnese.

### Situação real

| Requisito | Resultado |
|---|---|
| Abrir tela | Sim; mostra somente “Tela de Anamnese” |
| Preencher | Não |
| Salvar | Não |
| Editar | Não |
| Consultar ficha | Não |
| Histórico | Não |
| Persistir após fechar | Não há gravação pela interface |
| Sincronizar | Não; apenas estrutura genérica potencial, sem fluxo utilizável ou teste real |
| Modelos por estabelecimento | Não implementado |
| Identificar profissional | Não existe campo/fluxo funcional |
| Data e horário | A tabela antiga possui criação/atualização, mas a tela não usa |

### Tipos de campo

A estrutura antiga contém textos, observações, vários booleanos de sim/não e uma string de assinatura. Não possui sistema configurável de campos, modelos, múltipla escolha, seleção única, data, número, fotos, versão da ficha ou histórico imutável. O modelo Dart cobre apenas parte das colunas antigas.

Status: **NÃO IMPLEMENTADO**.

## 4. Cancelar e excluir agendamento

### Cancelar

Existe ação distinta e `AgendaCompletaRepository.registrarStatus` atualiza o status para `cancelado`, mantém a cliente e grava `agendamento_historico` com usuário e data. Para sessões de pacote, chama a regra do pacote.

Lacunas:

- a interface não pede motivo; envia detalhes vazios;
- lembretes já inseridos em `outbound_messages` não são cancelados;
- não há confirmação específica para cancelamento;
- não há teste que verifique remoção de lembretes pendentes;
- o funcionamento em nuvem não foi testado.

Status: **PARCIAL**.

### Excluir

A interface pede somente confirmação sim/não e chama `AgendaRepository.excluir`, que executa `DELETE FROM agendamentos`.

Lacunas críticas:

- botão aparece sem verificação visual de proprietário/gerente;
- repositório de exclusão não valida `gerenciarAgenda` nem função;
- não pede motivo;
- não grava auditoria antes de apagar;
- o histórico possui `ON DELETE CASCADE`, portanto também é apagado;
- não verifica previamente pagamentos, caixa, comissão, pacote, estoque, venda ou sessão realizada;
- não cancela mensagens já enfileiradas;
- vínculos protegidos por FK podem causar apenas erro genérico; vínculos sem FK podem ser perdidos silenciosamente;
- não distingue teste/duplicado/engano de registro operacional.

Status: **PARCIAL**, com risco de integridade.

## 5. Persistência e sincronização — respostas objetivas

1. **O backend está hospedado na internet?** Não há evidência de hospedagem. O repositório contém Docker Compose para execução local/servidor, não uma implantação confirmada.
2. **Qual é a URL atual?** Nenhuma URL real confirmada. O exemplo usa `localhost`; o APK foi compilado sem `STUDIOFLOW_PUBLIC_BACKEND_URL` e a tela permite digitação manual.
3. **O aplicativo instalado se conecta a essa URL?** Não comprovado. Nenhuma URL foi confirmada no banco privado do aparelho.
4. **O login consulta backend ou banco local?** Banco SQLite local. `AcessoPage` chama `AcessoRepository.autenticar` diretamente.
5. **Dados criados no celular são enviados ao servidor?** Somente se o usuário conectar manualmente um endpoint válido e ativar sincronização. A arquitetura existe; envio real não foi comprovado.
6. **Outro celular recupera os dados?** Não testado e atualmente bloqueado.
7. **Após reinstalar, os dados são recuperados?** Não comprovado. Sem nuvem ativa, desinstalar remove SQLite e dados não retornam.
8. **O que é mock/simulação?** Assinatura/pagamento comercial, IA conversacional online, fila WhatsApp local, confirmação automática de pagamento e alguns contratos de integrações.
9. **Credenciais faltantes?** Servidor/PostgreSQL, JWT, domínio/TLS, provedor WhatsApp, webhook, e-mail/SMS de recuperação, armazenamento de arquivos e fonte externa de produtos.
10. **Módulos somente locais?** Login principal, empresas, usuários, permissões, clientes, agenda, serviços, profissionais, pacotes, caixa, financeiro, comissões, estoque, loja, consignados, relatórios, configurações, IA local e central manual de aniversários.

## 6. Teste reproduzível entre dois aparelhos

Status: **BLOQUEADO POR INFRAESTRUTURA**.

### Pré-requisitos

1. Hospedar o backend continuamente com HTTPS.
2. Criar PostgreSQL separado e aplicar migrações 001–004.
3. Configurar domínio, JWT e cofre de segredos.
4. Conectar o aparelho A em “Produção e sincronização”.
5. Instalar APK com a mesma assinatura no aparelho B.
6. Criar a mesma conta remota e validar tokens seguros.
7. Antes de testar anamnese, implementar seu fluxo real e incluir suas novas tabelas no contrato de sincronização.

### Roteiro

- A: criar cliente, agendamento, anamnese, produto e movimento de estoque; sincronizar e registrar IDs.
- B: entrar na mesma conta remota, sincronizar e comparar IDs/campos.
- B: editar cada tipo; sincronizar.
- A: receber alterações e validar versão, duplicidade e conflito.
- Operar ambos offline sobre o mesmo registro; reconectar e validar política de conflito.
- Fechar/reabrir ambos.
- Em aparelho de teste, limpar/reinstalar, entrar e recuperar tudo do servidor.
- Comparar contagens e hashes lógicos antes/depois.

Não executar reinstalação no aparelho com dados únicos antes de backup remoto validado.

## 7. Código de barras e busca externa

### O que funciona

- Scanner aceita EAN-8, EAN-13, UPC-A, UPC-E, Code 39/128, ITF-14 e QR.
- Normaliza e valida dígito verificador de GTIN-8/12/13/14.
- Consulta primeiro o estoque do estabelecimento.
- Consulta cache e `catalogo_produtos` SQLite.
- Informa a lista de provedores consultados.
- Formulário pode receber nome, marca, categoria e descrição do resultado.
- Falhas de câmera oferecem digitação manual.

### O que não funciona de ponta a ponta

- `OfficialProductCatalogProvider.findByGtin` retorna sempre `null`.
- Nenhuma API externa, chave ou acesso HTTP está implementado nesse provider.
- “Catálogo StudioFlow” é tabela local/sincronizável, não catálogo online confirmado.
- O botão “Cadastrar manualmente” fica disponível antes de pesquisar.
- Unidade/volume não fazem parte de `CatalogProduct`.
- A imagem pode existir no resultado, mas não é exibida/salva no cadastro local.
- Não há log técnico persistente das consultas; há apenas a lista exibida na tela.
- Não há diferenciação operacional entre fonte indisponível e produto inexistente.

Status: **PARCIAL**.

## 8. WhatsApp automático

### Implementado em código

- Worker executado pelo processo backend a cada minuto.
- Agendamento de lembrete 16h, duas horas antes e aniversários 8h/9h.
- PostgreSQL `outbound_messages` e `message_delivery_attempts`.
- Idempotência, até cinco tentativas e backoff.
- Sender HTTP configurável por ambiente.
- Webhook autenticado para enviado/entregue/lido/erro.
- Histórico autenticado por estabelecimento.
- Provider desabilitado mantém erro e retentativa em vez de marcar envio como sucesso.

### Não comprovado/configurado

- backend público continuamente online;
- URL do provedor;
- token do provedor;
- número WhatsApp Business conectado;
- conta Meta/WABA;
- templates aprovados;
- webhook público validado;
- entrega real em telefone;
- consentimento integrado à decisão do worker (o worker atual seleciona cliente ativo, mas não filtra explicitamente `consentimento_whatsapp`).

A fila Flutter `whatsapp_fila` grava status `simulado`; o WhatsApp manual abre o aplicativo externo ou compartilhamento.

Status: **BLOQUEADO POR CREDENCIAL** e **BLOQUEADO POR INFRAESTRUTURA**.

## 9. Matriz de módulos

| Módulo | Tela/funcionalidade | Status real | Local | Nuvem | Outro aparelho | Incompleta | Credencial/externo | Erro principal | Ação necessária |
|---|---|---|---|---|---|---|---|---|---|
| Login | Acesso e sessão persistente | FUNCIONAL SOMENTE LOCAL | Sim | Não no fluxo principal | Não | Sim | Backend | Autentica no SQLite | Unificar login com backend e fallback offline seguro |
| Empresas | Cadastro de comércio | FUNCIONAL SOMENTE LOCAL | Sim | Não comprovado | Não | Sim | Backend | Ambiente nasce local | Provisionamento remoto por transação |
| Usuários | Funcionários e acessos | FUNCIONAL SOMENTE LOCAL | Sim | Não comprovado | Não | Parcial | Backend | Sem validação real multiaparelho | Sincronizar e testar conflitos |
| Permissões | Módulos e ações | FUNCIONAL SOMENTE LOCAL | Sim | Não comprovado | Não | Parcial | Backend | Alguns fluxos antigos não checam ação no repositório | Aplicar autorização em toda mutação |
| Clientes | Cadastro, edição, importação, 360 | FUNCIONAL SOMENTE LOCAL | Sim | Não comprovado | Não | Parcial | Contatos do aparelho opcional | Sem teste remoto | Sincronizar e homologar |
| Anamnese | Ficha da cliente | NÃO IMPLEMENTADO | Não | Não | Não | Sim | Fotos/arquivos futuramente | Tela placeholder | Implementar modelos, respostas, mídia, assinatura e histórico |
| Agenda | Criar, editar, conflitos, bloqueios, recorrência | FUNCIONAL SOMENTE LOCAL | Sim | Não comprovado | Não | Parcial | Backend para online | E2E remoto ausente | Homologar e reforçar transações |
| Cancelar | Status e histórico | PARCIAL | Sim | Não comprovado | Não | Sim | Backend/WhatsApp | Sem motivo e sem cancelar lembrete enfileirado | Criar fluxo transacional completo |
| Excluir | Remoção de agendamento | PARCIAL | Sim, perigoso | Não | Não | Sim | Não | Sem permissão, motivo, auditoria ou checagem de vínculos | Criar exclusão segura/soft-delete auditável |
| Serviços | Cadastro e edição | FUNCIONAL SOMENTE LOCAL | Sim | Não comprovado | Não | Parcial | Backend | Sem E2E remoto | Sincronizar e testar |
| Profissionais | Cadastro, horários e equipe | FUNCIONAL SOMENTE LOCAL | Sim | Não comprovado | Não | Parcial | Backend | Sem E2E remoto | Sincronizar e testar |
| Pacotes | Venda, sessões, agenda, falta, parcelas | FUNCIONAL SOMENTE LOCAL | Sim, 34 testes específicos anteriores | Não comprovado | Não | Parcial | Backend | Sem homologação real | Testar em dois aparelhos e com caixa real |
| Financeiro | Entradas, saídas e resumo | FUNCIONAL SOMENTE LOCAL | Sim | Não comprovado | Não | Parcial | Backend/pagamentos | Confirmação externa ausente | Sincronizar e conciliar |
| Caixa | Abertura e movimentação | FUNCIONAL SOMENTE LOCAL | Sim | Não comprovado | Não | Parcial | Backend | Concorrência remota não testada | Controle de versão e conflito |
| Comissões | Cálculo/listagem | FUNCIONAL SOMENTE LOCAL | Sim | Não comprovado | Não | Parcial | Backend | Sem validação multiaparelho | Homologar fechamento |
| Estoque operacional | Itens e movimentos | FUNCIONAL SOMENTE LOCAL | Sim | Não comprovado | Não | Parcial | Backend | Concorrência remota não testada | Sincronização transacional |
| Estoque loja | Produtos, transferências e vendas | FUNCIONAL SOMENTE LOCAL | Sim | Não comprovado | Não | Parcial | Backend | Concorrência remota não testada | Homologar saldo e conflitos |
| Consignados | Cadastro e fechamento | FUNCIONAL SOMENTE LOCAL | Sim | Não comprovado | Não | Parcial | Backend | Sem homologação real | Testar fornecedor e estorno |
| Código de barras | Scanner e busca | PARCIAL | Parcial | Não | Não | Sim | Fonte externa | Provider oficial sempre retorna null | Implementar consulta backend legal e logs |
| Mensagem manual | WhatsApp/compartilhar | FUNCIONAL SOMENTE LOCAL | Sim | Não | Não aplicável | Parcial | Aplicativo WhatsApp | Não confirma entrega | Manter como fallback explícito |
| Mensagens automáticas | Worker/fila/webhook | BLOQUEADO POR CREDENCIAL | Simulação/teste | Código pronto, não implantado | Não | Sim | Provedor WhatsApp e servidor | Nenhum envio real comprovado | Implantar e homologar templates/status |
| Aniversários | Central e ações manuais | FUNCIONAL SOMENTE LOCAL | Sim | Automação bloqueada | Não | Parcial | WhatsApp/backend | 8h/9h não homologados | Implantar worker e provar não duplicidade |
| Relatórios | Resumo financeiro/operacional | FUNCIONAL SOMENTE LOCAL | Sim | Não | Não | Sim | Nenhum | Sem PDF/Excel e poucos cortes | Expandir somente após base consistente |
| Configurações | Comércio, horários, tema e integrações | FUNCIONAL SOMENTE LOCAL | Sim | Não comprovado | Não | Parcial | Backend | Endpoint é manual | Perfis por ambiente e sync |
| Backup local | Backups de migração | PARCIAL | Em upgrades | Não | Não | Sim | Armazenamento seguro | Não é backup diário nem restauração testada | Criar backup verificável e restore |
| Backup backend | Compose diário | BLOQUEADO POR INFRAESTRUTURA | Configuração | Não implantado | Não | Sim | Servidor/storage | Restore nunca testado | Implantar, criptografar e testar restauração |
| Sincronização | Push/pull genérico | BLOQUEADO POR INFRAESTRUTURA | Fila local | API testada localmente | Não | Sim | HTTPS/PostgreSQL/JWT | Sem servidor e sem teste real | Deploy e teste A/B |
| IA local | Indicadores SQLite | FUNCIONAL SOMENTE LOCAL | Sim | Não | Não necessário | Parcial | Nenhum | Escopo limitado | Manter claramente como local |
| IA online | Conversa externa | SIMULAÇÃO | Simulador | Não | Não | Sim | Serviço/credencial | Provider sempre offline | Backend seguro futuro |
| Assinatura | Trial e pagamento | SIMULAÇÃO | Mock | Não | Não | Sim | Gateway | Botão explicitamente simulado | Não usar comercialmente |
| Privacidade | Exportação e pedido de exclusão | PARCIAL | Sim | Não | Não | Sim | Backend | Pedido fica pendente do backend | Implementar processo do titular |

## 10. Itens realmente funcionais

Somente no aparelho/banco local: cadastro e login local, sessão persistente, empresas, usuários, permissões principais, clientes, serviços, profissionais, agenda básica, bloqueios/conflitos, pacotes, caixa, financeiro, comissões, estoque operacional, estoque da loja, consignados, vendas, configurações, relatórios-resumo, IA local, central de aniversários e WhatsApp manual.

## 11. Itens incompletos

- Anamnese completa.
- Cancelamento com motivo e cancelamento de fila.
- Exclusão segura e auditável.
- Autorização uniforme no nível de repositório.
- Backend hospedado e conexão confirmada.
- Login remoto integrado ao fluxo principal.
- Sincronização entre aparelhos e recuperação pós-reinstalação.
- Busca externa real por GTIN e persistência de logs.
- Imagem/unidade/volume no catálogo inteligente.
- Backup diário validado e restauração.
- Consentimento aplicado pelo worker automático.
- Relatórios exportáveis.

## 12. Simulações identificadas

- assinatura e pagamento comercial;
- WhatsApp local enfileirado;
- IA conversacional online;
- conversas/mensagens do simulador;
- provedores externos de pagamento e confirmação;
- catálogo externo oficial, que atualmente retorna ausência sem consultar rede.

## 13. Infraestrutura necessária

- servidor Linux/container continuamente disponível;
- domínio e TLS válido;
- PostgreSQL gerenciado ou operado com monitoramento;
- armazenamento de objetos para fotos/anamneses;
- cofre de segredos;
- backup criptografado fora do servidor e restore testado;
- observabilidade, logs e alertas;
- ambientes separados de desenvolvimento e homologação;
- segundo aparelho de teste.

## 14. Credenciais e serviços externos necessários

- `DATABASE_URL` e `JWT_SECRET` fortes;
- domínio/HTTPS e `PUBLIC_BASE_URL`;
- provedor oficial WhatsApp Business, número, token, segredo, webhook e templates aprovados;
- provedor de e-mail/SMS para recuperação;
- storage S3 compatível para fotos/documentos;
- fonte legal/licenciada de dados GTIN acessada pelo backend;
- credenciais de marketplace/afiliados somente se essas integrações forem homologadas;
- gateway de pagamento somente quando assinatura deixar de ser mock.

## 15. Arquivos previstos para correção

A lista exata poderá crescer após o desenho da migração, mas o núcleo esperado é:

- `lib/screens/anamnese_page.dart`;
- novos modelos e `lib/repositories/anamnese_repository.dart`;
- nova migração SQLite versionada e `database_schema_latest.dart`;
- `lib/screens/agenda_page.dart`;
- `lib/repositories/agenda_repository.dart`;
- `lib/repositories/agenda_completa_repository.dart`;
- permissões em `lib/models/domain/acesso.dart` e fluxo de usuários;
- `lib/services/backend_sync_service.dart`;
- `lib/screens/acesso_page.dart` e `lib/repositories/acesso_repository.dart`;
- `lib/services/product_lookup_service.dart`;
- `lib/screens/commercial_center_page.dart` e cadastro de catálogo;
- endpoints/migrações do backend para anamnese, exclusão auditável e catálogo externo;
- worker de mensagens para consentimento e cancelamento;
- novos testes de migração, anamnese, agenda segura, catálogo e sincronização.

## 16. Plano de correção por prioridade

1. Congelar nova Sprint e fazer backup verificável do código e banco de homologação.
2. Implementar anamnese ponta a ponta com migração aditiva, modelos por estabelecimento, respostas versionadas, fotos/assinatura e histórico.
3. Separar cancelamento de exclusão: motivo obrigatório, permissão, auditoria imutável, verificação de vínculos e cancelamento de mensagens.
4. Implantar backend de homologação real com PostgreSQL, TLS, secrets e backups; não usar dados reais em desenvolvimento.
5. Integrar o login do aplicativo ao backend preservando modo offline seguro e tokens em secure storage.
6. Corrigir/validar sincronização de todas as novas tabelas e conflitos; executar teste real em dois aparelhos e reinstalação de teste.
7. Implementar busca GTIN externa somente pelo backend, com fonte legal, timeouts, cache, origem, logs sem segredo e fallback manual após falha total.
8. Configurar WhatsApp Business oficial, consentimento, templates e webhook; validar entrega real e cancelamento de pendências.
9. Executar regressão completa, testes de carga e homologação de um dia nos três estabelecimentos.
10. Somente então gerar novo APK e avaliar avanço de Sprint.

## 17. Decisão de auditoria

**NÃO APROVADO PARA HOMOLOGAÇÃO REAL AINDA.**

Os testes automatizados estão verdes, mas os critérios críticos de anamnese, exclusão segura, backend real, dois aparelhos, recuperação pós-reinstalação, catálogo externo e WhatsApp oficial não foram atendidos. Um novo APK não deve ser gerado até essas correções serem implementadas e testadas.
