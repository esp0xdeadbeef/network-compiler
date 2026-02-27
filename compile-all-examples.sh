find examples -name 'inputs.nix' -print0 |
while IFS= read -r -d '' f; do
  echo ""
  echo "=== $f ==="
  nix run path:.#compile -- "$f" | jq -c
done
