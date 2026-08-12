# ADR-0014 — Diagnóstico MCP pós-atualização de harness

- **Status:** accepted
- **Date:** `2026-08-12`
- **Owner:** Equipe do Ralph Method

## Contexto

Uma atualização do Codex CLI `0.147.0` expôs uma falha de startup em que o
Codex cancelava a inicialização de MCPs configurados com executáveis resolvidos
por PATH. O `context7` respondia ao handshake quando iniciado diretamente, mas
uma sessão nova do Codex não conseguia completar o startup até o profile usar o
caminho absoluto do `npx`. O incidente está registrado em
[`Incidente 0014`](../incidents/0014-startup-mcp-pos-atualizacao-codex.md).

O Ralph Method é agnóstico ao domínio e não é dono da configuração global do
Codex. Portanto, a prevenção precisa ser um procedimento operacional verificável
para o harness, não uma dependência de runtime dentro do control plane.

## Opções consideradas

| Opção | Vantagens | Desvantagens |
|---|---|---|
| **A — Desabilitar o MCP ou trocar provider** | Remove o aviso rapidamente | Perde capacidade e mascara a causa; viola a política de não trocar provider silenciosamente |
| **B — Aumentar timeout sem diagnóstico** | Pode esconder uma lentidão transitória | Não distingue servidor quebrado de launcher travado e cria falsa sensação de saúde |
| **C — Diagnosticar handshake e adaptar o executável somente quando necessário** | Preserva o servidor, trata a causa comprovada e produz evidência reproduzível | Exige uma sessão nova e um ajuste explícito no profile local |

## Decisão

Adotamos a opção C como rotina de pós-atualização do Codex CLI, de plugin MCP ou
do profile do harness.

Quando houver falha MCP:

1. confirmar a versão do Codex e listar a configuração efetiva com
   `codex --profile <profile> mcp list --json`;
2. executar o comando configurado de cada servidor em um handshake MCP direto,
   sem enviar prompts nem fazer geração;
3. se o handshake falhar, corrigir primeiro o servidor, dependência,
   autenticação ou ambiente correspondente;
4. se o handshake passar, mas o startup do Codex falhar, testar a resolução do
   launcher com `command -v <executável>` e substituir o comando no profile por
   seu caminho absoluto, mantendo argumentos e transporte;
5. reiniciar o Codex e comprovar, em sessão nova, que todos os servidores
   esperados chegam ao estado inicializado e que o prompt é alcançado sem
   `MCP startup interrupted`;
6. registrar a causa e a evidência no incidente ou capture log, sem registrar
   tokens, prompts, respostas completas ou valores de ambiente.

Esta rotina não autoriza desabilitar MCP, trocar provider silenciosamente,
alterar pacote sem evidência ou aumentar timeout como substituto do diagnóstico.

## Consequências

### Positivas

- atualizações passam a ter um smoke test operacional explícito;
- a mesma causa raiz pode ser confirmada ou descartada com evidência curta;
- a correção preserva capacidades MCP e é reversível no profile local;
- o Ralph Method continua sem acoplamento ao estado global do Codex.

### Negativas

- a validação exige uma sessão nova do Codex;
- o caminho absoluto depende da instalação local do runtime e pode precisar ser
  recalculado após trocar a versão do Node;
- o procedimento é condicional: uma falha real no handshake exige investigação
  específica do servidor, não esta mesma adaptação.

## Gatilho para revisitar

Revisitar quando o Codex passar a oferecer um diagnóstico não interativo de
startup MCP que informe a causa de resolução do launcher, ou quando o profile do
Beer & Code Harness passar a ser gerado e versionado por uma ferramenta própria.
