# ADR-0022 — Cockpit visual somente leitura (Laravel observador)

- **Status:** accepted
- **Date:** `2026-08-16`
- **Owner:** Equipe do Ralph Method

## Contexto

O canal de feedback (`ADR-0002`) e o `ralph-monitor` já publicam fatos
sanitizados, mas a operação ainda depende de CLI e de relatórios pedidos a
um agente. O design `Ralph Trace Cockpit` descreve uma superfície premium
somente leitura. Esta linha quer implantá-la com Laravel 13, Docker,
PostgreSQL e Reverb, observando execução pelo adapter Cursor, sem violar a
fronteira: o núcleo não usa banco de produto, não importa a aplicação-alvo
e não testa o control plane com Laravel.

Escala agora: um operador, um checkout, um browser, dezenas de eventos por
bloco. Futuro plausível: o mesmo cockpit apontado a outro projeto-alvo.
Risco: a UI virar uma segunda autoridade (aprovar gate pelo browser).
Constraint: `scripts/ci-portable.sh` permanece sem Laravel, Postgres ou
credenciais.

## Opções consideradas

| Opção | Vantagens | Desvantagens |
|---|---|---|
| **A — Só CLI** (`monitor`/`metrics`) | zero superfície nova | o problema relatado permanece |
| **B — Livewire no núcleo** (`bin/` ou PHP do control plane) | um processo | mistura Laravel no núcleo portátil; viola o teste sem framework |
| **C — App Laravel isolado em `apps/cockpit/`** | observa JSONL/monitor; Reverb; visual fiel; CI do núcleo intacta | segundo runtime Docker |
| **D — Repo irmão** | isolamento máximo | dual-repo cedo demais para um operador só |

## Decisão

Adotar a opção **C**.

O cockpit é um **consumidor externo** do canal já definido no `ADR-0002` e
nas fronteiras: lê feedback JSONL, ledger JSONL e `ralph-monitor --once
--json`; projeta em PostgreSQL; transmite deltas no Reverb; renderiza o
design em Livewire 4. Não grava ledger, não adquire lease, não escolhe
feature, não troca provider.

O banco é **read-model reconstruível**. A fonte de verdade continua nos
arquivos do `ralph-control`. Apagar o Postgres e reingerir é operação
válida.

A UI **não** aprova gate, não faz retry/advance/release, não
escolhe provider e não grava o ledger. Emenda de 2026-08-16: o cockpit
pode disparar **somente** `ralph-control supervise --workflow {id}`
quando o preflight local estiver verde (checkout gravável, manifesto do
mesmo workflow, fila com feature pendente, working tree limpa, arquivo
de plano declarado presente, sem supervisor ativo). O controlador
continua escolhendo a feature e decidindo os gates.

Emenda posterior (mesmo dia): o cockpit é o **painel administrativo** do
orquestrador — não da fila. Além do `supervise`, a UI pode (1) correr
`ralph-control debug` com o comando read-only `apps/cockpit/bin/ralph-diagnose.php`,
(2) correr `ralph-control recover` quando o cursor está em
`recovery_required` ou `blocked`, e (3) enviar SIGTERM ao supervise que
**este** cockpit iniciou. Continua proibido approve, retry, advance,
release e escolha de feature. Rotas HTTP não expõem esses verbos no URI.

O Compose monta o checkout observado **somente leitura** (no mínimo
`.git/ralph-control/` e `.ralph/knowledge-candidates/`). Nesse modo o
botão fica desabilitado: o preflight falha fechado. Bind de HTTP e
WebSocket em `127.0.0.1`.

## Consequências

### Positivas

- visibilidade ao vivo sem pedir relatório;
- o design vira produto sem copiar autoridade;
- o núcleo portátil permanece testável sem Laravel.

### Negativas

- dois runtimes (PHP CLI do método + PHP-FPM/Sail do cockpit);
- o JSONL grande exige ingestor incremental (já previsto no ADR-0002);
- Reverb e Postgres são dependências de *observação*, não de execução.

### Obrigações

- nenhuma rota POST/PUT/PATCH/DELETE de `approve`, `retry`, `recover`,
  `advance` ou `release`;
- os comandos mutantes permitidos pela UI são `supervise` após preflight
  verde, `debug` com o diagnóstico read-only do cockpit, `recover` quando
  o cursor está travado, e a pausa SIGTERM do processo que o próprio
  cockpit disparou; o cockpit não escolhe a feature;
- `ci-portable.sh` e a suíte do núcleo ignoram `apps/cockpit/`;
- nenhum token, prompt ou resposta completa no banco ou no Echo;
- o `engine` na tela é o valor sanitizado do evento; a UI não seleciona runner.

## Gatilho para revisitar

Revisitar quando (a) um segundo checkout precisar ser observado ao mesmo
tempo, (b) o JSONL de um bloco único passar de 50 MiB com hidratação lenta,
ou (c) houver requisito real de auth além de localhost. Extração então:
processo ingestor separado e/ou autenticação local — sem promover o banco
a fonte de verdade.

## Emenda (2026-08-16)

O hero do cockpit deixou o texto de marketing e passou a exibir o próximo
bloco, o botão **Rodar Ralph** (fail-closed), **Pausar** (SIGTERM no
supervise que o cockpit iniciou) e chips de runtime (Reverb, Laravel,
banco, PHP). Continua proibido qualquer controle de gate.

## Emenda — painel administrativo (2026-08-16)

O hero também é o painel para fazer o orquestrador voltar a correr:
**Diagnosticar** (`ralph-control debug` + `ralph-diagnose.php` read-only)
e **Retomar orquestrador** (`recover` se `recovery_required`/`blocked`,
depois `supervise` com `--debug-command`). Sem comando de debug o
supervise sai na hora em `debugging_required`. O diagnóstico read-only
inspeciona o manifesto, o stderr do supervisor e o ledger: se o
`plan_file` estiver ausente no checkout, a causa é essa — recover não
cria o arquivo, e o preflight recusa novo `supervise`. A autoridade
continua no `ralph-control`; a UI não aprova gate nem escolhe a próxima
feature.

## Emenda — fonte única: stream e controlador (2026-08-21)

O cockpit não utiliza parsing de texto nem expressões regulares em logs de
processo (`exitReasonFromLog`) para determinar razões de término ou falha do
supervisor. A decisão e a observação de estados apoiam-se exclusivamente na
fonte autoritativa do controlador (`ralph-control status`) e no stream de
eventos estruturado (`events.jsonl` / feedback), eliminando heurísticas sobre
logs e unificando a fonte de verdade entre o terminal (`ralph-watch`) e o cockpit.

