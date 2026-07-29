# Relatório final — Sprint 6 (continuação)

Data da validação: 29/07/2026
Versão pública: 1.1.0
Build do projeto: 2008
Banco SQLite: versão 8
Plataforma entregue: Android ARM64-v8a

## Resultado executivo

A continuação foi aplicada sobre o projeto existente, sem recriar a aplicação nem apagar dados. Foi criado previamente um checkpoint lógico integral do código. O login deixou de exigir o ID do comércio, contas com o mesmo login em mais de um estabelecimento são identificadas e o usuário escolhe em qual entrar. Cadastro, sessão persistente, logout, recuperação local de senha, tipo de estabelecimento e identidade visual por comércio foram concluídos e testados.

O APK foi instalado como atualização sobre a versão existente no aparelho. O `firstInstallTime` permaneceu em 13/07/2026, confirmando que não houve desinstalação ou limpeza de dados. O aplicativo iniciou com processo ativo e sem `FATAL EXCEPTION` ou `SQLiteException` no log da abertura.

## Backup lógico antes das alterações

- Arquivo: `D:\projeto salao\studioflow\.checkpoints\studioflow_pre_continuacao_sprint6_20260729.zip`
- SHA-256: `7BD4E70E68BC9A60DACFCE6B8A6D2EF28ED61D61FE50E2089930A8D9BDC69C77`

## Implementado nesta continuação

### Acesso multiestabelecimento

- Login somente por e-mail/login e senha, sem solicitar ID do comércio.
- Identificação automática de todas as contas compatíveis.
- Seletor de estabelecimento quando o login pertence a mais de um comércio.
- Sessão persistente após a escolha.
- Logout e invalidação segura de sessões.
- Recuperação local de senha com validação do telefone já cadastrado, nova hash/salt e auditoria de tentativas.
- Cadastro inicial com seleção do segmento do estabelecimento.

### Segmentos

Foram adicionados: salão, barbearia, estética, nail designer, lash designer, podologia, spa, massagem, micropigmentação, bronzeamento e outro.

### Marca e aparência

- Nova tela `Configurações > Aparência`.
- Seleção de logo pela galeria ou câmera.
- Recorte quadrado da imagem.
- Cópia definitiva da logo para a área de documentos do aplicativo.
- Extração local das três cores dominantes, sem API externa.
- Cores principal, secundária e de destaque editáveis manualmente.
- Tema automático, claro, escuro ou conforme o sistema.
- Restauração das cores a partir da logo.
- Tema isolado e persistido por estabelecimento.
- Aplicação dinâmica do tema no aplicativo após salvar.

### Persistência e isolamento

- Migração SQLite v8 aditiva e versionada.
- Backup lógico das tabelas críticas antes da atualização v7→v8.
- Nenhum dado antigo é removido pela migração.
- Índice global para busca de login ativo, preservando duplicidade permitida entre comércios.
- Auditoria de recuperação de senha.
- Estrutura explícita para dispositivos/sincronização futura, desativada até existir backend seguro.
- Teste com três estabelecimentos confirmou contas e clientes isolados por `comercio_id`.

### Funcionalidades existentes preservadas

Foram mantidos os módulos já existentes de agenda, clientes/360/anamnese, serviços, usuários/permissões, caixa/financeiro, estoque operacional, estoque da loja, consignação, vendas, central de reposição, mensagens, Pix, localização, contatos e IA local. Não houve reimplementação desses módulos.

## Migração criada

`MigrationV8` adiciona em `comercios`:

- `tipo_estabelecimento`
- `logo_path`
- `cor_principal`
- `cor_secundaria`
- `cor_destaque`
- `tema_modo`
- `tema_automatico`

Novas tabelas:

- `recuperacoes_senha`
- `dispositivos_sincronizacao`

Novos índices:

- `idx_usuarios_login_global`
- `idx_recuperacoes_usuario`

## Arquivos criados

- `lib/database/migrations/migration_v8.dart`
- `lib/models/domain/aparencia.dart`
- `lib/repositories/aparencia_repository.dart`
- `lib/services/marca_service.dart`
- `lib/screens/aparencia_page.dart`
- `test/sprint6_continuacao_test.dart`
- `test/sprint6_v8_migration_test.dart`
- `SPRINT_6_CONTINUACAO_REPORT.md`

## Arquivos alterados

- `lib/core/constants/database_constants.dart`
- `lib/database/database_schema_latest.dart`
- `lib/models/domain/acesso.dart`
- `lib/repositories/acesso_repository.dart`
- `lib/screens/acesso_page.dart`
- `lib/screens/configuracoes_page.dart`
- `lib/screens/app_bootstrap_page.dart`
- `lib/app.dart`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/build.gradle.kts`
- `pubspec.yaml`
- `pubspec.lock`
- `test/sprint2_test.dart`

## Dependências adicionadas

- `image_picker` — galeria e câmera.
- `image_cropper` — recorte da logo.
- `path_provider` — armazenamento definitivo no diretório do aplicativo.
- `image` — leitura e extração local de cores.

## Validação

- `flutter pub get`: concluído.
- `dart format lib test`: 144 arquivos verificados; nenhum pendente.
- `flutter analyze --no-pub`: concluído, `No issues found`.
- `flutter test --no-pub`: 43/43 testes aprovados.
- Migração real de teste v6→v7→v8: aprovada, com dados, sessão e configurações preservados.
- Cenário com três estabelecimentos: aprovado.
- Build `release` ARM64-v8a: concluído.
- Instalação ADB com `-r`: `Success`.
- Versão instalada: `versionName=1.1.0`, `versionCode=4008` (código final ajustado pelo split ARM64 do Flutter).
- Primeiro horário de instalação preservado: `2026-07-13 17:06:10`.
- Processo após abertura: ativo.
- Erros fatais/SQLite na abertura: nenhum encontrado.

Avisos não bloqueantes do build:

- `mobile_scanner` e `share_plus` ainda aplicam o Kotlin Gradle Plugin legado; uma versão futura do Flutter exigirá atualização desses plugins.
- As ferramentas de linha de comando e o XML do SDK Android estão em gerações diferentes; o build concluiu normalmente.
- O Android SDK está em um caminho com espaço. O build atual funciona, mas uma futura compilação NDK pode exigir mover o SDK para um caminho sem espaços.

## APK final

- Caminho: `D:\projeto salao\studioflow\releases\StudioFlow-1.1.0-sprint6-continuacao-arm64-v8a-release.apk`
- Tamanho: 29.358.498 bytes (aprox. 28,0 MB)
- SHA-256: `CA69847A69116ECADF86588E8227DBD796E6EEF64105BC5EB3C6F213D32BA6D0`

## Como testar

1. Em uma instalação nova, toque em `Cadastrar comércio` e preencha os dados do negócio, responsável, segmento, login e senha.
2. Nos próximos acessos, informe somente `E-mail ou login` e `Senha`.
3. Se o mesmo login existir em mais de um comércio, escolha a unidade exibida pelo aplicativo.
4. Abra `Configurações > Aparência`, selecione a logo, recorte, confira as cores sugeridas e salve.
5. Feche e reabra o aplicativo para confirmar sessão, dados e tema persistentes.

## Limitações honestas restantes

- Sincronização real entre aparelhos e restauração após troca de aparelho ainda dependem de um backend multiempresa autenticado. A fila/cache local e os contratos de integração existem, mas o envio online continua explicitamente desativado; nenhum dado é fingido como sincronizado.
- Recuperação remota por e-mail/SMS exige backend e provedor homologado. A entrega atual é recuperação local validada pelo telefone cadastrado.
- Mensagens automáticas oficiais do WhatsApp exigem backend, credenciais da Meta, templates aprovados e webhooks. O aplicativo mantém mensagens manuais/simuladas e apresenta aviso claro quando o serviço oficial não está configurado.
- Pacotes com saldo de sessões, validade e agendamentos automáticos ainda não possuem módulo completo no código atual.
- Comparação automática de preços de Shopee, Mercado Livre e Amazon depende de APIs/programas oficiais; a central atual não inventa preço, avaliação, prazo ou frete.
- Não há keystore comercial configurada. O APK de validação usa o fallback de assinatura já previsto no projeto; antes de publicar em loja, deve ser assinado com uma chave release externa e protegida.
- Teste físico em um segundo aparelho não foi possível sem outro dispositivo conectado e sem backend. O isolamento local de três estabelecimentos foi coberto automaticamente.

Nenhuma chave, token ou senha externa foi inserida no aplicativo. A Sprint 7 não foi iniciada.