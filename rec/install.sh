#!/bin/bash
# ============================================================
#  rec.sh installer
#
#  Installs a 'rec-on' shell function that fetches the current rec.sh
#  at use time and sources it. The installed block never needs updating
#  -- rec.sh itself is fetched fresh on every 'rec-on'.
#
#    curl -fsSL <raw>/rec/install.sh | bash                 install
#    curl -fsSL <raw>/rec/install.sh | bash -s -- --system  all users
#    curl -fsSL <raw>/rec/install.sh | bash -s -- --uninstall
#
#  English-only on purpose, same reason as rec-help: the Linux virtual
#  console font cannot render CJK, so Korean would be broken boxes on a
#  physical server console. Korean guide: rec/README.md
# ============================================================

set -u

REC_URL="https://raw.githubusercontent.com/terry8408/Claude_Automation/main/rec/rec.sh"
DOCS_URL="https://github.com/terry8408/Claude_Automation/tree/main/rec"
MARK_BEGIN='# >>> rec-on >>>'
MARK_END='# <<< rec-on <<<'

CACHE_DIR="$HOME/.cache/rec"
LOG_DIR="${REC_DIR:-$HOME/rec_logs}"
: "${REC_SYSTEM_FILE:=/etc/profile.d/rec.sh}"   # overridable for testing

MODE="install"
SCOPE="user"
ASSUME_YES=0

usage() {
  cat <<EOF
rec.sh installer

Usage: install.sh [OPTION]

  (no option)   install rec-on into ~/.bashrc          (per user)
  --system      install into $REC_SYSTEM_FILE   (all users)
  --uninstall   remove rec-on and the cache; KEEPS work logs
  --purge       --uninstall, and also delete logs in $LOG_DIR
  --yes         skip the confirmation prompt (for --purge)
  --help        show this text

Docs: $DOCS_URL
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --system)    SCOPE="system" ;;
    --uninstall) MODE="uninstall" ;;
    --purge)     MODE="purge" ;;
    --yes|-y)    ASSUME_YES=1 ;;
    --help|-h)   usage; exit 0 ;;
    *) echo "install.sh: unknown option '$1'" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [ "$SCOPE" = "system" ]; then
  TARGET="$REC_SYSTEM_FILE"
else
  TARGET="$HOME/.bashrc"
fi

# ---- ask on /dev/tty: stdin is the script itself under 'curl | bash' ----
confirm() {
  [ "$ASSUME_YES" = 1 ] && return 0
  # Must actually open /dev/tty: '[ -r /dev/tty ]' passes on permissions
  # even when the process has no controlling terminal, and the open then
  # fails with ENXIO mid-prompt.
  if { : < /dev/tty; } 2>/dev/null; then
    printf '%s [y/N] ' "$1" > /dev/tty
    local ans=""
    read -r ans < /dev/tty || return 1
    case "$ans" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
  fi
  echo "  cannot prompt for confirmation (no tty). Re-run with --yes." >&2
  return 1
}

# Strip a previously installed block. Written through the original file
# so its permissions and inode survive.
remove_block() {
  local f="$1" tmp
  [ -f "$f" ] || return 0
  grep -qF "$MARK_BEGIN" "$f" || return 0
  tmp="$(mktemp)" || return 1
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip
  ' "$f" > "$tmp" && cat "$tmp" > "$f"
  rm -f "$tmp"
}

emit_block() {
  cat <<EOF
$MARK_BEGIN
# Terminal work recorder. 'rec-on' fetches the current rec.sh, caches it
# at ~/.cache/rec/rec.sh, and sources it -- so this block itself never
# needs updating. Falls back to the cache when offline.
# Docs: $DOCS_URL
rec-on() {
  local u=$REC_URL
  local c=~/.cache/rec/rec.sh
  mkdir -p "\${c%/*}"
  if curl -fsSL --max-time 5 "\$u" -o "\$c.tmp" 2>/dev/null; then
    mv "\$c.tmp" "\$c"
  else
    rm -f "\$c.tmp"
    [ -f "\$c" ] && echo "rec: offline, using cached copy" >&2
  fi
  [ -f "\$c" ] || { echo "rec: no network and no cache" >&2; return 1; }
  source "\$c" "\$@"
}
$MARK_END
EOF
}

# ---- uninstall / purge ----
if [ "$MODE" = "uninstall" ] || [ "$MODE" = "purge" ]; then
  removed=0
  for f in "$HOME/.bashrc" "$REC_SYSTEM_FILE"; do
    if [ -f "$f" ] && grep -qF "$MARK_BEGIN" "$f"; then
      if [ -w "$f" ]; then
        remove_block "$f"
        echo "removed rec-on from $f"
        removed=1
      else
        echo "cannot write $f (try sudo)" >&2
      fi
    fi
  done
  [ "$removed" = 0 ] && echo "no rec-on block found"

  if [ -d "$CACHE_DIR" ]; then
    rm -rf "$CACHE_DIR"
    echo "removed cache $CACHE_DIR"
  fi

  if [ "$MODE" = "purge" ]; then
    n=0
    [ -d "$LOG_DIR" ] && n="$(find "$LOG_DIR" -maxdepth 1 -name '*.log' 2>/dev/null | wc -l)"
    if [ "$n" -gt 0 ]; then
      echo ""
      echo "  $LOG_DIR contains $n work log(s)."
      echo "  These are your recorded evidence and cannot be recovered."
      if confirm "  Delete them?"; then
        rm -rf "$LOG_DIR"
        echo "  deleted $LOG_DIR"
      else
        echo "  kept $LOG_DIR"
      fi
    else
      echo "no logs to delete in $LOG_DIR"
    fi
  else
    if [ -d "$LOG_DIR" ]; then
      echo ""
      echo "work logs kept in $LOG_DIR (use --purge to delete them)"
    fi
  fi

  echo ""
  echo "open a new shell, or run: unset -f rec-on run rec-off 2>/dev/null"
  exit 0
fi

# ---- install ----
if ! command -v curl >/dev/null 2>&1; then
  echo "install.sh: curl is required but not installed." >&2
  echo "  Debian/Ubuntu:  apt install -y curl" >&2
  exit 1
fi

if [ "$SCOPE" = "system" ]; then
  mkdir -p "$(dirname "$TARGET")" 2>/dev/null
  if [ -e "$TARGET" ] && [ ! -w "$TARGET" ]; then
    echo "install.sh: cannot write $TARGET (run with sudo)" >&2; exit 1
  fi
  if [ ! -e "$TARGET" ] && [ ! -w "$(dirname "$TARGET")" ]; then
    echo "install.sh: cannot write $(dirname "$TARGET") (run with sudo)" >&2; exit 1
  fi
  : > "$TARGET"
  emit_block >> "$TARGET"
else
  [ -e "$TARGET" ] || : > "$TARGET"
  if [ ! -w "$TARGET" ]; then
    echo "install.sh: cannot write $TARGET" >&2; exit 1
  fi
  remove_block "$TARGET"                       # replace, never duplicate
  [ -s "$TARGET" ] && [ -n "$(tail -c 1 "$TARGET")" ] && echo "" >> "$TARGET"
  emit_block >> "$TARGET"
fi

echo "installed rec-on -> $TARGET"

if ! command -v ansi2txt >/dev/null 2>&1; then
  echo ""
  echo "note: ansi2txt not found. rec.sh works without it, but colour"
  echo "      codes will be left in the logs. To get clean text:"
  echo "        apt install -y colorized-logs"
fi

if [ "$SCOPE" = "system" ]; then
  echo ""
  echo "note: $TARGET is read by LOGIN shells only -- console login, ssh,"
  echo "      'su -', 'sudo -i'. A plain 'bash' started inside an existing"
  echo "      session will not see rec-on. Per-user install (no --system)"
  echo "      covers both."
fi

cat <<EOF

next:
  source $TARGET      # or just log in again
  rec-on                       # starts recording; then use 'run <cmd>'

if you copied rec.sh onto this machine before, delete those copies so
you do not source an outdated one by habit:
  ls ~/rec.sh ~/*/rec.sh 2>/dev/null
EOF
