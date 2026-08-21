# Ralph Trace Cockpit — design de referência

Mockup da camada de visibilidade. A implementação vive em `apps/cockpit/`
e segue o [ADR-0022](../../adr/0022-cockpit-somente-leitura.md).

| Arquivo | Papel |
|---|---|
| `Ralph Trace Cockpit.dc.html` | **Canônico.** Tokens, motion, três visões, tipografia Space Grotesk + JetBrains Mono. |
| `uploads/ralph-trace-web.html` | Export estático para preview rápido. Fallback Inter — não copiar a fonte. |
| `support.js` | Runtime do `.dc.html`; não entra no produto. |

Rodapé do mockup, que vira regra de produto:

> a interface real nunca aprova gates, altera leases ou inicia features.
