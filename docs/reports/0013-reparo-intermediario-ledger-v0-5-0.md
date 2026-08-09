# Relatório 0013 — reparo intermediário do ledger v0.5.0

**Data:** 2026-08-09
**Versão:** `0.5.0`
**Branch:** `feat/ralph-hardening`
**Escopo:** corrupção no meio de `events.jsonl` e recuperação segura

## Problema

O reparo terminal já preservava o arquivo original e truncava somente o
fragmento final incompleto. Para corrupção no meio, truncar seria inseguro:
eventos posteriores poderiam parecer recuperáveis, mas a hash chain já não
teria continuidade confiável.

## Contrato implementado

Quando a linha inválida não é a última, `ralph-control repair-ledger`:

1. impede reparo se ainda houver processo do workflow ativo;
2. preserva o `events.jsonl` original em backup;
3. grava o prefixo íntegro em um artefato separado;
4. grava a linha inválida e o restante em um sufixo forense;
5. aloca `RPT-YYYY-NNNN` e grava o relatório operacional;
6. retorna `recovery_required` com `requires_manual_restore=true`;
7. não altera o ledger original e não emite transição falsa nele.

## Cenários comprovados

| Cenário | Resultado |
|---|---|
| Fragmento inválido no final | restauração do prefixo, backup e recovery requerido |
| Fragmento inválido no meio | original preservado, prefixo/sufixo separados e relatório |
| Hash do ledger antes/depois do reparo intermediário | idêntico |
| `verify` após corrupção intermediária | continua rejeitando o ledger até restauração explícita |
| Relatório | ID `RPT-YYYY-NNNN`, backup e referências aos artefatos |

## Evidência

```bash
bash scripts/test-ralph-method.sh
```

Saída do checkpoint:

```text
OK: Ralph Method smoke passou.
```

O aviso `Killed` exibido pelo fixture pertence ao processo deliberadamente
encerrado no cenário de crash e não é falha do teste; o exit code final foi
`0`.

## Decisão

A Fase 0C está concluída nesta branch. Restauração automática continua restrita
ao fragmento terminal; corrupção intermediária exige intervenção explícita e
auditável, evitando perda ou reordenação silenciosa de fatos.
