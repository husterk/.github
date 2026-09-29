#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

mapfile -t sh_files < <(git ls-files '*.sh')
if [ "${#sh_files[@]}" -gt 0 ]; then
  shellcheck "${sh_files[@]}"
fi

actionlint

mapfile -t md_files < <(git ls-files '*.md')
python3 scripts/check-us-spelling.py "${md_files[@]}"

renovate-config-validator --strict --no-global renovate/*.json renovate.json
