# rec.sh — 터미널 작업 기록기

명령어와 그 출력을 **깨끗한 텍스트 로그로 남기는** 셸 스크립트입니다.
장애 대응이나 RMA 조사처럼 "무엇을 확인했는지" 증거로 남겨야 하는 작업에
쓰려고 만들었습니다.

`run`을 붙인 명령만 기록됩니다. 시행착오로 이것저것 쳐보는 명령은 그냥
치고, **증거로 남길 가치가 있는 명령에만** `run`을 붙이면 됩니다.
로그는 `$HOME/rec_logs/YYYYmmdd_HHMMSS.log`에 쌓입니다.

> 영어 레퍼런스는 [`rec-help.md`](rec-help.md)에 있습니다. 스크립트에
> 내장된 `rec-help` 도움말도 영어인데, 이는 리눅스 콘솔(tty) 폰트가
> 한글 글리프를 렌더링하지 못해 실제 서버 콘솔에서는 한글이 깨진 네모로
> 보이기 때문입니다. 파일 인코딩 문제가 아니라 콘솔 폰트의 한계라,
> MobaXterm 같은 SSH 클라이언트로 접속하면 같은 UTF-8 텍스트가 정상적으로
> 보입니다. 이 문서는 워크스테이션에서 읽는 용도입니다.

---

## 빠른 시작

```bash
git clone https://github.com/terry8408/Claude_Automation.git
cd Claude_Automation/rec
source rec.sh                 # 실행(./rec.sh)이 아니라 source 해야 합니다

run nvidia-smi -L
run 'nvidia-smi -q | egrep -i "Serial|Bus"'

cat "$RECLOG"                 # 지금까지 기록된 내용 전체
rec-off                       # 기록 중지 (로그 파일은 그대로 남습니다)
```

---

## 왜 `source` 해야 하나요

`source rec.sh`는 `run`과 `rec-off` 함수를 **현재 셸에** 정의합니다.
`./rec.sh`로 실행하면 자식 셸에 정의됐다가 그 셸이 끝나면서 같이 사라지므로
아무것도 남지 않습니다. 그래서 직접 실행하면 도움말만 출력하고 종료합니다.

스크립트는 `$0`와 `${BASH_SOURCE[0]}`를 비교해 이를 구분합니다. 두 값은
파일을 실행했을 때만 일치합니다.

---

## 시작과 이어쓰기

| 명령 | 동작 |
| --- | --- |
| `source rec.sh` | 이전 로그가 있으면 이어쓸지 새로 만들지 물어봄 |
| `source rec.sh -n` | 항상 **새 로그** 파일로 시작 (묻지 않음) |
| `source rec.sh -r` | 항상 최신 로그에 **이어쓰기** (묻지 않음) |
| `source rec.sh --help` | 도움말 출력 후 종료 |
| `./rec.sh` | 도움말 출력 후 종료 (위 설명 참고) |

**재부팅한 경우.** 새 셸이 뜨면서 함수가 사라지므로 다시 source 해야 합니다.
`source rec.sh -r`를 쓰면 이전 로그에 계속 이어서 기록합니다. 세션 경계는
아래 구분선으로 표시되어 나중에 봐도 어디서 끊겼는지 알 수 있습니다.

```
##### session resumed: 2026-07-08 13:00:00 (/dev/tty1) #####
```

**로그 위치.** `$HOME/rec_logs/` 고정 절대 경로라 어느 디렉터리에서
source 하든 동일합니다. 바꾸려면:

```bash
REC_DIR=/원하는/절대경로 source rec.sh
```

현재 로그 파일 경로는 항상 `$RECLOG`에 들어 있습니다.

---

## 명령 기록하기

단순한 명령은 따옴표 없이 그대로 씁니다.

```bash
run lsblk
run smartctl -a /dev/sdd
run grep -c "Chassis Serial" /var/log/syslog
```

파이프, 리다이렉트, `;`, `&&` 등 **셸 문법이 들어가면 명령 전체를
따옴표로 감싸야** 합니다.

```bash
run 'nvidia-smi -q | egrep -i "Serial|Bus"'
run 'storcli /call show all | grep Status'
run 'dmesg | tail -50 > /tmp/dmesg.txt; wc -l /tmp/dmesg.txt'
```

따옴표가 없으면 바깥 셸이 `run`을 호출하기 **전에** 파이프라인을 먼저
쪼개버립니다. 그러면 첫 `|` 앞부분만 기록기에 전달되고 나머지는 로그에
아예 남지 않습니다.

### 꼭 기억할 따옴표 규칙

`'...'` 안에서는 `"..."`를 쓰세요. **`'...'`를 또 쓰면 안 됩니다.**

```bash
run 'nvidia-smi -q | egrep -i "Serial|Bus"'    # 정상
run "nvidia-smi -q | egrep -i 'Serial|Bus'"    # 정상
run 'nvidia-smi -q | egrep -i 'Serial|Bus''    # 깨짐
```

마지막 줄은 **스크립트 버그가 아니고, 스크립트 안에서 고칠 수도 없습니다.**
셸은 작은따옴표를 중첩할 수 없어서, 두 번째 `'`에서 첫 따옴표를 닫고 `|`를
진짜 파이프로 해석한 뒤 `Bus`를 별개 명령으로 실행하려 합니다. 이 모든 게
`run`이 호출되기도 전에 일어납니다.

```
run 'nvidia-smi -q | egrep -i Serial'  |  Bus
                                       ↑ 진짜 파이프  ↑ 별개 명령
```

증상은 `Command 'bus' not found`와 함께 로그에 잘린 명령줄이 남는 것입니다.
작은따옴표 안에 작은따옴표를 꼭 써야 한다면 닫았다 다시 열면 됩니다.

```bash
run 'egrep -i '\''Serial|Bus'\'' /tmp/gpu.txt'
```

`"..."`를 쓰면 **바깥 셸이** `$VAR`와 `` `cmd` ``를 먼저 확장한 뒤 기록기에
넘깁니다. 즉 로그에는 확장된 결과가 남습니다. 입력한 그대로 남기고 싶으면
`'...'`를 쓰세요.

실행 파일 경로에 공백이 있으면 안쪽 따옴표가 필요합니다. 인자가 하나면
명령줄로 해석하기 때문입니다.

```bash
run '"/opt/my tool.sh" --flag'
```

---

## 인자 처리 방식

`run`은 받은 인자 개수로 동작을 나눕니다.

- **인자 1개** — 명령 *줄*로 보고 평가합니다. 그래서 파이프, 리다이렉트 등
  셸 문법이 동작합니다. 로그에는 입력 그대로 기록됩니다.
- **인자 여러 개** — `command`로 그대로 넘깁니다. 따옴표가 필요 없고 인자가
  다시 쪼개질 일도 없습니다. 로그에는 `printf %q`로 따옴표를 복원해
  기록하므로, 로그를 복사해 재실행해도 같은 명령이 됩니다.

  ```
  run grep -c "Chassis Serial" file
  →  $ grep -c Chassis\ Serial file
  ```

  따옴표가 필요한 인자만 처리하므로 평범한 명령은 로그 모양이 그대로입니다.

명령 텍스트는 화면에서 긁어오는 게 아니라 **셸이 넘겨준 인자에서** 가져옵니다.
그래서 탭 완성, 방향키 편집, 붙여넣기를 아무리 해도 기록되는 명령이
망가지지 않습니다.

---

## 동작 확인된 셸 문법

아래는 모두 정상 실행 + 정상 기록됩니다.

| 문법 | 예시 |
| --- | --- |
| 파이프 | `run 'dmesg \| tail -20'` |
| 리다이렉트 | `run 'nvidia-smi > /tmp/gpu.txt; cat /tmp/gpu.txt'` |
| 순차 실행 | `run 'echo a; echo b'` |
| 조건 실행 | `run 'true && echo yes \|\| echo no'` |
| 변수 | `run 'echo "home=$HOME"'` |
| 명령 치환 | `` run 'echo "n=$(nproc)"' `` 및 백틱 |
| 글롭 | `run 'ls /dev/nvidia*'`, `?`, `[abc]`, `{1..3}` |
| 틸드 | `run 'ls ~'` |
| 서브셸 | `run '(cd /etc && pwd)'` |
| 이스케이프 | `run 'printf "a\tb\n"'`, `run 'echo "price: \$5"'` |
| 따옴표 중첩 | 위 규칙대로 양방향 모두 |

---

## 출력 정리

프로그램 출력에서 ANSI 색상·제어 문자를 제거해 로그에 남깁니다. 티켓이나
보고서에 붙여넣어도 깨지지 않게 하기 위해서입니다.

`ansi2txt`가 있으면 그것을 사용합니다.

```bash
apt install colorized-logs      # Debian / Ubuntu
```

없으면 출력을 그대로 통과시키는 방식으로 동작합니다. 기능은 다 되고,
로그에 이스케이프 시퀀스가 남을 뿐입니다.

출력은 화면과 파일에 **동시에** 기록되므로(`tee -a`), 결과를 실시간으로
보면서 작업할 수 있습니다.

---

## 기록 중지

```bash
rec-off
```

`run`, `rec-off`, 내부 헬퍼 함수와 `$RECLOG`를 셸에서 제거합니다.
**디스크의 로그 파일은 그대로 남습니다.** `exit`이나 Ctrl+D가 필요 없어서,
같은 세션에서 계속 작업하면서 기록만 멈추고 싶을 때 유용합니다.

---

## 여러 tty에서 쓸 때

셸 함수는 프로세스 단위라 tty1에서 source 한 `run` 함수를 tty2가 재사용할 수
없습니다. tty2에서는 이렇게 실행하세요.

```bash
source rec.sh -r
```

그러면 **같은 로그 파일에** 이어서 기록합니다. 다만 tty는 한 번에 하나씩
쓰시는 게 좋습니다. append 모드(`tee -a`)라 서로 덮어쓰지는 않지만, 동시에
쓰면 로그가 뒤섞여 읽기 어려워집니다.

---

## 문제 해결

| 증상 | 원인 |
| --- | --- |
| `run: command not found` | source 하지 않고 실행했거나, 새 셸이 열렸습니다. `source rec.sh -r` 하세요. |
| `Command 'bus' not found` | 작은따옴표 중첩입니다. 위 따옴표 규칙 참고. |
| 로그가 첫 `\|`에서 잘림 | 같은 원인 — 바깥 셸이 파이프라인을 먼저 쪼갰습니다. |
| 명령줄 전체가 통째로 "not found" | 따옴표로 감싼 명령줄이 평가되지 않고 `command`로 넘어간 경우입니다. 인자 1개를 평가하는 현재 버전으로 업데이트하세요. |
| 로그에 `ESC[0m` 같은 게 잔뜩 | `ansi2txt`가 없습니다. `colorized-logs` 설치. |
| 콘솔에서 한글이 네모로 깨짐 | tty 폰트 한계입니다. 파일 문제가 아니니 SSH로 접속해서 보세요. |
