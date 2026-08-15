#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSER="$SCRIPT_DIR/parser.php"
POLICY="$SCRIPT_DIR/policy.php"
PRIVATE_DIR=''

cleanup() {
  if [ -n "$PRIVATE_DIR" ]; then
    rm -f "$PRIVATE_DIR/events.jsonl" "$PRIVATE_DIR/stderr.log" \
      "$PRIVATE_DIR/settings.json" "$PRIVATE_DIR/read-boundary-canary"
    rmdir "$PRIVATE_DIR" 2>/dev/null || true
  fi
}
trap cleanup EXIT

usage() {
  printf '%s\n' \
    'uso: runner.sh preflight [--mode impl|verify] [--repo-root DIR]' \
    '     runner.sh run --repo-root DIR --prompt-file FILE --events-file FILE \' \
    '       --result-file FILE --mode impl|verify --execution-id ID \' \
    '       --workflow-id ID --feature-key KEY --attempt N' \
    '     runner.sh version'
}

die() {
  printf 'ralph-agy: %s\n' "$1" >&2
  exit 2
}

version() {
  local output
  output="$(agy --version 2>&1)" || die 'não foi possível obter a versão do agy'
  output="${output%%$'\n'*}"
  output="$(printf '%s' "$output" | tr -d '\r' | sed -E 's/^[^0-9]*([0-9]+\.[0-9]+\.[0-9]+).*$/\1/')"
  [[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die 'versão do agy não reconhecida'
  printf '%s\n' "$output"
}

selected_model() {
  local mode="$1"
  if [ "$mode" = verify ] && [ -n "${RALPH_VERIFY_MODEL:-}" ]; then
    printf '%s' "$RALPH_VERIFY_MODEL"
  else
    printf '%s' "${RALPH_AGY_MODEL:-}"
  fi
}

policy_json() {
  local repo_root="$1" agent="$2"
  local args=(check --repo-root "$repo_root" --agent "$agent")
  [ -z "${RALPH_AGY_TOKEN_FILE:-}" ] || args+=(--token-file "$RALPH_AGY_TOKEN_FILE")
  php "$POLICY" "${args[@]}"
}

preflight() {
  local mode='impl' repo_root='' model='' effort="${RALPH_AGY_EFFORT:-high}"
  local agent="${RALPH_AGY_VERIFY_AGENT:-ralph-review}"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mode) mode="${2:-}"; shift 2 ;;
      --repo-root) repo_root="${2:-}"; shift 2 ;;
      --model) model="${2:-}"; shift 2 ;;
      --effort) effort="${2:-}"; shift 2 ;;
      --agent) agent="${2:-}"; shift 2 ;;
      *) die "opção desconhecida no preflight: $1" ;;
    esac
  done

  command -v agy >/dev/null 2>&1 || die 'CLI agy não encontrada'
  command -v php >/dev/null 2>&1 || die 'PHP não encontrado'
  [ -x "$PARSER" ] || [ -f "$PARSER" ] || die 'parser agy ausente'
  [[ "$mode" == impl || "$mode" == verify ]] || die "modo inválido: $mode"
  [ -n "$model" ] || model="$(selected_model "$mode")"
  [ -n "$model" ] || die 'RALPH_AGY_MODEL deve ser explícito'
  [[ "$model" =~ ^[^[:space:]]+$ ]] || die "modelo inválido: $model"
  [[ "$effort" =~ ^(low|medium|high)$ ]] || die "effort inválido: $effort"

  local help
  help="$(agy --help 2>&1)" || die 'não foi possível consultar help do agy'
  for flag in --print --output-format --model --effort --print-timeout; do
    grep -q -- "$flag" <<< "$help" || die "agy sem suporte comprovado a $flag"
  done

  local policy_hash='' policy_status='not_required'
  if [ "$mode" = verify ]; then
    [ -n "$repo_root" ] || die 'verify exige repo-root explícito'
    repo_root="$(cd "$repo_root" 2>/dev/null && pwd -P)" || die 'repo-root inválido'
    local agent_file="$repo_root/.agents/agents/$agent/agent.md"
    [ -f "$agent_file" ] && [ -r "$agent_file" ] \
      || die "agente agy não descoberto: $agent (esperado em .agents/agents/$agent/agent.md)"
    local checked
    checked="$(policy_json "$repo_root" "$agent")" || die 'política agy não foi comprovada'
    policy_hash="$(POLICY_JSON="$checked" php -r '$v=json_decode(getenv("POLICY_JSON"), true, 512, JSON_THROW_ON_ERROR); echo $v["policy_hash"] ?? "";')"
    [ -n "$policy_hash" ] || die 'política agy sem hash'
    policy_status='verified'
  fi

  local hash_json='null'
  [ -z "$policy_hash" ] || hash_json="\"$policy_hash\""
  printf '{"status":"ready","runner":"agy","runner_version":"%s","requested_model":"%s","prompt_transport":"file_to_argument","permission_policy_status":"%s","permission_policy_hash":%s}\n' \
    "$(version)" "$model" "$policy_status" "$hash_json"
}

append_runtime_mounts() {
  local -n command_ref="$1"
  command_ref+=(--ro-bind /usr /usr)
  if [ -L /bin ]; then command_ref+=(--symlink "$(readlink /bin)" /bin); elif [ -d /bin ]; then command_ref+=(--ro-bind /bin /bin); fi
  if [ -L /lib ]; then command_ref+=(--symlink "$(readlink /lib)" /lib); elif [ -d /lib ]; then command_ref+=(--ro-bind /lib /lib); fi
  if [ -L /lib64 ]; then command_ref+=(--symlink "$(readlink /lib64)" /lib64); elif [ -d /lib64 ]; then command_ref+=(--ro-bind /lib64 /lib64); fi
  command_ref+=(--dir /etc)
  local path
  for path in /etc/ssl /etc/resolv.conf /etc/hosts /etc/nsswitch.conf /etc/passwd; do
    [ ! -e "$path" ] || command_ref+=(--ro-bind "$path" "$path")
  done
}

build_verify_command() {
  local repo_root="$1" model="$2" effort="$3" timeout_value="$4" prompt="$5" agent="$6"
  local settings_file="$7" canary_file="$8"
  local agy_bin agy_home token home_dir username
  agy_bin="$(readlink -f "$(command -v agy)")"
  home_dir="${HOME:?HOME obrigatório}"
  agy_home="$home_dir/.gemini/antigravity-cli"
  token="${RALPH_AGY_TOKEN_FILE:-$agy_home/antigravity-oauth-token}"
  token="$(readlink -f "$token")"
  username="${USER:-$(id -un)}"

  VERIFY_COMMAND=(
    bwrap --die-with-parent --new-session --unshare-pid --unshare-ipc
    --unshare-uts --unshare-cgroup-try --clearenv
  )
  append_runtime_mounts VERIFY_COMMAND
  VERIFY_COMMAND+=(
    --tmpfs /tmp
    --dir "$(dirname "$repo_root")" --ro-bind "$repo_root" "$repo_root"
    --dir "$(dirname "$agy_home")" --tmpfs "$agy_home"
    --ro-bind "$token" "$agy_home/antigravity-oauth-token"
    --ro-bind "$settings_file" "$agy_home/settings.json"
    --ro-bind "$canary_file" "$agy_home/ralph-read-boundary-canary"
    --proc /proc --dev /dev --ro-bind "$agy_bin" /agy
    --setenv HOME "$home_dir" --setenv USER "$username"
    --setenv PATH /usr/bin:/bin --setenv LANG C.UTF-8 --chdir "$repo_root"
    /agy --add-dir "$repo_root" --mode plan --sandbox --output-format stream-json --model "$model"
    --effort "$effort" --agent "$agent" --print-timeout "$timeout_value"
    --print "$prompt"
  )
}

run_engine() {
  local repo_root='' prompt_file='' events_file='' result_file='' mode='impl'
  local execution_id='' workflow_id="${RALPH_EXECUTION_WORKFLOW_ID:-}"
  local feature_key="${RALPH_EXECUTION_FEATURE_KEY:-}" attempt="${RALPH_EXECUTION_ATTEMPT:-}"
  local model='' effort="${RALPH_AGY_EFFORT:-high}"
  local agent="${RALPH_AGY_AGENT:-}" verify_agent="${RALPH_AGY_VERIFY_AGENT:-ralph-review}"
  local max_prompt_bytes="${RALPH_AGY_MAX_PROMPT_BYTES:-262144}"
  local max_event_bytes="${RALPH_AGY_MAX_EVENT_BYTES:-5242880}"
  local max_events="${RALPH_AGY_MAX_EVENTS:-10000}"
  local timeout_seconds="${RALPH_AGY_TIMEOUT:-1800}"
  local print_timeout="${RALPH_AGY_PRINT_TIMEOUT:-30m}"

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --repo-root) repo_root="${2:-}"; shift 2 ;;
      --prompt-file) prompt_file="${2:-}"; shift 2 ;;
      --events-file) events_file="${2:-}"; shift 2 ;;
      --result-file) result_file="${2:-}"; shift 2 ;;
      --mode) mode="${2:-}"; shift 2 ;;
      --execution-id) execution_id="${2:-}"; shift 2 ;;
      --workflow-id) workflow_id="${2:-}"; shift 2 ;;
      --feature-key) feature_key="${2:-}"; shift 2 ;;
      --attempt) attempt="${2:-}"; shift 2 ;;
      --model) model="${2:-}"; shift 2 ;;
      --effort) effort="${2:-}"; shift 2 ;;
      --agent) agent="${2:-}"; shift 2 ;;
      *) die "opção desconhecida na execução: $1" ;;
    esac
  done

  repo_root="$(cd "$repo_root" 2>/dev/null && pwd -P)" || die 'repo-root inválido'
  [ -f "$prompt_file" ] || die "prompt ausente: $prompt_file"
  [ -n "$events_file" ] || die 'events-file obrigatório'
  [ -n "$result_file" ] || die 'result-file obrigatório'
  [[ "$mode" == impl || "$mode" == verify ]] || die "modo inválido: $mode"
  [[ "$execution_id" =~ ^exec_[A-Za-z0-9_-]+$ ]] || die 'execution-id inválido'
  [[ "$workflow_id" =~ ^wf_[A-Za-z0-9_-]+$ ]] || die 'workflow-id inválido'
  [[ "$feature_key" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]] || die 'feature-key inválida'
  [[ "$attempt" =~ ^[0-9]+$ ]] || die 'attempt inválida'
  [ -n "$model" ] || model="$(selected_model "$mode")"
  [ -n "$model" ] || die 'RALPH_AGY_MODEL deve ser explícito'
  [[ "$effort" =~ ^(low|medium|high)$ ]] || die 'effort inválido'
  [[ "$max_prompt_bytes" =~ ^[1-9][0-9]*$ && "$max_event_bytes" =~ ^[1-9][0-9]*$ && "$max_events" =~ ^[1-9][0-9]*$ ]] || die 'limites inválidos'
  [[ "$timeout_seconds" =~ ^[1-9][0-9]*$ ]] || die 'timeout inválido'

  local prompt_bytes prompt
  prompt_bytes="$(wc -c < "$prompt_file")"
  [ "$prompt_bytes" -le "$max_prompt_bytes" ] || die "prompt excede ${max_prompt_bytes} bytes"
  prompt="$(<"$prompt_file")"
  mkdir -p "$(dirname "$events_file")" "$(dirname "$result_file")"
  local private_base='/tmp'
  [ ! -d /dev/shm ] || private_base='/dev/shm'
  PRIVATE_DIR="$(mktemp -d "$private_base/ralph-agy-${UID:-0}.XXXXXX")"
  chmod 0700 "$PRIVATE_DIR"
  local raw_events="$PRIVATE_DIR/events.jsonl" raw_stderr="$PRIVATE_DIR/stderr.log"
  local text_output="${result_file}.text" runner_version prompt_sha256
  runner_version="$(version)"
  prompt_sha256="$(php -r 'echo hash_file("sha256", $argv[1]);' "$prompt_file")"

  local policy_hash='' policy_status='not_required' verification_agent=''
  local command=()
  if [ "$mode" = verify ]; then
    verification_agent="$verify_agent"
    [ "$verification_agent" = ralph-review ] || die 'verify exige agente ralph-review'
    local checked
    checked="$(policy_json "$repo_root" "$verification_agent")" || die 'política agy inválida antes da execução'
    policy_hash="$(POLICY_JSON="$checked" php -r '$v=json_decode(getenv("POLICY_JSON"), true, 512, JSON_THROW_ON_ERROR); echo $v["policy_hash"] ?? "";')"
    policy_status='verified'
    REPO_ROOT_JSON="$repo_root" php -r '
      echo json_encode([
        "allowNonWorkspaceAccess" => false,
        "permissions" => ["allow" => []],
        "trustedWorkspaces" => [getenv("REPO_ROOT_JSON")],
      ], JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR), "\n";
    ' > "$PRIVATE_DIR/settings.json"
    printf '%s\n' 'RALPH_AGY_READ_BOUNDARY_CANARY' > "$PRIVATE_DIR/read-boundary-canary"
    chmod 0600 "$PRIVATE_DIR/settings.json" "$PRIVATE_DIR/read-boundary-canary"
    build_verify_command "$repo_root" "$model" "$effort" "$print_timeout" "$prompt" "$verification_agent" \
      "$PRIVATE_DIR/settings.json" "$PRIVATE_DIR/read-boundary-canary"
    command=("${VERIFY_COMMAND[@]}")
  else
    command=(agy --add-dir "$repo_root" --mode accept-edits --dangerously-skip-permissions --output-format stream-json
      --model "$model" --effort "$effort" --print-timeout "$print_timeout")
    [ -z "$agent" ] || command+=(--agent "$agent")
    command+=(--print "$prompt")
  fi

  local rc=0
  (cd "$repo_root" && timeout --kill-after=10s "${timeout_seconds}s" "${command[@]}") > "$raw_events" 2> "$raw_stderr" || rc=$?
  if [ "$mode" = verify ]; then
    local checked_after hash_after
    checked_after="$(policy_json "$repo_root" "$verification_agent")" || rc=1
    hash_after="$(POLICY_JSON="$checked_after" php -r '$v=json_decode(getenv("POLICY_JSON"), true); echo is_array($v) ? ($v["policy_hash"] ?? "") : "";')"
    if [ "$hash_after" != "$policy_hash" ]; then
      policy_status='failed'
      rc=1
    fi
  fi

  php "$PARSER" \
    --events "$raw_events" --sanitized-events "$events_file" --result "$result_file" \
    --repo-root "$repo_root" --exit-code "$rc" --runner-version "$runner_version" \
    --requested-model "$model" --execution-id "$execution_id" --execution-mode "$mode" \
    --workflow-id "$workflow_id" --feature-key "$feature_key" --attempt "$attempt" \
    --prompt-sha256 "$prompt_sha256" --prompt-transport file_to_argument \
    --permission-policy-status "$policy_status" --permission-policy-hash "${policy_hash:-none}" \
    --verification-agent "${verification_agent:-none}" --text-output "$text_output" \
    --max-event-bytes "$max_event_bytes" --max-events "$max_events"

  cat "$result_file"
  [ ! -s "$text_output" ] || cat "$text_output"
  local status
  status="$(php -r '$v=json_decode(file_get_contents($argv[1]), true); echo is_array($v) ? ($v["status"] ?? "failed") : "failed";' "$result_file")"
  [ "$status" = completed ]
}

command="${1:-}"
[ -n "$command" ] || { usage >&2; exit 2; }
shift
case "$command" in
  preflight) preflight "$@" ;;
  run) run_engine "$@" ;;
  version) version ;;
  *) usage >&2; exit 2 ;;
esac
