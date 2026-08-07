# Interfaces do Ralph Method

## CLI mínima

```text
ralph-init plan --project <path>
ralph-init apply --project <path> --provider auto|codex|claude|opencode
ralph-doctor --project <path>
bin/ralph-control <command> ...
bin/ralph-trace record|report|tree ...
```

## Contrato de provider

Um adapter não grava arquivos de estado. Ele entrega ao controlador os campos:

```text
runner, runner_version, role, execution_id,
requested_model, effective_model, provider,
session_id ou conversation_id,
identity_status, identity_source,
status, reason e fallback_used
```

Quando o provider não expõe modelo efetivo, a identidade deve ser marcada como
`declared`, `observed`, `partial` ou `unavailable`.

## Política de fallback

O padrão é `none`. Fallback precisa estar declarado no manifesto e sempre ser
registrado pelo `ralph-trace`; nenhuma falha pode trocar executor
silenciosamente.
