#!/bin/sh
# Fetches only the "Basis Server" folder of upstream Basis at BASIS_REF (commit, branch or tag)
# into ./basis, which the compose file builds the server image from. Nothing is forked.
set -eu
cd "$(dirname "$0")"
BASIS_REPO=${BASIS_REPO:-https://github.com/BasisVR/Basis.git}
[ -n "${BASIS_REF:-}" ] || BASIS_REF=$(sed -n 's/^BASIS_REF=//p' .env 2>/dev/null || true)
BASIS_REF=${BASIS_REF:-experimental-branch-major-changes}
if [ ! -d basis/.git ]; then
  git init -q basis
  git -C basis remote add origin "$BASIS_REPO"
  git -C basis config core.sparseCheckout true
  git -C basis config core.sparseCheckoutCone true
  mkdir -p basis/.git/info
  printf '/*\n!/*/\n/Basis Server/\n' > basis/.git/info/sparse-checkout
fi
git -C basis fetch -q --depth 1 --filter=blob:none origin "$BASIS_REF"
git -C basis checkout -q --detach FETCH_HEAD
echo "basis: $(git -C basis rev-parse --short HEAD) ($BASIS_REF)"
