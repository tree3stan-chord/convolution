#!/usr/bin/env bash
# Deploy script for convolution.musicsian.com
# 1. Compile native → WASM  (scripts/build-fixed.sh)
# 2. Bundle any JS (skip npm build since we're not bundling)
# 3. Stage finished static files into ~/builds/<STAMP>
# 4. Rsync → /var/www/…/releases/<STAMP>, flip symlink, restore SELinux, reload Nginx

set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"   # one level up from scripts/
STAMP=$(date +%Y-%m-%d-%H%M%S)
STAGE=~/builds/$STAMP
mkdir -p "$STAGE"

echo "▶ 1) Compile C/Fortran → WASM"
# Use the fixed build script
if [ -f "$PROJECT_DIR/scripts/build-fixed.sh" ]; then
    bash "$PROJECT_DIR/scripts/build-fixed.sh"
else
    bash "$PROJECT_DIR/scripts/build.sh"
fi

echo "▶ 2) Skipping JS bundling (no dependencies to install)"
# Since we don't have any npm dependencies, we can skip this step
# The WebAssembly module and JS files are already built

echo "▶ 3) Stage finished assets"
# Copy everything from build directory (which includes all needed files)
rsync -az --delete "$PROJECT_DIR/build/" "$STAGE/"

# Ensure we have all the required files
echo "   Checking required files..."
for file in index.html style.css app.js convolution-module.js audio-processor.js convolution_reverb.js convolution_reverb.wasm; do
    if [ ! -f "$STAGE/$file" ]; then
        echo "   WARNING: Missing $file"
    else
        echo "   ✓ $file"
    fi
done

echo "▶ 4) Publish release to Nginx docroot"
RSYNC_DEST="/var/www/convolution.musicsian.com/releases/$STAMP/"
sudo mkdir -p "$(dirname "$RSYNC_DEST")"
sudo rsync -az --delete "$STAGE/" "$RSYNC_DEST"

echo "▶ 5) Flip 'current' symlink"
sudo ln -nfs "$RSYNC_DEST" /var/www/convolution.musicsian.com/current

echo "▶ 6) Restore SELinux context"
sudo restorecon -Rv "$RSYNC_DEST" >/dev/null 2>&1 || echo "   (SELinux context restoration skipped)"

echo "▶ 7) Reload Nginx"
sudo systemctl reload nginx || sudo nginx -s reload || echo "   (Nginx reload failed - check configuration)"

echo "✓ Deployed $STAMP to convolution.musicsian.com"
echo ""
echo "Test URLs:"
echo "  - https://convolution.musicsian.com/"
echo "  - https://convolution.musicsian.com/test.html"