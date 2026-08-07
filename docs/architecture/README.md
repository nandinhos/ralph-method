# Arquitetura do Ralph Method

O Ralph Method é um framework local instalado dentro de um projeto-alvo. O
`bc-harness` distribui o instalador, mas não se torna dependência de runtime.

## Documentos

- [boundaries.md](boundaries.md) — componentes e seams;
- [data-model.md](data-model.md) — manifestos, ledger e ownership;
- [interfaces.md](interfaces.md) — CLI, events e providers.

## Princípio central

```text
executor executa
→ hook observa
→ feedback informa o orquestrador
→ ralph-control retransmite o feedback do bloco
→ ralph-trace normaliza fatos
→ ralph-control registra e valida
→ gates comprovam
→ ralph-control decide
```

O trace não aprova, não libera e não escolhe a próxima feature.
