# WhatsApp e IA

Contratos definidos: `WhatsAppProvider`, `AiAssistantProvider`, `ConversationRepository`, `MessageRepository` e `AutomationRepository`.

`SimulatedWhatsAppProvider` grava mensagens locais com status `simulado`. `OfficialWhatsAppProvider` interrompe claramente se não houver backend. Nenhuma automação de WhatsApp Web é usada.

Produção deverá usar API oficial WhatsApp Business por backend, templates aprovados, consentimento, webhooks autenticados, limitação de taxa e atendimento humano. A IA deve consultar dados do comércio pelo backend e responder apenas com fatos disponíveis; o fallback transfere para humano.
