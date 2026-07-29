# Arquitetura de Assinatura

Plano único: 30 dias grátis e R$ 24,99/mês. Estados persistidos: `trial`, `active`, `pending`, `overdue`, `gracePeriod`, `suspended`, `canceled`.

`PaymentProvider` desacopla cobrança do domínio. A v1.0 usa somente `MockPaymentProvider`; não cobra, não agenda renovação e não armazena cartão. Eventos ficam em `assinatura_eventos` para auditoria.

Integrações reais com Pix, Mercado Pago, Stripe ou gateway brasileiro exigem backend, webhook assinado, idempotência, credenciais fora do APK, termos aceitos e homologação. Não devem ser ativadas apenas por feature flag local.
