#!/bin/sh
# Re-deploy the latest pushed main through GitHub Actions.
# Local edits must be committed and pushed first. See docs/deployment.md.
set -eu
cd "$(dirname "$0")"
exec gh workflow run deploy.yml --ref main
