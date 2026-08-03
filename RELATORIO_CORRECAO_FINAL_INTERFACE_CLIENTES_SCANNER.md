# Relatório de Correção Final - Interface, Clientes e Scanner

Versão candidata: `1.4.6+4017`
Data: 03/08/2026

## Implementado

- Barra inferior premium com Início, Agenda, Loja e Mais.
- Loja abre a Loja do Salão e Clientes aparece somente em Mais.
- `instagram_url` obrigatório no cadastro e edição, com normalização e abertura do perfil exato.
- Ações condicionais de WhatsApp, Instagram e Telefone na tela premium.
- Edição e inativação com confirmação na tela premium usada em produção.
- Oito entradas migradas para o scanner inteligente centralizado.
- Scanner com código/QR, OCR, prévia sem salvamento automático e digitação manual.
- Parser OCR separa código, preço, produto, material/descrição e fornecedor.

## Já existente e preservado

- Layout premium, tema Light/Dark, cores, cards, tipografia e AppBar.
- Coluna SQLite `instagram_url` desde a migration 17 e persistência no repositório.
- Exclusão lógica e preservação do histórico.
- Busca de produto existente e abertura do cadastro quando não encontrado.

## Validação automatizada

- `flutter analyze`: sem problemas.
- `flutter test`: 129 testes aprovados.
- Backend `dart analyze`: sem problemas.
- Backend `dart test`: 38 testes aprovados.

## Validação manual obrigatória

Pendente da instalação do APK candidato por ADB e conferência no aparelho. O AAB definitivo e o commit final somente serão feitos depois dessa validação.
