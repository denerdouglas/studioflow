# Relatório — Estabelecimento multimodal e IA operacional

Data: 04/08/2026

## Implementado

- Um único estabelecimento pode reunir várias modalidades sem criar comércio, conta ou aplicativo paralelo.
- Modalidades sugeridas e personalizadas possuem nome, descrição, ícone, capa, cor, ordem, favorito, visibilidade na Home e estado ativo/inativo.
- Modalidades podem ser criadas, renomeadas, editadas, reorganizadas, inativadas, restauradas e excluídas apenas quando não possuem vínculos ou histórico.
- Serviços, colaboradores, funções profissionais e estoque podem pertencer a várias modalidades por relações muitos-para-muitos.
- Remover um vínculo não apaga o cadastro principal nem seu histórico.
- A configuração está disponível em Configurações → Modalidades.
- A Home respeita a ordem, favoritos e visibilidade configurados.
- A Agenda permite visão consolidada ou filtro por modalidade.
- Novos estabelecimentos recebem uma modalidade inicial editável; estabelecimentos existentes são migrados sem perda.
- Alterações entram na fila offline de sincronização e registram auditoria.

## Helloa Sophia

- Mantém prévia, confirmação explícita, permissões, idempotência, transação, auditoria e sincronização posterior.
- Entende comandos informais e datas numéricas ou por extenso.
- Cria produtos e lotes com quantidade, validade, códigos, custo, preço, fornecedor, unidade de medida e estoque mínimo quando informados.
- Mesmo código com vencimento diferente reutiliza o produto e cria outro lote.
- Mesmo código e mesmo vencimento não é duplicado silenciosamente.
- Atualiza quantidade, vencimento de lote e preço de serviço.
- Inativa produto somente após mostrar a prévia do registro procurado.
- Transfere saldo por lote entre unidades sem alterar o total agregado do estabelecimento.
- Cria serviço dentro de uma modalidade e vincula colaborador existente a outra modalidade sem duplicá-lo.

## Migração

- Schema local: V28.
- Tabelas: `modalidades_estabelecimento`, `modalidade_servicos`, `modalidade_profissionais`, `modalidade_funcoes` e `modalidade_estoque`.
- `pubspec.yaml` permanece em `1.4.7+4018`.

## Validação

- `flutter analyze`: aprovado, sem ocorrências.
- `flutter test`: 153 testes aprovados.
- Testes direcionados: 14 aprovados.
- Backend `dart analyze`: aprovado, sem ocorrências.
- Backend `dart test`: 44 aprovados e 1 PostgreSQL ignorado porque `POSTGRES_TEST_URL` não está configurada.

## Fora desta entrega local

- Nenhum APK/AAB foi gerado.
- Nenhum push, deploy, acesso à VPS ou publicação na Play Store foi realizado.
