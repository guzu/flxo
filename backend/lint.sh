#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

run() {
  local label="$1"; shift
  echo ""
  echo "── $label ─────────────────────────────────────────"
  if "$@"; then
    echo "✓ $label OK"
    PASS=$((PASS + 1))
  else
    echo "✗ $label FAILED"
    FAIL=$((FAIL + 1))
  fi
}

run "ruff format (check)" uv run ruff format --check .
run "ruff lint"           uv run ruff check .
run "ty (type check)"     uv run ty check

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Résultats : $PASS OK, $FAIL échec(s)"
echo "═══════════════════════════════════════════════════"

[ "$FAIL" -eq 0 ]
