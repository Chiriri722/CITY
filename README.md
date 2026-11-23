# CITY

CITY는 Android Termux에서 Ubuntu 또는 Debian PRoot 컨테이너를 구성해 주요 CLI 코딩 에이전트를 설치하고 실행하는 Bash 도구입니다. 하나의 PRoot 배포판(`city-ubuntu` 또는 `city-debian`) 안에 고정된 버전의 Node.js와 각 에이전트를 격리된 경로(`/opt/city`)로 설치하고, Termux 홈 디렉터리를 공유해 로컬 프로젝트를 바로 편집할 수 있게 연결합니다.

에이전트는 PRoot 안의 일반 glibc Linux(arm64/x86_64) 환경에서 실행되므로, Termux에서 직접 설치되지 않는 도구도 대부분 그대로 쓸 수 있습니다. 모든 목록은 `bash city.sh --help`로도 확인할 수 있습니다.

| 지원 도구 | CITY 실행 명령 | 게스트 실행 파일 | 고정 설치 버전 | 배포 형식 |
| --- | --- | --- | --- | --- |
| OpenAI Codex | `codex` | `codex` | 0.154.0 | npm |
| OpenCode | `opencode` | `opencode` | 1.18.31 | npm |
| Google Antigravity CLI | `antigravity` | `agy` | 1.3.1 | 아카이브 |
| xAI Grok Build | `grok` | `grok` | 1.0.46 | npm |
| Meta Muse Code | `muse` | `muse` | 1.4.3-R5018.1 | 단일 바이너리 |
| Anthropic Claude Code | `claude` | `claude` | 2.1.330 | npm |
| Google Gemini CLI | `gemini` | `gemini` | 0.70.0 | npm |
| Qwen Code | `qwen` | `qwen` | 0.28.4 | npm |
| GitHub Copilot CLI | `copilot` | `copilot` | 1.0.114 | npm |
| Sourcegraph Amp | `amp` | `amp` | 0.0.1795449633-g4295dd | npm |
| Charm Crush | `crush` | `crush` | 0.102.0 | npm |
| Cline CLI | `cline` | `cline` | 3.0.75 | npm |
| Kilo Code CLI | `kilo` | `kilo` | 7.8.32 | npm |
| Augment Auggie | `auggie` | `auggie` | 1.2.2 | npm |
| Factory Droid | `droid` | `droid` | 1.17.2 | npm |
| Qoder CLI | `qoder` | `qodercli` | 1.1.96 | npm |
| Tencent CodeBuddy Code | `codebuddy` | `codebuddy` | 2.185.0 | npm |
| Continue CLI | `continue` | `cn` | 1.5.47 | npm |
| Forge Code | `forge` | `forge` | 2.13.21 | npm |
| Google Jules CLI | `jules` | `jules` | 0.1.42 | 아카이브 |
| Kiro CLI (AWS) | `kiro` | `kiro-cli` | 3.5.0 | 아카이브 |
| Aider | `aider` | `aider` | 0.86.2 | PyPI wheel |
| Mistral Vibe | `vibe` | `vibe` | 3.1.4 | PyPI wheel (Ubuntu 전용) |
| OpenHands CLI | `openhands` | `openhands` | 1.16.0 | PyPI wheel (Ubuntu 전용) |

- Antigravity는 터미널용 CLI만 설치하며 데스크톱 IDE는 포함하지 않습니다.
- Python 에이전트는 각자 별도 venv(`/opt/city/<agent>-<version>/venv`)에 설치되어 서로·배포판 패키지와 충돌하지 않습니다. Vibe·OpenHands는 Python 3.12가 필요하므로 Ubuntu 24.04(기본값)에서만 설치되고, Debian 12(Python 3.11)에서는 해당 항목만 실패로 보고됩니다.
- 포함하지 않은 도구와 이유는 [지원 범위와 제외 기준](#지원-범위와-제외-기준)을 참고하세요.

## 설치 및 업데이트

64비트 ARM 또는 x86_64 환경의 Termux, PRoot-Distro 5 이상, 인터넷 연결이 필요합니다.

### 새 기기에 처음 설치

```bash
pkg update && pkg install git
git clone https://github.com/Chiriri722/CITY.git "$HOME/CITY"
cd "$HOME/CITY"
bash city.sh install codex claude gemini
bash city.sh status
```

필요한 도구만 이름으로 나열해 설치하는 것을 권장합니다(`bash city.sh install aider`처럼 하나만 지정해도 됩니다). `bash city.sh install all`은 표의 모든 도구를 설치하며 내려받는 양이 수 GB에 이릅니다. 여러 개를 설치하다 하나가 실패해도 나머지는 계속 설치되고, 마지막에 실패한 이름만 다시 알려 줍니다. 실패한 도구의 기존 버전은 그대로 유지됩니다.

기본 배포판은 Ubuntu 24.04(`city-ubuntu`)이며, Debian 12(`city-debian`)를 쓰려면 설치와 실행 시 `export CITY_DISTRO=debian`을 지정합니다.

### 기존 기기 업데이트

새 폴더나 새 컨테이너를 만들지 않고 기존 체크아웃 폴더에서 그대로 갱신합니다.

```bash
CITY_DIR="$HOME/CITY"
git -C "$CITY_DIR" status --short
git -C "$CITY_DIR" pull --ff-only &&
bash "$CITY_DIR/city.sh" status &&
bash "$CITY_DIR/city.sh" update &&
bash "$CITY_DIR/city.sh" status
```

`update`는 이미 설치된 에이전트만 현재 CITY 체크아웃에 고정된 버전으로 갱신합니다(`update codex claude`처럼 일부만 지정할 수도 있습니다). 설치되지 않은 에이전트를 추가할 때는 `bash "$CITY_DIR/city.sh" install muse`처럼 `install` 명령을 사용합니다.

### 한 번 설치한 환경의 재사용

PRoot 배포판은 최초 `install` 때 한 번만 만들어지고, 이후 `install`·`update`·실행은 모두 같은 배포판을 재사용합니다. 재설치가 필요하지 않도록 다음을 보장합니다.

- **체크아웃 갱신 직후에도 실행 가능**: 각 에이전트는 설치·검증에 사용한 Node.js 버전을 기록(`.city-node`)하고 그 Node로 실행됩니다. 새 CITY가 Node 고정 버전을 올려도 `update` 전까지 기존 에이전트는 그대로 동작하며, `update`가 새 Node로 기동 확인을 마친 뒤에만 전환합니다. 기록이 없는 이전 설치본은 배포판에 있는 Node를 자동으로 사용합니다.
- **설치 중단 복구**: 배포판 생성 도중 Termux가 종료되면, CITY가 만들다 만 배포판임을 표시해 두었다가 다음 `install`에서 자동으로 지우고 다시 만듭니다. 이 표시가 없는 배포판(사용자가 직접 만든 것 등)은 절대 지우지 않습니다. `status`에서 이 상태를 확인할 수 있습니다.
- **에이전트 자체 업데이트 비활성화**: 지원되는 도구의 자동 업데이트 환경 변수(`DISABLE_AUTOUPDATER` 등)를 실행 시 설정해, 에이전트가 검증되지 않은 버전으로 스스로 바꾸지 않게 합니다. 버전 변경은 항상 `update`로 합니다.
- 로그인 정보와 설정은 Termux 홈(게스트 `/root`)에 저장되므로 에이전트 갱신과 무관하게 유지됩니다.

## 사용법

작업할 프로젝트를 Termux 홈(`$HOME`) 아래에 두고 실행합니다. Termux 홈은 게스트의 `/root`에 연결되며 현재 작업 폴더와 인자가 그대로 전달됩니다.

```bash
mkdir -p "$HOME/projects/demo"
cd "$HOME/projects/demo"

bash "$HOME/CITY/city.sh" codex login --device-auth
bash "$HOME/CITY/city.sh" codex

bash "$HOME/CITY/city.sh" opencode auth login
bash "$HOME/CITY/city.sh" opencode

bash "$HOME/CITY/city.sh" antigravity

bash "$HOME/CITY/city.sh" grok login --device-auth
bash "$HOME/CITY/city.sh" grok

bash "$HOME/CITY/city.sh" muse

bash "$HOME/CITY/city.sh" claude
bash "$HOME/CITY/city.sh" gemini
bash "$HOME/CITY/city.sh" aider
```

표의 다른 도구도 `bash "$HOME/CITY/city.sh" <CITY 실행 명령> [인자...]` 형식으로 같습니다. 버전 확인은 대부분 `--version`이며 Jules만 `jules version` 하위 명령을 씁니다.

`~/.bashrc`에 별칭을 등록해 두면 어디서든 `city codex`, `city opencode`, `city status` 형태로 짧게 실행할 수 있습니다.

```bash
alias city='bash "$HOME/CITY/city.sh"'
```

### 인증 및 Python 작업 환경

- 로그인할 때 출력되는 URL은 Android 브라우저에서 직접 열어 인증합니다. 호스트 Termux의 환경 변수는 PRoot 게스트로 자동 전달되지 않습니다.
- API 키 등 실행 시 필요한 환경 변수는 Termux의 `~/.config/city/env` 파일에 `KEY=value` 형식으로 적어 두면 모든 에이전트 실행 시 적용됩니다. 비밀 값이 들어가므로 권한을 제한하세요.

  ```bash
  mkdir -p ~/.config/city
  printf '%s\n' 'GEMINI_API_KEY=...' 'ANTHROPIC_API_KEY=...' >> ~/.config/city/env
  chmod 600 ~/.config/city/env
  ```
- Antigravity를 브라우저 없이 Gemini API 키로 사용하려면 `~/.gemini/antigravity-cli/settings.json`에 `"modelProvider": "gemini"`를 추가하고 `~/.config/city/env`에 `GEMINI_API_KEY`를 설정한 뒤 실행합니다.
- Grok Build는 `grok login --device-auth` 또는 `~/.config/city/env`의 `XAI_API_KEY`를 사용하며, Muse Code는 첫 실행의 `/login` 또는 `city.sh muse auth set --api-key-stdin`을 지원합니다.
- 설치 시 게스트 배포판 내부에 `python3`, `python3-pip`, `python3-venv`, `python3-cryptography`가 함께 준비됩니다. 에이전트 작업 시 Termux의 Python이 아니라 게스트 내부의 `/usr/bin/python3`나 게스트에서 만든 `.venv`를 사용하세요.

로컬 스크립트 검증은 `python3 tests/check.py`와 `shellcheck city.sh scripts/agents.sh scripts/environment.sh scripts/guest-install.sh`로 수행합니다.

## 지원 범위와 제외 기준

- **포함 기준**: 공식 배포처(npm, PyPI, 제조사 배포 서버)에서 linux arm64·x86_64(glibc) 빌드를 제공하고, 버전과 체크섬을 고정할 수 있으며, 2025년 말 이후에도 유지되는 CLI 코딩 에이전트.
- **Android 차단**: Android(PRoot 포함)를 의도적으로 막도록 설계된 에이전트는 지원하지 않습니다. 위 표의 도구는 배포물 정적 검사에서 Android 거부 코드가 발견되지 않았고, PRoot 안에서는 일반 Linux로 동작합니다(`--isolated`로 Android 경로를 숨기고 커널 정보도 PRoot 값으로 표시). 실기기에서 특정 도구가 Android를 감지해 거부하는 것이 확인되면 목록에서 제외합니다.
- **현재 제외한 도구**
  - Cursor CLI, Block Goose: 배포 서버(GitHub Releases 등)의 바이너리 체크섬을 이번 검증 환경에서 확인할 수 없어 보류했습니다.
  - Codebuff: 실행할 때마다 최신 바이너리를 내려받는 구조라 버전·체크섬 고정이 불가능합니다.
  - Kimi CLI: PyPI 패키지(`kimi-cli`)가 더 이상 유지되지 않는다고 스스로 안내하며, 후속 Kimi Code CLI는 전용 설치 스크립트로만 배포되어 체크섬을 확인할 수 없어 보류했습니다.
  - Letta Code: 필수 의존성(`node-pty`)에 linux용 사전 빌드가 없어 설치 때 C++ 컴파일러로 직접 빌드해야 하므로 제외했습니다.
  - iFlow CLI: 2026년 4월 이후 배포가 없어 제외했습니다.

## 유지보수

- 지원 도구와 고정 버전은 `scripts/agents.sh` 한 곳에만 있습니다. 버전을 올릴 때는 해당 항목만 바꾸면 됩니다.
- npm·PyPI 도구는 아래 명령이 레지스트리가 공개한 체크섬으로 그대로 붙여 넣을 줄을 출력합니다.

  ```bash
  python3 scripts/pin.py npm @google/gemini-cli          # 최신 버전
  python3 scripts/pin.py npm @google/gemini-cli 0.70.0   # 특정 버전
  python3 scripts/pin.py pypi aider-chat 0.86.2
  ```

- 아카이브·단일 바이너리 도구(Antigravity, Muse, Jules, Kiro)는 배포 URL 형식이 `scripts/guest-install.sh`에도 별도로 검증되므로, URL 구조가 바뀌면 두 파일을 함께 수정합니다.
- 변경 후 `python3 tests/check.py`로 모든 항목의 URL·체크섬 형식과 설치기 검증 통과를 확인합니다.

## 유의사항

- 설치기는 OCI 이미지, Node.js 아카이브, 각 CLI 배포물의 SHA-256 또는 SHA-512 체크섬을 검증하고 `--version` 기동 확인까지 통과한 뒤에만 활성 심볼릭 링크를 전환합니다. npm·PyPI 도구의 하위 의존성은 각 레지스트리의 무결성 검사를 따릅니다. 체크섬이 맞지 않거나 관리 표식(`CITY_ENV_V1`)이 없는 외부 배포판은 자동으로 덮어쓰지 않습니다.
- PRoot는 보안 격리용 가상 머신이 아닙니다. 실행된 에이전트는 공유된 Termux 홈 디렉터리에 접근할 수 있습니다.
- Android 공유 저장소(`/sdcard` 등) 경로는 지원하지 않으므로 작업 폴더는 항상 Termux 홈 내부에 두어야 합니다.
- 구 폴더나 컨테이너를 정리하기 전에는 반드시 `proot-distro backup`과 홈 디렉터리 백업을 먼저 수행하고, 인증 정보가 담긴 백업 아카이브가 공개 저장소에 올라가지 않도록 주의하세요.

## 라이선스

[MIT License](LICENSE)로 배포됩니다.
