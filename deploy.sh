#!/bin/sh
# Builds the web host and publishes it to the gh-pages branch, which GitHub
# Pages serves. Sign the file first: cd rive && rive . --publish, then copy
# rive/build/janhyang.riv to web/public/.
set -eu
cd "$(dirname "$0")/web"
pnpm install --frozen-lockfile
pnpm build
touch dist/.nojekyll
cd dist
rm -rf .git
git init -q -b gh-pages
git add -A
git commit -q -m "Deploy web host"
git push -q -f "$(git -C .. remote get-url origin)" gh-pages
rm -rf .git
echo "deployed: https://yeonseong-lee.github.io/janhyang/"
