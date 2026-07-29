# Relatório Final — Sprint 6

Data: 22/07/2026  
Versão: `1.0.0+6`  
SQLite: versão 6  
Status: concluída para validação local/comercial; publicação bloqueada somente por dependências externas e assinatura de produção.

## 1. Diagnóstico e checkpoint

- Checkpoint pré-Sprint: `C:\studioflow\.checkpoints\studioflow_pre_sprint6_20260722.zip`.
- SHA-256 do checkpoint: `0BADFD0E5F188ED760C9C385E1222F11C862614BC5A2A93C6068CBF4FBC573D3`.
- Foi identificado que estoque operacional e Loja do Salão usavam a mesma tabela sem discriminador persistido. A v6 adiciona `estoque_destino` e todos os repositórios passaram a filtrar `salao` ou `loja` explicitamente.
- Dados legados foram preservados. Itens com campos comerciais inequívocos são classificados como loja; os demais permanecem no estoque operacional.

## 2. Implementações

- Assinatura de plano único: trial de 30 dias, R$ 24,99/mês, sete estados, histórico e `MockPaymentProvider` sem cobrança/cartão.
- Central Comercial 1.0 visível no menu, com assinatura, termos, histórico, checklist de 15 áreas, catálogo e flags.
- Catálogo Mestre global sem dados privados; variações por GTIN; cache offline com expiração.
- `ProductCatalogProvider` e implementações Local, StudioFlow, Official, Community e Mock.
- `ProductLookupService`: normalização, GTIN-8/12/13/14, dígito verificador, prioridade/confiança, cache e prévia.
- Leitura pela câmera na Central Comercial, cadastro manual, escolha Salão/Loja, código interno, dados locais e contribuição opcional.
- Sugestões comunitárias pendentes, consentimento, auditoria e fila offline idempotente; sem publicação automática.
- Mesmo GTIN permitido em comércios diferentes, mantendo preço/estoque/fornecedor privados.
- Carrinho preparado; rejeita estoque operacional e baixa exclusivamente estoque da loja.
- Cardápio funcional: criar, editar, ativar/desativar, excluir com confirmação e adicionar complementos.
- Privacidade/LGPD: explicação, exportação cadastral em JSON e solicitação de exclusão com confirmação.
- Contratos seguros para WhatsApp oficial, IA, conversas, mensagens, automações e ambientes; somente modo simulado local.
- Perfil/área do cliente, salões próximos, WhatsApp oficial, IA online, OCR e cloud sync preparados e desligados por flags.
- Identidade comercial: ícone original, mipmaps, ícone Play 512 px e splash roxo StudioFlow.
- `applicationId` atual preservado para permitir atualização da instalação existente.

## 3. Migração v6

Alteração aditiva em `estoque`: `estoque_destino TEXT NOT NULL DEFAULT 'salao'`.

Novas tabelas:

- `catalogo_produtos`, `catalogo_variacoes`, `catalogo_cache`;
- `catalogo_sugestoes`, `catalogo_auditoria`;
- `assinaturas`, `assinatura_eventos`, `progresso_configuracao`;
- `feature_flags`;
- `cardapio_itens`, `cardapio_complementos`;
- `perfis_clientes`;
- `carrinhos`, `carrinho_itens`;
- `consentimentos_privacidade`, `solicitacoes_privacidade`;
- `whatsapp_fila`.

Antes da migração v5→v6 são gravados backups lógicos de comércios, usuários, configurações, estoque, fila e configuração de integrações.

## 4. Arquivos criados

- `lib/database/migrations/migration_v6.dart`
- `lib/services/product_lookup_service.dart`
- `lib/integrations/commercial_integrations.dart`
- `lib/repositories/commercial_repository.dart`
- `lib/repositories/catalog_registration_repository.dart`
- `lib/repositories/cardapio_repository.dart`
- `lib/repositories/customer_cart_repository.dart`
- `lib/repositories/privacy_repository.dart`
- `lib/screens/commercial_center_page.dart`
- `lib/screens/catalog_registration_page.dart`
- `lib/screens/cardapio_page.dart`
- `lib/screens/privacy_page.dart`
- `test/sprint6_test.dart`
- `test/sprint6_cart_test.dart`
- `test/sprint6_migration_test.dart`
- `assets/branding/studioflow-icon-v6.png`
- `assets/branding/studioflow-play-icon-512.png`
- `android/app/src/main/res/values/colors.xml`
- documentação técnica em `docs/`.

## 5. Principais arquivos alterados

- `pubspec.yaml` (`1.0.0+6`) e `pubspec.lock`.
- `lib/database/database_schema_latest.dart` e `lib/core/constants/database_constants.dart`.
- `lib/repositories/acesso_repository.dart`.
- `lib/models/domain/loja.dart`.
- repositórios de estoque, loja, compras, consignação, reposição e produto/fornecedor.
- `lib/screens/mais_sprint2_page.dart`.
- recursos Android `ic_launcher.png` e `launch_background.xml`.

## 6. Testes e análise

- `flutter pub get`: sucesso.
- `dart format lib test`: sucesso.
- `flutter analyze --no-pub`: **No issues found**.
- `flutter test --no-pub`: **33/33 testes aprovados**.
- Cobertura funcional nova: migração v5→v6/backup, trial, pagamento mock, GTIN, cache/providers, isolamento multiempresa, catálogo sem campos privados, flags, carrinho e separação de estoques.

## 7. Builds finais

APK:

- Caminho: `C:\studioflow\releases\StudioFlow-1.0.0-sprint6-arm64-v8a-release.apk`
- Tamanho: 27.387.475 bytes.
- SHA-256: `BFD8551204D8FACF7080E6FC22B011C0129ADFE66943DAD6EA837BF995F1671D`
- ABI: somente `arm64-v8a`.
- Pacote: `com.example.studioflow`; versionName `1.0.0`; versionCode do APK split `2006`; minSdk 24; targetSdk 36.
- Assinatura APK v2 válida; certificado `Android Debug`.

AAB:

- Caminho: `C:\studioflow\releases\StudioFlow-1.0.0-sprint6-arm64-release.aab`
- Tamanho: 29.597.231 bytes.
- SHA-256: `69A3428ACC4A306769907F8DBB1D37181F48039690C6BC7255F9AE7F9CE92BD4`
- `jarsigner`: `jar verified`, com certificado autoassinado/debug.

## 8. Validação física

- Aparelho: `2410FPCC5G`, Android 16, serial `WW4L6PQ4HYSCSSF6`.
- Instalação como atualização: `adb install -r` → `Success`.
- `firstInstallTime` permaneceu `2026-07-13 17:06:10`, comprovando preservação da instalação.
- Sessão e comércio preservados: Rafaela / Rafa Salao / `SF16447489`.
- Central Comercial abriu com R$ 24,99, 30 dias, checklist de 15 áreas e assinatura mock.
- Sem `FATAL EXCEPTION`, `E/flutter`, `DatabaseException` ou `SQLiteException`.

## 9. Como testar

1. Instale o APK acima como atualização.
2. Abra `Mais` → `StudioFlow Comercial 1.0`.
3. Teste termos, histórico, pagamento simulado e checklist.
4. Em Catálogo Inteligente, digite um GTIN válido ou use o ícone da câmera.
5. Confirme a prévia ou use Cadastro Manual; escolha Estoque do Salão ou Estoque da Loja.
6. Abra `Mais` → `Cardápio do Salão` para criar item/complemento.
7. Abra `Mais` → `Privacidade e LGPD` para exportar dados ou registrar solicitação.

## 10. Limitações e bloqueios externos

- Pagamento real não foi ativado: exige gateway, backend, webhooks e credenciais seguras.
- WhatsApp oficial e IA online não foram ativados: exigem backend e API oficial.
- Área do cliente e salões próximos permanecem desativados por segurança/LGPD.
- OCR real e sincronização cloud permanecem desativados; cadastro/cache/fila funcionam offline.
- `applicationId` ainda é `com.example.studioflow`; foi preservado para não quebrar atualizações. A decisão sobre identificador comercial deve ocorrer antes da primeira publicação.
- Não existe keystore de produção. APK/AAB usam o certificado debug atual e **não devem ser publicados** assim.
- Build emitiu aviso futuro do `mobile_scanner` sobre Built-in Kotlin e aviso de diferença entre versões XML do SDK; ambos não impediram build/teste.
- iOS não foi compilado no Windows; preparação documentada.

Sprint 7 não iniciada.
