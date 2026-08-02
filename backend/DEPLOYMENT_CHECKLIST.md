Consulte também PRODUCTION_RUNBOOK.md para o procedimento completo, variáveis, DNS, Meta, Resend e catálogo GTIN.

# Gate operacional — Sprint 7 / Fase 1

A Fase 1 só pode ser considerada operacional após todos os itens abaixo.

## Infraestrutura

- [ ] PostgreSQL de staging provisionado.
- [ ] `DATABASE_URL` injetada pelo cofre de segredos.
- [ ] Migrações `001` e `002` executadas.
- [ ] Usuários separados para migration, runtime e backup.
- [ ] RLS validado com pelo menos três estabelecimentos.
- [ ] Domínio e DNS configurados.
- [ ] API publicada atrás de HTTPS (Proxy reverso).
- [ ] Rota `GET /health` validada externamente (Health Check).
- [ ] Logs centralizados e alertas de erro ativos.
- [ ] Backup automático executado.
- [ ] Restauração de backup validada.

## Aplicativo e sincronização

- [ ] Aplicativo conectado ao endpoint de staging.
- [ ] Carga inicial enviada sem mistura de comércio.
- [ ] Alteração offline sincronizada ao recuperar internet.
- [ ] Refresh token rotacionado.
- [ ] Conflito concorrente exibido sem sobrescrita silenciosa.
- [ ] Segundo aparelho restaurado a partir do backend.
- [ ] Logout revoga sessão online.

## Provedores externos

- [ ] E-mail de recuperação homologado.
- [ ] SMS de recuperação homologado.
- [ ] Meta WhatsApp Cloud API homologada.
- [ ] Webhook Meta protegido por assinatura.
- [ ] Armazenamento S3 compatível com versionamento e retenção.
- [ ] Contas oficiais/afiliadas de Shopee, Mercado Livre e Amazon aprovadas.

## Segurança

- [ ] `JWT_SECRET` aleatório com no mínimo 64 caracteres.
- [ ] Nenhum segredo presente no APK ou repositório.
- [ ] TLS obrigatório fora de localhost.
- [ ] Testes de autorização horizontal e vertical aprovados.
- [ ] Política de retenção e LGPD revisada.
- [ ] Pentest antes da produção nacional.

A Fase 2 permanece bloqueada enquanto existir qualquer item obrigatório sem
validação.
