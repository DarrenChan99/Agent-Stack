#!/bin/bash
# Installs post-commit/post-merge hooks that rebuild Perch.app in the background.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
for h in post-commit post-merge; do
  cat > ".git/hooks/$h" <<H
#!/bin/bash
# skip while a rebase/cherry-pick is replaying commits
for p in rebase-merge rebase-apply CHERRY_PICK_HEAD; do [ -e "\$(git rev-parse --git-path \$p)" ] && exit 0; done
LOG="\$HOME/Library/Logs/Perch-build.log"
mkdir -p "\$HOME/Library/Logs"
nohup bash -c 'echo "=== \$(date "+%F %T") \$(git -C "$ROOT" rev-parse --short HEAD)"; "$ROOT/Scripts/build-app.sh"' >> "\$LOG" 2>&1 &
H
  chmod +x ".git/hooks/$h"
done
echo "installed post-commit and post-merge"
