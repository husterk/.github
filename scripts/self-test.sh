#!/usr/bin/env bash
set -euo pipefail

# Run Renovate in lookup mode against test/renovate-fixture and fail unless
# every expected group branch appears and Renovate logs no warnings. The one
# warning ignored is about the environment: mise installs Renovate without
# building its optional native RE2 module.
#
#   self-test.sh --ref <sha|tag>   extend the presets from GitHub at that ref,
#                                  the way dependent repositories load them
#   self-test.sh --local           inline the presets from this working tree,
#                                  to test a change before it is pushed

usage() {
  echo "usage: $0 --ref <sha|tag> | --local" >&2
  exit 2
}

[ $# -ge 1 ] || usage
mode="$1"
root="$(git rev-parse --show-toplevel)"
repo="${PRESET_REPO:-husterk/.github}"
# Resolved here because mise shims cannot pick a version from inside the
# temporary fixture directory, which has no mise.toml. Renovate needs the
# pinned Node too, or it runs on whatever node the runner ships.
renovate_bin="$(mise which renovate 2> /dev/null || command -v renovate)"
node_dir="$(dirname "$(mise which node 2> /dev/null || command -v node)")"

# An old release extended first gives Renovate a pinned preset reference to
# bump. The presets under test come later, so their rules win.
old_preset="github>$repo//renovate/default#v1.0.0"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp -R "$root/test/renovate-fixture/." "$work/"

case "$mode" in
  --ref)
    [ $# -eq 2 ] || usage
    jq -n --arg old "$old_preset" --arg r "github>$repo//renovate/default#$2" --arg m "github>$repo//renovate/mise#$2" \
      '{extends: [$old, $r, $m]}' > "$work/renovate.json"
    ;;
  --local)
    jq -s '. as [$base, $mise]
      | ($base + $mise)
      | .packageRules = ($base.packageRules + $mise.packageRules)
      | .extends = [$old] + .extends
      | del(.description, ."$schema")' --arg old "$old_preset" \
      "$root/renovate/default.json" "$root/renovate/mise.json" > "$work/renovate.json"
    ;;
  *) usage ;;
esac

echo "Fixture config:"
jq -c . "$work/renovate.json"

# The fixture is a throwaway repository that is never pushed. Renovate's local
# platform only reads tracked files, so it needs one commit.
git -C "$work" init -q
git -C "$work" add -A
git -C "$work" -c user.name=self-test -c user.email=self-test@invalid -c commit.gpgsign=false commit -qm fixture

token="${GITHUB_COM_TOKEN:-${GITHUB_TOKEN:-$(gh auth token 2> /dev/null || true)}}"
log="$work/renovate.log"
(
  cd "$work"
  PATH="$node_dir:$PATH" RENOVATE_CACHE_DIR="$work/.cache" RENOVATE_TOKEN="$token" GITHUB_COM_TOKEN="$token" \
    LOG_LEVEL=debug LOG_FORMAT=json \
    "$renovate_bin" --platform=local --dry-run=lookup --repository-cache=disabled
) > "$log" 2>&1 || {
  tail -20 "$log"
  echo "Renovate exited with an error" >&2
  exit 1
}

json="$work/renovate.jsonl"
grep '^{' "$log" > "$json"

fail=0
warnings="$(jq -r '(select(.level >= 40) | .msg),
  (select(.msg == "packageFiles with updates") | .config[]?[]?.deps[]? | .warnings[]?.message)' "$json" |
  grep -vx 'RE2 not usable, falling back to RegExp' | sort -u || true)"
if [ -n "$warnings" ]; then
  echo "FAIL Renovate logged warnings or errors:"
  printf '  %s\n' "$warnings"
  fail=1
fi

branches="$(jq -r 'select(.msg == "packageFiles with updates") | .config[]?[]?.deps[]? | .updates[]?.branchName' "$json" | sort -u)"
echo "Branches Renovate would open:"
printf '  %s\n' "$branches"

for expected in renovate/mise-formatters-and-linters renovate/mise-language-servers; do
  if grep -qx "$expected" <<< "$branches"; then
    echo "PASS $expected"
  else
    echo "FAIL missing branch $expected"
    fail=1
  fi
done

for name in op 1password; do
  update="$(jq -r --arg n "$name" 'select(.msg == "packageFiles with updates") | .config.mise[]?.deps[]? | select(.depName == $n) | .updates[0].newValue // empty' "$json")"
  if [ -n "$update" ]; then
    echo "PASS $name resolves through the 1Password release history (update to $update)"
  else
    echo "FAIL $name has no update; the 1Password datasource did not resolve"
    fail=1
  fi
done

dotgithub_branches="$(jq -r 'select(.msg == "packageFiles with updates") | .config[]?[]?.deps[]? | select(.depName == "husterk/.github") | .updates[]?.branchName' "$json" | sort -u)"
dotgithub_updates="$(jq -r 'select(.msg == "packageFiles with updates") | .config[]?[]?.deps[]? | select(.depName == "husterk/.github") | .updates[]?.branchName' "$json" | wc -l | tr -d ' ')"
if [ "$dotgithub_updates" -ge 2 ] && [ "$(wc -l <<< "$dotgithub_branches" | tr -d ' ')" -eq 1 ]; then
  echo "PASS $dotgithub_updates husterk/.github updates share one branch ($dotgithub_branches)"
else
  echo "FAIL husterk/.github updates: $dotgithub_updates, branches: $(tr '\n' ' ' <<< "$dotgithub_branches")"
  fail=1
fi

exit "$fail"
