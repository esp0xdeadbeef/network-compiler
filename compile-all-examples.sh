find examples -type f -exec sh -c '
  echo -e "\n\n$1:\n"
  nix run path:.#compile -- "$1" | jq -c
' _ {} \;
