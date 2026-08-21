# Trace Cockpit

UI do Ralph Method. Observa JSONL, ledger e `ralph-monitor`.
Não aprova gates nem escolhe a próxima feature. `supervise` só com
preflight verde. Com a fila travada, **Diagnosticar** e **Retomar
orquestrador** falam com o `ralph-control` (`debug` read-only, `recover`,
depois `supervise --debug-command`). O diagnóstico lê o stderr do
supervisor; se o `plan.md` declarado estiver ausente, o preflight
recusa novo disparo — recover não cria o arquivo.

## Prova de campo (FEATURE-100)

O checkout observado executa trabalho **real** (campo Cursor, superfícies v1,
hero flow browser). A FEATURE-099 permanece como smoke de contrato
(manifesto/preflight) — use `--fixture-099` no bootstrap se precisar só disso.

```bash
# no repositório ralph-method (branch feat/trace-cockpit)
bash scripts/bootstrap-cockpit-field.sh --reset

# apps/cockpit/.env
RALPH_PROJECT_ROOT=/tmp/ralph-cockpit-field
RALPH_CONTROL_BIN=/caminho/para/ralph-method/bin/ralph-control
```

Features do workflow `wf_trace_cockpit_hero` (default):

| Feature | Fase | Foco |
|---|---|---|
| `FEATURE-100A-CURSOR-FIELD` | 1 | campo opt-in Cursor (`BL-0004`) |
| `FEATURE-100B-COCKPIT-SURFACES` | 2 | memória, delegação, visões Eventos/Gates |
| `FEATURE-100C-COCKPIT-HERO-FLOW` | 3 | Rodar/Diagnosticar/Retomar no browser |
| `FEATURE-100D-COCKPIT-RELEASE` | 4 | adversarial, relatório, docs |

Especificação: `.spec/features/100-trace-cockpit-hero/` (`PLAN.md`, `PHASES.md`,
`workflow.json`). Smoke legado: `.spec/features/099-cockpit-field/` +
`bash scripts/bootstrap-cockpit-field.sh --fixture-099`.

Depois do bootstrap: `ralph:ingest --rebuild`, servidores locais e **Rodar Ralph**
no browser. O diagnóstico lê stderr do supervisor; se o plano declarado estiver
ausente, o preflight recusa novo disparo — recover não cria o arquivo.

## Local (SQLite + Vite)

```bash
cd apps/cockpit
cp .env.example .env
php artisan key:generate
# para dev rápido sem Docker:
# DB_CONNECTION=sqlite
php artisan migrate
npm install
npm run build
php artisan ralph:ingest --rebuild
php artisan serve --host=127.0.0.1 --port=8000
```

Em terminais separados, para ao vivo (os dois precisam estar no ar):

```bash
php artisan reverb:start --host=127.0.0.1 --port=8080
php artisan ralph:ingest --follow
```

`--no-broadcast` no ingestor desliga o Reverb de propósito. O Vite não
expande `${REVERB_*}`; as variáveis `VITE_REVERB_*` precisam de valor
literal, ou o layout injeta a config do PHP em `window.RalphCockpit`.

## Docker (Postgres + Reverb)

```bash
cd apps/cockpit
docker compose up --build
docker compose exec app php artisan migrate --force
docker compose exec app php artisan ralph:ingest --rebuild --follow
```

Abra `http://127.0.0.1:8000`. O checkout observado é montado em
`/ralph-project` somente leitura.

A suíte do núcleo (`scripts/ci-portable.sh`) não sobe este app.
