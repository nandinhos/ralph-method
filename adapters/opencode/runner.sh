#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSER="$SCRIPT_DIR/parser.php"
POLICY_CHECKER="$SCRIPT_DIR/policy.php"

usage() {
  cat <<'EOF'
uso: runner.sh preflight [--model provider/model]
     runner.sh run --repo-root DIR --prompt-file FILE --events-file FILE \
       --result-file FILE --mode impl|verify --execution-id ID [opções]
EOF
}

die() {
  printf 'ralph-opencode: %s\n' "$1" >&2
  exit 2
}

require_file() {
  [ -f "$2" ] || die "$1 ausente: $2"
}

version() {
  local output
  output="$(opencode --version 2>&1)" || die "não foi possível obter a versão do OpenCode"
  printf '%s\n' "${output%%$'\n'*}" | tr -d '\r' | sed 's/^[^0-9]*//' | cut -c1-64
}

preflight() {
  local model="${RALPH_OPENCODE_MODEL:-}"
  local mode='impl'
  local repo_root=''
  local agent="${RALPH_OPENCODE_VERIFY_AGENT:-}"
  local policy_proof="${RALPH_OPENCODE_VERIFY_POLICY_PROOF:-}"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --model) model="${2:-}"; shift 2 ;;
      --model=*) model="${1#*=}"; shift ;;
      --mode) mode="${2:-}"; shift 2 ;;
      --repo-root) repo_root="${2:-}"; shift 2 ;;
      --agent) agent="${2:-}"; shift 2 ;;
      --policy-proof) policy_proof="${2:-}"; shift 2 ;;
      *) die "opção desconhecida no preflight: $1" ;;
    esac
  done

  command -v opencode >/dev/null 2>&1 || die 'CLI opencode não encontrada'
  [ -n "$model" ] || die 'RALPH_OPENCODE_MODEL deve ser explícito'
  [[ "$model" =~ ^[^/[:space:]]+/[^[:space:]]+$ ]] || die "modelo inválido: $model"
  [[ "$mode" == impl || "$mode" == verify ]] || die "modo inválido: $mode"
  opencode run --help 2>&1 | grep -q -- '--format' || die 'OpenCode sem suporte comprovado a --format'
  opencode run --help 2>&1 | grep -q -- '--file' || die 'OpenCode sem suporte comprovado a --file'

  local policy_hash=''
  if [ "$mode" = verify ]; then
    [ -n "$repo_root" ] || die 'modo verify exige repo-root explícito'
    [ -n "$agent" ] || die 'modo verify exige agente read-only explícito'
    [ -n "$policy_proof" ] || die 'modo verify exige prova read-only externa'
    local policy_json
    policy_json="$(php "$POLICY_CHECKER" check --repo-root "$repo_root" --agent "$agent" --proof-file "$policy_proof")" \
      || die 'prova read-only não corresponde à política atual'
    policy_hash="$(POLICY_JSON="$policy_json" php -r '$v=json_decode(getenv("POLICY_JSON"), true, 512, JSON_THROW_ON_ERROR); echo $v["policy_hash"] ?? "";')"
    [ -n "$policy_hash" ] || die 'prova read-only sem hash de política'
  fi

  printf '{"status":"ready","runner":"opencode","runner_version":"%s","requested_model":"%s","prompt_transport":"file","permission_policy_status":"%s","permission_policy_hash":%s}\n' \
    "$(version)" "$model" "$([ "$mode" = verify ] && echo verified || echo not_required)" \
    "${policy_hash:+\"$policy_hash\"}"
}

run_engine() {
  local repo_root=''
  local prompt_file=''
  local events_file=''
  local result_file=''
  local mode='impl'
  local execution_id=''
  local model="${RALPH_OPENCODE_MODEL:-}"
  local agent="${RALPH_OPENCODE_AGENT:-}"
  local variant="${RALPH_OPENCODE_VARIANT:-}"
  local auto="${RALPH_OPENCODE_AUTO:-0}"
  local pure="${RALPH_OPENCODE_PURE:-1}"
  local policy_proof="${RALPH_OPENCODE_VERIFY_POLICY_PROOF:-}"
  local max_prompt_bytes="${RALPH_OPENCODE_MAX_PROMPT_BYTES:-262144}"
  local timeout_seconds="${RALPH_OPENCODE_TIMEOUT:-1800}"

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --repo-root) repo_root="${2:-}"; shift 2 ;;
      --prompt-file) prompt_file="${2:-}"; shift 2 ;;
      --events-file) events_file="${2:-}"; shift 2 ;;
      --result-file) result_file="${2:-}"; shift 2 ;;
      --mode) mode="${2:-}"; shift 2 ;;
      --execution-id) execution_id="${2:-}"; shift 2 ;;
      --model) model="${2:-}"; shift 2 ;;
      --agent) agent="${2:-}"; shift 2 ;;
      --variant) variant="${2:-}"; shift 2 ;;
      --auto) auto="${2:-1}"; shift 2 ;;
      --pure) pure="${2:-1}"; shift 2 ;;
      --policy-proof) policy_proof="${2:-}"; shift 2 ;;
      --) shift; [ "$#" -eq 0 ] || die 'argumentos posicionais não são permitidos' ;;
      *) die "opção desconhecida na execução: $1" ;;
    esac
  done

  [ -d "$repo_root" ] || die "raiz do projeto ausente: $repo_root"
  require_file 'prompt' "$prompt_file"
  [ -n "$events_file" ] || die 'events-file obrigatório'
  [ -n "$result_file" ] || die 'result-file obrigatório'
  [[ "$mode" == 'impl' || "$mode" == 'verify' ]] || die "modo inválido: $mode"
  local policy_hash=''
  if [ "$mode" = verify ]; then
    local verify_agent="${RALPH_OPENCODE_VERIFY_AGENT:-$agent}"
    [ -n "$verify_agent" ] || die 'modo verify exige RALPH_OPENCODE_VERIFY_AGENT explícito e read-only'
    [ -n "$policy_proof" ] || die 'modo verify exige prova read-only externa'
    local policy_json
    policy_json="$(php "$POLICY_CHECKER" check --repo-root "$repo_root" --agent "$verify_agent" --proof-file "$policy_proof")" \
      || die 'prova read-only não corresponde à política atual antes da execução'
    policy_hash="$(POLICY_JSON="$policy_json" php -r '$v=json_decode(getenv("POLICY_JSON"), true, 512, JSON_THROW_ON_ERROR); echo $v["policy_hash"] ?? "";')"
  fi
  [[ "$execution_id" =~ ^exec_[A-Za-z0-9_-]+$ ]] || die "execution-id inválido: $execution_id"
  [ -n "$model" ] || die 'RALPH_OPENCODE_MODEL deve ser explícito'
  [[ "$model" =~ ^[^/[:space:]]+/[^[:space:]]+$ ]] || die "modelo inválido: $model"
  [[ "$auto" == 0 || "$auto" == 1 ]] || die 'auto deve ser 0 ou 1'
  [[ "$pure" == 0 || "$pure" == 1 ]] || die 'pure deve ser 0 ou 1'
  [[ "$max_prompt_bytes" =~ ^[1-9][0-9]*$ ]] || die 'limite de prompt inválido'
  [[ "$timeout_seconds" =~ ^[1-9][0-9]*$ ]] || die 'timeout inválido'

  local prompt_bytes
  prompt_bytes="$(wc -c < "$prompt_file")"
  [ "$prompt_bytes" -le "$max_prompt_bytes" ] || die "prompt excede o limite de ${max_prompt_bytes} bytes"

  mkdir -p "$(dirname "$events_file")" "$(dirname "$result_file")"
  : > "$events_file"
  local stderr_file="${events_file}.stderr"
  : > "$stderr_file"
  local text_output="${result_file}.text"
  local runner_version
  runner_version="$(version)"
  local prompt_sha256
  prompt_sha256="$(sha256sum "$prompt_file" | awk '{print $1}')"
  local provider="${model%%/*}"
  local command=(opencode run --format json --dir "$repo_root" --model "$model" --file "$prompt_file")

  [ -n "$agent" ] && command+=(--agent "$agent")
  [ -n "$variant" ] && command+=(--variant "$variant")
  [ "$pure" = 1 ] && command+=(--pure)
  [ "$mode" = impl ] && [ "$auto" = 1 ] && command+=(--auto)
  [ "$mode" = verify ] && [ -n "${RALPH_OPENCODE_VERIFY_AGENT:-}" ] && command+=(--agent "$RALPH_OPENCODE_VERIFY_AGENT")
  command+=(-- "Execute a instrução de fase anexada. A resposta deve ser objetiva e não deve incluir segredos.")

  local rc=0
  timeout --kill-after=10s "${timeout_seconds}s" "${command[@]}" > "$events_file" 2> "$stderr_file" || rc=$?
  local fallback_status="${RALPH_OPENCODE_FALLBACK_STATUS:-unknown}"
  case "$fallback_status" in unknown|detected|not_detected) ;; *) die 'fallback status inválido' ;; esac

  local policy_status='not_required'
  if [ "$mode" = verify ]; then
    policy_status='verified'
    if ! php "$POLICY_CHECKER" check --repo-root "$repo_root" --agent "${RALPH_OPENCODE_VERIFY_AGENT:-$agent}" --proof-file "$policy_proof" >/dev/null; then
      policy_status='failed'
      rc=1
    fi
  fi

  php "$PARSER" \
    --events "$events_file" \
    --result "$result_file" \
    --exit-code "$rc" \
    --runner-version "$runner_version" \
    --provider "$provider" \
    --requested-model "$model" \
    --execution-id "$execution_id" \
    --prompt-sha256 "$prompt_sha256" \
    --prompt-transport file \
    --permission-policy-hash "$policy_hash" \
    --permission-policy-status "$policy_status" \
    --verification-agent "${RALPH_OPENCODE_VERIFY_AGENT:-}" \
    --text-output "$text_output" \
    --fallback-status "$fallback_status" \
    --max-event-bytes "${RALPH_OPENCODE_MAX_EVENT_BYTES:-5242880}" \
    --max-events "${RALPH_OPENCODE_MAX_EVENTS:-10000}"

  cat "$result_file"
  if [ "$mode" = verify ] && [ -s "$text_output" ]; then
    cat "$text_output"
  fi
  local status
  status="$(php -r '$v=json_decode(file_get_contents($argv[1]), true); echo is_array($v) ? ($v["status"] ?? "failed") : "failed";' "$result_file")"
  [ "$status" = completed ] || exit 1
}

command="${1:-}"
[ -n "$command" ] || { usage >&2; exit 2; }
shift
case "$command" in
  preflight) preflight "$@" ;;
  run) run_engine "$@" ;;
  *) usage >&2; exit 2 ;;
esac
