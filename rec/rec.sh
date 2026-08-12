# ============================================================
#  Terminal work recorder (commands + output as clean text)
#
#  Start:   source rec.sh          # must be SOURCED (not ./rec.sh)
#  Record:  run <command>          # only 'run'-prefixed lines are logged
#  Stop:    rec-off                # remove functions/vars (log file kept)
#  Help:    rec-help  /  ./rec.sh  /  source rec.sh --help
#
#  Principle: the command is taken from the shell's arguments ($*),
#             not scraped from the screen, so Tab-completion / arrow
#             editing / paste never corrupt the recorded command.
#
#  English-only on purpose: the Linux virtual console (tty) font
#  cannot render CJK glyphs, so Korean would look broken there. It is
#  a console-font limitation, not a file-encoding problem -- the same
#  UTF-8 text renders fine over an SSH client such as MobaXterm.
# ============================================================

# Bump this whenever the recording behaviour changes. It is stamped into
# every log header, so a log always states which version produced it --
# necessary because installations fetch this file from main and update
# themselves silently.
REC_VERSION="1.0.0"

# ---- help ----
rec-help() {
  cat <<'EOF'
=== Terminal work recorder =================================
[What]
  Records commands (prefixed with 'run') and their output into a
  clean text log. Type trial-and-error commands WITHOUT 'run', and
  prefix only the commands you want to keep as RMA evidence.

[Start]
  source rec.sh        if a previous log exists, asks resume-or-new
  source rec.sh -n     always start a NEW log file (no prompt)
  source rec.sh -r     always RESUME the latest log (no prompt)
  * Running ./rec.sh directly only prints this help: the functions
    would be defined in a child shell and vanish when it exits.

[Install once, stay current]
  Put this in ~/.bashrc on each machine. The line never changes, so
  every session picks up the latest rec.sh by itself -- no copies to
  keep in sync. It caches the file and falls back to the cache when
  the network is down, which matters during an outage.

    rec-on() {
      local u=https://raw.githubusercontent.com/terry8408/Claude_Automation/main/rec/rec.sh
      local c=~/.cache/rec/rec.sh
      mkdir -p "${c%/*}"
      if curl -fsSL --max-time 5 "$u" -o "$c.tmp" 2>/dev/null; then
        mv "$c.tmp" "$c"
      else
        rm -f "$c.tmp"
        [ -f "$c" ] && echo "rec: offline, using cached copy" >&2
      fi
      [ -f "$c" ] || { echo "rec: no network and no cache" >&2; return 1; }
      source "$c" "$@"
    }

  Then use 'rec-on' / 'rec-on -r' instead of 'source rec.sh'.

[Version]
  Every log header records the version that produced it:
      ##### rec.sh v1.0.0 | session started: ... (/dev/tty1) #####
  Since installs update themselves, this is how you tell later which
  behaviour a given log reflects. Also in $REC_VERSION.

[Resume after reboot]
  A reboot starts a fresh shell, so the functions are gone and you
  must source again. Use:
      source rec.sh -r
  to keep appending to the previous log. A separator like
      ##### session resumed: 2026-07-08 13:00:00 (/dev/tty1) #####
  is inserted so session boundaries stay visible.

[Record]
  run lsblk
  run smartctl -a /dev/sdd
  Commands typed without 'run' are NOT logged.

  Pipes, redirects and other shell syntax: QUOTE THE WHOLE COMMAND.
      run 'nvidia-smi -q | egrep -i "Serial|bus"'
      run 'storcli /call show all | grep Status'
  A single quoted argument is interpreted as a command line, so the
  pipeline runs (and is logged) as one unit. Without the quotes the
  outer shell splits the pipeline first, and only the part before
  the first '|' would reach the recorder.

[Quoting rule -- the one thing to remember]
  Inside '...' use "..." for the inner quotes, never '...' again:
      run 'nvidia-smi -q | egrep -i "Serial|bus"'    GOOD
      run "nvidia-smi -q | egrep -i 'Serial|bus'"    GOOD
      run 'nvidia-smi -q | egrep -i 'Serial|bus''    BROKEN
  The broken line is not a recorder problem and cannot be fixed here:
  the shell cannot nest single quotes, so it ends the first quote at
  the second ', leaves the | as a real pipe, and tries to run 'bus' as
  a separate command -- all before 'run' is ever called. Symptom:
  "Command 'bus' not found" plus a truncated line in the log.
  If you must keep single quotes inside single quotes, close and
  re-open them:  run 'egrep -i '\''Serial|bus'\'' file'

  Note that "..." lets the OUTER shell expand $VAR and `cmd` before
  the recorder sees them. Prefer '...' when you want the command
  logged exactly as typed.

  A command whose PATH contains spaces needs inner quotes too, since a
  single argument is parsed as a command line:
      run '"/opt/my tool.sh" --flag'

[Check]
  echo "$RECLOG"    current log file path
  cat  "$RECLOG"    show everything recorded so far

[Stop]  (without exit / Ctrl+D)
  rec-off           removes functions/vars only; log files remain

[Log location]
  $HOME/rec_logs/   fixed absolute path (same no matter where you
                    source from).
  Override:  REC_DIR=/your/absolute/path source rec.sh

[Multiple ttys]
  Shell functions are per-process, so tty2 cannot reuse the 'run'
  function sourced on tty1. Instead run 'source rec.sh -r' on tty2 to
  append to the SAME log file. Use the ttys one at a time; append mode
  (tee -a) keeps the two from overwriting each other.
============================================================
EOF
}

# ---- direct-exec guard ----
# When sourced, $0 is the shell name (bash) while BASH_SOURCE is this
# file -> they differ. When run as ./rec.sh, both are this file ->
# they match -> just print help and exit, because the functions would
# die together with the child shell and starting would be pointless.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "WARNING: source this script, do not run it directly:"
  echo ""
  echo "    source rec.sh"
  echo ""
  rec-help
  exit 0
fi

# ---- --help / -h ----
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
  rec-help
  return 0
fi

# ---- choose log file: new vs resume ----
REC_DIR="${REC_DIR:-$HOME/rec_logs}"
mkdir -p "$REC_DIR"

# latest log = last by name; timestamp names make name-sort == time-sort
__REC_LATEST="$(ls -1 "$REC_DIR"/*.log 2>/dev/null | tail -1)"

__REC_MODE="ask"
[ "$1" = "-n" ] && __REC_MODE="new"
[ "$1" = "-r" ] && __REC_MODE="resume"

if [ "$__REC_MODE" = "ask" ] && [ -n "$__REC_LATEST" ]; then
  printf 'Previous log found: %s\n' "$__REC_LATEST"
  printf 'Resume it, or start a new one? [r/N] '
  read -r __REC_ANS
  case "$__REC_ANS" in
    r|R) __REC_MODE="resume" ;;
    *)   __REC_MODE="new" ;;
  esac
fi

if [ "$__REC_MODE" = "resume" ] && [ -n "$__REC_LATEST" ]; then
  export RECLOG="$__REC_LATEST"
  __REC_EVENT="session resumed"
else
  export RECLOG="$REC_DIR/$(date +%Y%m%d_%H%M%S).log"
  __REC_EVENT="session started"
fi

# Header on both paths: a resumed log that was updated in between then
# shows the version change at the exact point it happened.
if __REC_TTY="$(tty)"; then :; else __REC_TTY="n/a"; fi
printf '\n##### rec.sh v%s | %s: %s (%s) #####\n' \
       "$REC_VERSION" "$__REC_EVENT" "$(date '+%Y-%m-%d %H:%M:%S')" "$__REC_TTY" \
       >> "$RECLOG"

unset __REC_MODE __REC_LATEST __REC_ANS __REC_TTY __REC_EVENT

# ---- output stripper: ansi2txt if present, else passthrough ----
if command -v ansi2txt >/dev/null 2>&1; then
  __REC_STRIP() { ansi2txt; }
else
  __REC_STRIP() { cat; }   # fallback when colorized-logs is not installed
fi

# ---- command dispatcher ----
# A single argument is treated as a command LINE and evaluated, so
# quoted pipelines/redirects work: run 'cmd | grep x'. Bare multi-word
# invocations (run smartctl -a /dev/sdd) keep going through 'command',
# which needs no quoting and cannot re-split the arguments.
__REC_EXEC() {
  if [ "$#" -eq 1 ]; then
    eval "$1"
  else
    command "$@"
  fi
}

# ---- command formatter (for the log line) ----
# With several arguments, "$*" would flatten them and silently drop the
# quoting: run grep -c "Chassis Serial" f would be logged as
# `grep -c Chassis Serial f`, which means something else when replayed.
# Re-quote only the arguments that need it, so the logged line stays
# both readable and copy-paste accurate.
__REC_FMT() {
  local out= a
  for a in "$@"; do
    case $a in
      '')                       out="$out ''" ;;
      *[!A-Za-z0-9_.,:=@%+/-]*) out="$out $(printf '%q' "$a")" ;;
      *)                        out="$out $a" ;;
    esac
  done
  printf '%s' "${out# }"
}

# ---- record function ----
run() {
  local __rec_line
  if [ "$#" -eq 1 ]; then
    __rec_line="$1"              # already a command line: log it verbatim
  else
    __rec_line="$(__REC_FMT "$@")"
  fi
  {
    printf '\n$ %s\n' "$__rec_line"    # command: straight from args (never corrupted)
    __REC_EXEC "$@" 2>&1 | __REC_STRIP # output: color/control chars stripped
  } | tee -a "$RECLOG"                 # screen + file at the same time
}

# ---- teardown (no exit / Ctrl+D needed) ----
rec-off() {
  unset RECLOG REC_VERSION
  unset -f run __REC_EXEC __REC_FMT __REC_STRIP rec-help rec-off
  echo "recorder off (log files are kept on disk)"
}

echo "rec.sh v$REC_VERSION"
echo "recording -> $RECLOG"
echo "usage: run <command>    (details: rec-help)"
echo "stop:  rec-off"
