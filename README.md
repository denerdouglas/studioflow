# studioflow

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Assinatura Android de produção

O projeto não armazena senhas ou chaves no código. Para gerar um APK assinado para publicação, forneça `android/key.properties` (ignorado pelo Git) com `storeFile`, `storePassword`, `keyAlias` e `keyPassword`, ou defina as variáveis `STUDIOFLOW_KEYSTORE_PATH`, `STUDIOFLOW_KEYSTORE_PASSWORD`, `STUDIOFLOW_KEY_ALIAS` e `STUDIOFLOW_KEY_PASSWORD`.

Sem essas credenciais, o build release usa a chave de depuração somente para produzir um APK de validação instalável. Backend, Firebase, assinaturas, painel administrativo e Marketplace StudioFlow permanecem contratos preparados, não integrações ativas.