# ADR 0001 — Extração do núcleo para o Ralph Method

## Status

Aceita.

## Contexto

O control plane e o trace foram amadurecidos dentro do `refactor-radar`, mas
suas responsabilidades são independentes do domínio do produto. Para reutilizar
o loop em outros projetos e providers, o framework precisa ter repositório,
versão, testes e instalação próprios.

## Opções consideradas

### Manter o Ralph dentro do produto

Rejeitada. Cada novo projeto teria de copiar contexto de domínio e a evolução
do loop ficaria acoplada ao ciclo do produto.

### Instalar somente a partir de um caminho global

Rejeitada. Atualização global poderia alterar silenciosamente um projeto em
execução e dificultaria auditoria da versão usada.

### Extrair um bundle local versionado

Escolhida. O `bc-harness` distribui o instalador, e cada projeto recebe um
manifesto e um runtime local com versão e hashes verificáveis.

## Consequências

- o núcleo pode ser testado sem Laravel, banco ou domínio de aplicação;
- upgrades passam a ser explícitos e versionados;
- o bundle inicial duplica arquivos até existir uma distribuição própria;
- providers adicionais entram por adapters sem alterar `ralph-control`.

## Gatilho para revisitar

Separar o bundle em pacote distribuível quando o tamanho, a frequência de
upgrade ou a quantidade de projetos tornarem a cópia local operacionalmente
mais cara que a auditoria de uma release.

## Responsável

Equipe do Ralph Method.

## Data

2026-08-07.
