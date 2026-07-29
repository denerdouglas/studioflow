# Plano de Migração para Backend

1. Criar ambientes development/staging/production e cofre de segredos.
2. Replicar entidades por `businessId`, mantendo catálogo global em domínio separado.
3. Consumir `fila_sincronizacao` com idempotência, versionamento e resolução de conflito.
4. Migrar catálogo/sugestões e ativar moderação administrativa.
5. Integrar assinatura e webhooks de pagamento em staging.
6. Integrar WhatsApp oficial e IA com auditoria.
7. Ativar área do cliente por flags remotas após pentest e revisão LGPD.

Dados SQLite continuam sendo a fonte offline até confirmação de sincronização. Nunca apagar localmente antes de recibo remoto consistente.
