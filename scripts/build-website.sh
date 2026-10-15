#!/usr/bin/env bash
# Buildless static site: whitelist public assets, never copy operational directories.
set -euo pipefail
task_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
task_site="$task_root/website/.build"
mkdir -p "$task_site/assets"
cp "$task_root/website/index.html" "$task_root/website/style.css" "$task_root/website/site.js" "$task_site/"
cp "$task_root/website/privacy.html" "$task_site/"
cp "$task_root/assets/readme/panorama.png" "$task_site/assets/"
cp "$task_root/assets/readme/welcome-0.2.0.png" "$task_site/assets/"
cp "$task_root/assets/readme/server-setup-0.2.1.png" "$task_site/assets/"
cp "$task_root/assets/readme/connection-card-0.2.1.png" "$task_site/assets/"
cp "$task_root/ui/Assets.xcassets/ConnectionScene.imageset/connection-scene.png" "$task_site/assets/"
cp "$task_root/artwork/icons/hermland-icon-messenger-1024.png" "$task_site/assets/icon.png"
printf 'PASS：静态下载页 %s\n' "$task_site"
