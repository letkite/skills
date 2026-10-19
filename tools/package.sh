#!/usr/bin/env bash
# Zip each skill for upload to claude.ai (Customize > Skills > Upload a skill): dist/<skill>.zip holds <skill>/SKILL.md ...
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf dist && mkdir dist
for d in plugins/*/skills/*/; do
  name="$(basename "$d")"
  (cd "$(dirname "$d")" && zip -qr -X "$OLDPWD/dist/$name.zip" "$name" -x '*/.DS_Store')
  echo "dist/$name.zip"
done
