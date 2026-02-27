# ./tests/check.sh
set -euo pipefail

jq_sort() {
  jq -S .
}

compile_json() {
  local input="$1"
  nix run path:.#compile -- "$input" | jq -S 'del(.meta)'
}

diff_golden() {
  local name="$1"
  local input="$2"
  local golden="tests/golden/${name}.json"

  if [ ! -f "$golden" ]; then
    echo "missing golden: $golden" >&2
    exit 1
  fi

  local tmp
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' RETURN

  compile_json "$input" > "$tmp"

  if ! diff -u "$golden" "$tmp"; then
    echo "golden mismatch: $name" >&2
    exit 1
  fi
}

expect_fail_code() {
  local name="$1"
  local input="$2"
  local want="$3"

  set +e
  local err out rc
  err="$(mktemp)"
  out="$(mktemp)"
  nix run path:.#compile -- "$input" >"$out" 2>"$err"
  rc="$?"
  set -e

  if [ "$rc" -eq 0 ]; then
    echo "expected failure but succeeded: $name" >&2
    cat "$out" >&2
    rm -f "$err" "$out"
    exit 1
  fi

  local msg json got
  msg="$(tr -d '\n' <"$err")"
  json="$(echo "$msg" | sed -n 's/.*\({\"code\"[^}]*}\).*/\1/p')"

  if [ -z "$json" ]; then
    echo "could not extract structured error JSON for: $name" >&2
    cat "$err" >&2
    rm -f "$err" "$out"
    exit 1
  fi

  got="$(echo "$json" | jq -r .code)"
  if [ "$got" != "$want" ]; then
    echo "unexpected error code for $name: got=$got want=$want" >&2
    echo "$json" | jq -S . >&2
    rm -f "$err" "$out"
    exit 1
  fi

  rm -f "$err" "$out"
}

diff_golden "single-wan" "examples/single-wan/inputs.nix"
diff_golden "multi-wan" "examples/multi-wan/inputs.nix"
diff_golden "multi-enterprise" "examples/multi-enterprise/inputs.nix"

expect_fail_code "disconnected-topology" "tests/negative/disconnected.nix" "E_TOPO_DISCONNECTED"

echo "ok"
