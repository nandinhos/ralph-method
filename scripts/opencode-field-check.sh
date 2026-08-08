#!/usr/bin/env bash

set -euo pipefail

FIXTURE="${1:-}"
NONCE="${2:-}"
REFERENCE="${3:-}"
[ -d "$FIXTURE" ] || { echo 'FEATURE_CHECK_FAIL: fixture ausente' >&2; exit 1; }
[ -n "$NONCE" ] || { echo 'FEATURE_CHECK_FAIL: nonce ausente' >&2; exit 1; }
[ -d "$REFERENCE" ] || { echo 'FEATURE_CHECK_FAIL: referência externa ausente' >&2; exit 1; }

python3 - "$FIXTURE" "$NONCE" "$REFERENCE" <<'PY'
import hashlib
import json
import pathlib
import subprocess
import sys
import tempfile

fixture = pathlib.Path(sys.argv[1])
nonce = sys.argv[2]
reference = pathlib.Path(sys.argv[3])

def fail(message):
    print(f"FEATURE_CHECK_FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)

def load(path):
    try:
        return json.loads(path.read_text())
    except Exception as exc:
        fail(f"JSON inválido em {path.name}: {exc}")

def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

input_hash = reference / "tasks.json.sha256"
readme_hash = reference / "README.sha256"
report_path = fixture / "report.json"
if not input_hash.exists() or not readme_hash.exists():
    fail("referência externa ausente")
if sha256(fixture / "tasks.json") != input_hash.read_text().strip():
    fail("tasks.json foi alterado durante a execução")
if sha256(fixture / "README.md") != readme_hash.read_text().strip():
    fail("README.md protegido foi alterado durante a execução")
if not report_path.exists():
    fail("report.json não foi criado")

report = load(report_path)
expected = {
    "schema_version": "1.0.0",
    "nonce": nonce,
    "summary": {
        "total_tasks": 8,
        "by_status": {"blocked": 1, "done": 2, "in_progress": 2, "todo": 3},
        "by_priority": {"critical": 2, "high": 2, "low": 2, "medium": 2},
        "estimated_hours": 27.0,
    },
    "tags": {
        "api": 1, "backend": 4, "core": 1, "data": 1, "docs": 1,
        "frontend": 2, "ops": 1, "quality": 1, "release": 1, "ux": 2,
    },
}
for key in expected:
    if report.get(key) != expected[key]:
        fail(f"campo {key} difere do esperado")

order = report.get("topological_order")
if not isinstance(order, list) or set(order) != {f"T-{number:03d}" for number in range(1, 9)}:
    fail("ordem topológica incompleta")
tasks = load(fixture / "tasks.json")
remaining = {task["id"]: set(task.get("dependencies", [])) for task in tasks}
expected_order = []
while remaining:
    ready = sorted(task_id for task_id, dependencies in remaining.items() if not dependencies)
    if not ready:
        fail("entrada válida contém ciclo")
    expected_order.extend(ready)
    for task_id in ready:
        remaining.pop(task_id)
    for dependencies in remaining.values():
        dependencies.difference_update(ready)
if order != expected_order:
    fail("ordem topológica não é a ordem determinística esperada")

for protected_name in ["tasks.json", "duplicate.json", "unknown-dependency.json", "cycle.json", "invalid-status.json"]:
    protected_hash = reference / f"{protected_name}.sha256"
    if not protected_hash.exists() or sha256(fixture / protected_name) != protected_hash.read_text().strip():
        fail(f"arquivo de entrada protegido foi alterado: {protected_name}")

positions = {task_id: index for index, task_id in enumerate(order)}
for task in tasks:
    for dependency in task.get("dependencies", []):
        if positions[dependency] >= positions[task["id"]]:
            fail("ordem topológica viola dependência")
script = fixture / "task_report.py"
negative_cases = [
    ("duplicate.json", "duplicate_id"),
    ("unknown-dependency.json", "unknown_dependency"),
    ("cycle.json", "cycle_detected"),
    ("invalid-status.json", "invalid_status"),
]
for filename, expected_code in negative_cases:
    output = pathlib.Path(tempfile.mkstemp(prefix="ralph-negative-")[1])
    try:
        result = subprocess.run(
            [sys.executable, str(script), str(fixture / filename), str(output), "--nonce", nonce],
            text=True,
            capture_output=True,
            timeout=15,
        )
    finally:
        output.unlink(missing_ok=True)
    if result.returncode == 0:
        fail(f"caso negativo {filename} terminou verde")
    diagnostic = result.stderr + result.stdout
    if expected_code not in diagnostic:
        fail(f"caso negativo {filename} sem código {expected_code}")

first = pathlib.Path(tempfile.mkstemp(prefix="ralph-repeat-a-")[1])
second = pathlib.Path(tempfile.mkstemp(prefix="ralph-repeat-b-")[1])
try:
    subprocess.run([sys.executable, str(script), str(fixture / "tasks.json"), str(first), "--nonce", nonce], check=True)
    subprocess.run([sys.executable, str(script), str(fixture / "tasks.json"), str(second), "--nonce", nonce], check=True)
    if first.read_bytes() != second.read_bytes():
        fail("duas execuções idênticas produziram saída diferente")
finally:
    first.unlink(missing_ok=True)
    second.unlink(missing_ok=True)

print("FEATURE_CHECK_OK: saída canônica, nonce, hashes protegidos, dependências, negativos e repetição")
PY
