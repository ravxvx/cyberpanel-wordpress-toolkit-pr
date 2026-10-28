#!/bin/sh
# Builds dist/wordpressToolkitPro.zip (run from anywhere).
set -eu
cd "$(dirname "$0")/.."
mkdir -p dist
rm -f dist/wordpressToolkitPro.zip
find wordpressToolkitPro -name __pycache__ -type d -prune -exec rm -rf {} +
chmod 755 wordpressToolkitPro/*.sh wordpressToolkitPro/pre_install wordpressToolkitPro/post_install wordpressToolkitPro/pre_remove
zip -qr dist/wordpressToolkitPro.zip wordpressToolkitPro
echo "Built dist/wordpressToolkitPro.zip"
unzip -l dist/wordpressToolkitPro.zip | tail -n 1
