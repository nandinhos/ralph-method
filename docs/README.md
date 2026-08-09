# Documentação do Ralph Method

Esta pasta é a fonte de verdade do framework. A documentação separa o que o
usuário precisa entender, o que o agente de IA precisa executar e as decisões
que mantêm o núcleo seguro e reproduzível.

## Mapa rápido

```text
STATUS.md
  → o que está funcionando agora
architecture/
  → como os componentes se relacionam
AGENT_GUIDE.md
  → como instalar, identificar o harness e executar
adr/
  → decisões que não devem ser inferidas novamente
reports/
  → evidências numeradas de validações e releases
roadmap.md + backlog.md
  → próximos passos e itens adiados
```

## Para usuários

Comece pelo [README do projeto](../README.md) e depois consulte:

1. [STATUS.md](STATUS.md) para o estado atual;
2. [AGENT_GUIDE.md](AGENT_GUIDE.md) para a instalação e operação;
3. [architecture/interfaces.md](architecture/interfaces.md) para o contrato
   agnóstico de harness;
4. [architecture/README.md](architecture/README.md) para a matriz de cada
   componente, função e limite;
5. [reports/0009-regressao-multiprovider.md](reports/0009-regressao-multiprovider.md)
   para a prova dos três harnesses ativos.

## Para agentes de IA

O agente deve ler `AGENTS.md`, `STATUS.md`, a arquitetura relevante e os ADRs
antes de agir. Em seguida, deve seguir o [guia operacional](AGENT_GUIDE.md),
principalmente a decisão após a identificação do harness:

```text
detectar
→ verificar somente com probe seguro explícito
→ escolher apenas provider functional + runner_supported
→ aplicar perfil correspondente
→ inicializar workflow
→ executar uma feature
→ validar gates
→ registrar trace/handoff
→ deixar ralph-control decidir a continuidade
```

O agente não escolhe a próxima feature, não cria fallback silencioso e não
trata feedback como aprovação.

## Contrato de manutenção

Uma mudança que altera comportamento atual deve atualizar `STATUS.md`,
arquitetura e, quando aplicável, um ADR. Toda alteração de documentação ou
versão deve passar por:

```bash
bash scripts/check-doc-sync.sh
git diff --check
```

Os relatórios são numerados pelo controlador e devem conter comando, resultado,
escopo, limites e evidências; segredos, prompts e respostas completas nunca
entram em documentação versionada.
