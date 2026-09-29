# Renovate fixture

Old versions on purpose. `scripts/self-test.sh` copies this directory, points
its `renovate.json` at the presets on a given commit, and runs Renovate in
lookup mode to prove every expected group branch appears with no warnings.
