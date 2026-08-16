# ADR-0016 — Failover controlado entre providers com continuidade de feature

- **Status:** accepted
- **Date:** `2026-08-13` (aceito em `2026-08-16`)
- **Owner:** Equipe do Ralph Method

## Contexto

O loop atual reconhece limites de uso, espera o reset e repete a mesma fase sem
consumir ciclo de correção. O control plane também preserva árvores parciais e
cria nova `attempt`, lease e fencing durante recovery. Apesar dessas bases, a
política multiprovider aceita hoje apenas seleção inicial e registra
`fallback_policy=none`.

Workflows longos podem ficar ociosos quando o Codex atinge rate limit mesmo que
um OpenCode funcional, configurado e independente esteja disponível. A mudança
precisa aumentar continuidade sem permitir troca silenciosa, sessão
concorrente, perda de contexto ou bypass dos gates. O desenho completo está em
[`provider-failover-continuity-plan.md`](../architecture/provider-failover-continuity-plan.md).

## Opções consideradas

| Opção | Vantagens | Desvantagens |
|---|---|---|
| **A — Manter apenas espera do mesmo runner** | Menor superfície e comportamento já comprovado | Desperdiça capacidade alternativa e pode deixar workflows longos parados |
| **B — Trocar o engine dentro da mesma sessão/tentativa** | Retomada aparentemente rápida | Reutiliza autoridade, mistura contratos, dificulta fencing e pode manter dois processos vivos |
| **C — Failover explícito pelo controlador, em nova attempt** | Preserva árvore e contexto com autoridade, ledger, readiness e limites verificáveis | Exige novos contratos, eventos, fixtures e campo real |
| **D — Executar providers em paralelo e aceitar o primeiro** | Reduz latência de falhas | Duplica custo, cria escrita concorrente e viola a exclusividade por feature |

## Decisão

Adotamos a opção C.

O default permanece `fallback_policy=none`. Um workflow poderá optar por uma
cadeia versionada `explicit_failover`. Na primeira versão, somente
`provider_usage_limited` com classificação de alta confiança autoriza Codex →
OpenCode. O resultado de runner será um contrato único, pela evolução de
`schemas/runner-result.schema.json`, e não um segundo envelope concorrente.

A troca é uma transição do `ralph-control`, nunca do runner ou adapter. Ela
exige término comprovado do processo anterior, cápsula sanitizada e
regenerável, readiness do destino, domínios de falha distintos com identidade
`observed|exact` e nova `attempt`, lease, sessão,
`execution_id` e fencing token. A árvore parcial e a especificação original
são a fonte de continuidade; o handoff intermediário não transporta código,
prompts ou respostas.

Quando a política estiver ativa, `ralph.sh` devolve o rate limit ao controlador
e não permanece dormindo nem relança o provider por conta própria. Circuit
breakers derivados do ledger impedem flapping e permitem que features
seguintes usem o primeiro runner elegível durante o cooldown. Cadeia esgotada
entra em espera de capacidade com heartbeat e termina em `recovery_required`
quando exceder o horizonte sem progresso ou encontrar condição insegura.

## Consequências

### Positivas

- workflows longos podem continuar durante rate limits recuperáveis;
- o trabalho parcial não precisa ser refeito nem serializado em texto;
- toda troca fica auditável no ledger, trace, cápsula e handoff final;
- a autoridade continua exclusiva do controlador;
- o default de instalações e workflows existentes não muda;
- o desenho serve como seam para Claude futuro sem incluí-lo prematuramente.

### Negativas

- o schema de eventos e a projeção ganham novos estados;
- cada runner precisa publicar um `runner-result` comum confiável;
- perfis precisam permitir que o readiness observe o domínio de falha sem
  persistir identificadores sensíveis;
- o OpenCode precisa de modelo, agente e proof read-only configurados antes do
  failover;
- fixtures de relógio, crash, processo e concorrência aumentam o custo da
  regressão;
- não é possível prometer execução infinita quando todos os providers estão
  indisponíveis ou não há progresso.

### Obrigações

- nenhum fallback para gate vermelho, autenticação inválida ou erro ambíguo;
- nenhum processo novo antes do término do anterior;
- nenhum domínio de quota inferido por nome de modelo ou aceito apenas por
  declaração textual;
- nenhuma promoção sem fixture offline, adversarial, regressão completa e
  campo em worktree descartável do `refactor-radar`;
- `STATUS` e `AGENT_GUIDE` só mudam para comportamento implementado depois da
  prova final.

## Gatilho para revisitar

Revisitar a cadeia inicial quando ocorrer um destes fatos observáveis:

- dois incidentes independentes mostrarem que Codex e OpenCode compartilham o
  mesmo domínio de indisponibilidade;
- Claude CLI estiver funcional, em domínio distinto, e houver uma prova de
  campo que justifique terceiro runner;
- um provider passar a expor quota estruturada por modelo, permitindo avaliar
  failover dentro do mesmo runner sem inferência;
- o Ralph precisar coordenar o mesmo workflow entre hosts, tornando o ledger
  local insuficiente.
