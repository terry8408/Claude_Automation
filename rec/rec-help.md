# rec.sh — Terminal Work Recorder

Records commands and their output into a clean text log, so a support
session or an RMA investigation leaves reusable written evidence.

Only commands prefixed with `run` are recorded. Type trial-and-error
commands normally; prefix a command with `run` when the result is worth
keeping. The log ends up in `$HOME/rec_logs/YYYYmmdd_HHMMSS.log`.

> This document is in English on purpose. The Linux virtual console
> (tty) font cannot render CJK glyphs, so Korean shows up as broken
> boxes on a physical server console. It is a console-font limitation,
> not a file-encoding problem — the same UTF-8 text renders fine over
> an SSH client such as MobaXterm. A Korean guide lives in
> [`README.md`](README.md), for reading on a normal workstation.

---

## Install once, stay current

Put this function in `~/.bashrc` on each machine — once.

```bash
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
```

**That line never changes**, so every session picks up the current
rec.sh by itself — there are no copies left to keep in sync.

The fetched file is cached at `~/.cache/rec/rec.sh` and used as a
fallback when the network is unreachable, because this tool is often
needed exactly when something is broken. An unresponsive network is
given up on after 5 seconds rather than hanging.

```bash
rec-on                        # asks resume-or-new if a log exists
rec-on -r                     # resume the latest log straight away

run nvidia-smi -L
run 'nvidia-smi -q | egrep -i "Serial|Bus"'

cat "$RECLOG"                 # everything recorded so far
rec-off                       # stop recording (log files are kept)
```

## Other ways to install

**git clone** — when you want the source alongside the other tools:

```bash
git clone https://github.com/terry8408/Claude_Automation.git
cd Claude_Automation/rec
source rec.sh                 # note: SOURCE it, do not execute it
```

**Single file** — for air-gapped machines:

```bash
scp rec.sh user@server:~/     # then, on the server: source ~/rec.sh
```

rec.sh is deliberately self-contained: one file is enough, and the
help text is embedded so `rec-help` works without these documents.

## Versioning

Every log header records the version that produced it:

```
##### rec.sh v1.0.0 | session started: 2026-08-12 12:41:00 (/dev/tty1) #####
```

Installations update themselves, so without this you could not tell
later which behaviour a given log reflects. Resuming a log (`-r`) after
an update writes a fresh header, leaving the version boundary visible
at the exact point it changed. Also available in `$REC_VERSION`.

`REC_VERSION` near the top of rec.sh must be bumped whenever recording
behaviour changes — that is what makes the stamp meaningful.

---

## Why it must be sourced

`source rec.sh` defines `run` and `rec-off` **in your current shell**.
Executing `./rec.sh` would define them inside a child shell that exits
immediately, leaving nothing behind — so running it directly just prints
this help and stops.

The script detects the difference by comparing `$0` with
`${BASH_SOURCE[0]}`: they match only when the file is executed.

---

## Starting and resuming

| Command | Behaviour |
| --- | --- |
| `source rec.sh` | If a previous log exists, asks whether to resume it or start a new one |
| `source rec.sh -n` | Always start a **new** log file, no prompt |
| `source rec.sh -r` | Always **resume** the most recent log, no prompt |
| `source rec.sh --help` | Print the help text and stop |
| `./rec.sh` | Print the help text and stop (see above) |

A reboot starts a fresh shell, so the functions are gone and you must
source again. Use `source rec.sh -r` to keep appending to the previous
log. A separator marks the boundary so sessions stay distinguishable:

```
##### session resumed: 2026-07-08 13:00:00 (/dev/tty1) #####
```

**Log location.** `$HOME/rec_logs/` — a fixed absolute path, so it does
not matter which directory you source from. Override it with:

```bash
REC_DIR=/your/absolute/path source rec.sh
```

The current log path is always in `$RECLOG`.

---

## Recording commands

Simple commands need no quoting:

```bash
run lsblk
run smartctl -a /dev/sdd
run grep -c "Chassis Serial" /var/log/syslog
```

Anything involving shell syntax — pipes, redirects, `;`, `&&` — must be
quoted **as a whole**:

```bash
run 'nvidia-smi -q | egrep -i "Serial|Bus"'
run 'storcli /call show all | grep Status'
run 'dmesg | tail -50 > /tmp/dmesg.txt; wc -l /tmp/dmesg.txt'
```

Without the quotes the outer shell splits the pipeline *before* `run` is
called, so only the part before the first `|` reaches the recorder and
the rest never appears in the log.

### The quoting rule worth memorising

Inside `'...'`, use `"..."` for the inner quotes — **never `'...'`
again**:

```bash
run 'nvidia-smi -q | egrep -i "Serial|Bus"'    # GOOD
run "nvidia-smi -q | egrep -i 'Serial|Bus'"    # GOOD
run 'nvidia-smi -q | egrep -i 'Serial|Bus''    # BROKEN
```

The broken line is not a recorder problem and cannot be fixed inside the
script. The shell cannot nest single quotes, so it closes the first
quote at the second `'`, treats the `|` as a real pipe, and tries to run
`Bus` as a separate command — all before `run` ever executes:

```
run 'nvidia-smi -q | egrep -i Serial'  |  Bus
                                       ↑ real pipe   ↑ separate command
```

Symptom: `Command 'bus' not found` together with a truncated line in the
log. If you genuinely need single quotes inside single quotes, close and
reopen them:

```bash
run 'egrep -i '\''Serial|Bus'\'' /tmp/gpu.txt'
```

Note that `"..."` lets the **outer** shell expand `$VAR` and `` `cmd` ``
before the recorder sees them, so the log stores the expanded text.
Prefer `'...'` when you want the command recorded exactly as typed.

A command whose path contains spaces needs inner quotes too, because a
single argument is parsed as a command line:

```bash
run '"/opt/my tool.sh" --flag'
```

---

## How arguments are handled

`run` dispatches on the number of arguments it receives:

- **One argument** — treated as a command *line* and evaluated, so
  pipes, redirects and other shell syntax work. Logged verbatim.
- **Several arguments** — passed straight to `command`, which needs no
  quoting and cannot re-split the arguments. Logged with the quoting
  restored (via `printf %q`) so the recorded line stays replayable:

  ```
  run grep -c "Chassis Serial" file
  →  $ grep -c Chassis\ Serial file
  ```

  Only arguments that need quoting get it, so ordinary commands look
  unchanged in the log.

The command text is taken from the shell's arguments, never scraped from
the screen, so tab-completion, arrow-key editing and paste cannot
corrupt what gets recorded.

---

## Verified shell syntax

All of the following are recorded and executed correctly:

| Syntax | Example |
| --- | --- |
| Pipe | `run 'dmesg \| tail -20'` |
| Redirect | `run 'nvidia-smi > /tmp/gpu.txt; cat /tmp/gpu.txt'` |
| Sequencing | `run 'echo a; echo b'` |
| Conditionals | `run 'true && echo yes \|\| echo no'` |
| Variables | `run 'echo "home=$HOME"'` |
| Substitution | `` run 'echo "n=$(nproc)"' `` and backticks |
| Globs | `run 'ls /dev/nvidia*'`, `?`, `[abc]`, `{1..3}` |
| Tilde | `run 'ls ~'` |
| Subshell | `run '(cd /etc && pwd)'` |
| Escapes | `run 'printf "a\tb\n"'`, `run 'echo "price: \$5"'` |
| Both quote styles | nested either way, per the rule above |

---

## Output cleaning

Program output is stripped of ANSI colour and control characters, so the
log stays readable when pasted into a ticket or a report.

Stripping uses `ansi2txt` when available:

```bash
apt install colorized-logs      # Debian / Ubuntu
```

Without it the script falls back to passing output through unchanged —
everything still works, the log just keeps any escape sequences.

Output is written to the screen and the file at the same time (`tee -a`),
so you see results live while they are recorded.

---

## Stopping

```bash
rec-off
```

Removes `run`, `rec-off`, the internal helpers and `$RECLOG` from the
shell. **Log files on disk are kept.** No `exit` or Ctrl+D needed —
useful when you want to stop recording but keep working in the same
session.

---

## Using several ttys

Shell functions are per-process, so a second tty cannot reuse the `run`
function sourced on the first one. On the second tty run:

```bash
source rec.sh -r
```

to append to the **same** log file. Use the ttys one at a time; append
mode (`tee -a`) keeps the two from overwriting each other, but
interleaved concurrent writes would still be confusing to read.

---

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| `run: command not found` | The script was executed instead of sourced, or a new shell was opened. Run `source rec.sh -r`. |
| `Command 'bus' not found` | Nested single quotes. See the quoting rule above. |
| Log line stops at the first `\|` | Same cause — the outer shell split the pipeline. |
| `<command>: command not found` where the whole line is the name | A quoted command line reached `command` instead of being evaluated. Upgrade to the current version, which evaluates single arguments. |
| Log full of `ESC[0m` sequences | `ansi2txt` is missing — install `colorized-logs`. |
| Korean text is broken boxes on the console | tty font limitation, not the file. Read the docs over SSH instead. |
