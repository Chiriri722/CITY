# CITY

CITY는 Android Termux에서 Ubuntu 또는 Debian PRoot 컨테이너를 구성해 주요 CLI 코딩 에이전트를 설치하고 실행하는 Bash 도구입니다. 하나의 PRoot 배포판(`city-ubuntu` 또는 `city-debian`) 안에 고정된 버전의 Node.js와 각 에이전트를 격리된 경로(`/opt/city`)로 설치하고, Termux 홈 디렉터리를 공유해 로컬 프로젝트를 바로 편집할 수 있게 연결합니다.

| 지원 도구 | CITY 실행 명령 | 게스트 실행 파일 | 고정 설치 버전 |
| --- | --- | --- | --- |
| OpenAI Codex | `codex` | `codex` | 0.154.0 |
| OpenCode | `opencode` | `opencode` | 1.18.31 |
| Google Antigravity CLI | `antigravity` | `agy` | 1.3.1 |
| xAI Grok Build | `grok` | `grok` | 1.0.46 |
| Meta Muse Code | `muse` | `muse` | 1.4.3-R5018.1 |

Antigravity는 터미널용 CLI만 설치하며 데스크톱 IDE는 포함하지 않습니다.

## 설치 및 업데이트

64비트 ARM 또는 x86_64 환경의 Termux, PRoot-Distro 5 이상, 인터넷 연결이 필요합니다.

### 새 기기에 처음 설치

```bash
pkg update && pkg install git
git clone https://github.com/Chiriri722/CITY.git "$HOME/CITY"
cd "$HOME/CITY"
bash city.sh install all
bash city.sh status
```

특정 도구 하나만 설치하려면 `bash city.sh install antigravity`처럼 대상 이름(`codex`, `opencode`, `antigravity`, `grok`, `muse`)을 지정합니다. 기본 배포판은 Ubuntu 24.04(`city-ubuntu`)이며, Debian 12(`city-debian`)를 쓰려면 설치와 실행 시 `export CITY_DISTRO=debian`을 지정합니다.

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

`update`는 이미 설치된 에이전트만 현재 CITY 체크아웃에 고정된 버전으로 갱신합니다. 설치되지 않은 에이전트를 추가할 때는 `bash "$CITY_DIR/city.sh" install muse`처럼 `install` 명령을 사용합니다.

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
```

`~/.bashrc`에 별칭을 등록해 두면 어디서든 `city codex`, `city opencode`, `city status` 형태로 짧게 실행할 수 있습니다.

```bash
alias city='bash "$HOME/CITY/city.sh"'
```

### 인증 및 Python 작업 환경

- 로그인할 때 출력되는 URL은 Android 브라우저에서 직접 열어 인증합니다. 호스트 Termux의 환경 변수는 PRoot 게스트로 자동 전달되지 않습니다.
- Antigravity를 브라우저 없이 Gemini API 키로 사용하려면 `~/.gemini/antigravity-cli/settings.json`에 `"modelProvider": "gemini"`를 추가하고 게스트 셸 안에서 `GEMINI_API_KEY`를 설정한 뒤 `agy`를 실행합니다.
- Grok Build는 `grok login --device-auth` 또는 게스트의 `XAI_API_KEY`를 사용하며, Muse Code는 첫 실행의 `/login` 또는 `city.sh muse auth set --api-key-stdin`을 지원합니다.
- 설치 시 게스트 배포판 내부에 `python3`, `python3-pip`, `python3-venv`, `python3-cryptography`가 함께 준비됩니다. 에이전트 작업 시 Termux의 Python이 아니라 게스트 내부의 `/usr/bin/python3`나 게스트에서 만든 `.venv`를 사용하세요.

로컬 스크립트 검증은 `python3 tests/check.py`와 `shellcheck city.sh scripts/environment.sh scripts/guest-install.sh`로 수행합니다.

## 유의사항

- 설치기는 OCI 이미지, Node.js 아카이브, 각 CLI 배포물의 SHA-256 또는 SHA-512 체크섬을 검증한 뒤에만 활성 심볼릭 링크를 전환합니다. 체크섬이 맞지 않거나 관리 표식(`CITY_ENV_V1`)이 없는 외부 배포판은 자동으로 덮어쓰지 않습니다.
- PRoot는 보안 격리용 가상 머신이 아닙니다. 실행된 에이전트는 공유된 Termux 홈 디렉터리에 접근할 수 있습니다.
- Android 공유 저장소(`/sdcard` 등) 경로는 지원하지 않으므로 작업 폴더는 항상 Termux 홈 내부에 두어야 합니다.
- 구 폴더나 컨테이너를 정리하기 전에는 반드시 `proot-distro backup`과 홈 디렉터리 백업을 먼저 수행하고, 인증 정보가 담긴 백업 아카이브가 공개 저장소에 올라가지 않도록 주의하세요.

## 라이선스

[MIT License](LICENSE)로 배포됩니다.
