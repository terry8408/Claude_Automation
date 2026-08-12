# Claude_Automation

서버 운영·장애 대응에 쓰는 자동화 도구 모음입니다.

```bash
git clone https://github.com/terry8408/Claude_Automation.git
cd Claude_Automation
```

## 도구

### [`rec/`](rec/) — 터미널 작업 기록기

명령어와 출력을 깨끗한 텍스트 로그로 남깁니다. RMA 조사처럼 "무엇을
확인했는지" 증거로 남겨야 하는 작업용입니다.

머신마다 한 줄로 설치하면 이후 자동으로 최신 버전을 씁니다.

```bash
curl -fsSL https://raw.githubusercontent.com/terry8408/Claude_Automation/main/rec/install.sh | bash
source ~/.bashrc

rec-on
run 'nvidia-smi -q | egrep -i "Serial|Bus"'
```

- [한국어 사용법](rec/README.md)
- [English reference](rec/rec-help.md)

## 기타

- `test.html` — 월별 매출 인터랙티브 바 차트 데모
