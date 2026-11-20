# Source me. acquire_lock DIR: exit 0 quietly if another run holds DIR, else hold it until this shell exits.
# ponytail: a kill -9 leaves a stale lockdir; delete it by hand.
acquire_lock() {
  mkdir "$1" 2>/dev/null || exit 0
  LOCKDIR=$1
  trap 'rm -rf "$LOCKDIR"' EXIT
}
