# Checklist Play Store

- [x] Nome exibido: StudioFlow.
- [x] Versão: 1.0.0; versionCode 6.
- [x] Ícone próprio 512 px e mipmaps Android.
- [x] Splash com identidade StudioFlow.
- [x] Permissão de câmera declarada como hardware opcional.
- [x] Fluxo local de privacidade/exportação/exclusão.
- [x] APK ARM64 e AAB previstos no pipeline final.
- [ ] Definir applicationId comercial. `com.example.studioflow` foi preservado para permitir atualização da instalação atual; trocar cria outro aplicativo.
- [ ] Fornecer keystore de produção. O build local usa a chave já configurada ou fallback debug e nunca substitui chave sem autorização.
- [ ] Publicar URL da política de privacidade e página web de exclusão.
- [ ] Preencher Data Safety, classificação etária, público-alvo, ficha e capturas.
- [ ] Criar conta Play Console, teste interno e revisão pré-lançamento.

Não publicar o AAB se ele estiver assinado com fallback debug.
