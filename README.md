# CITY

Termux에서 Ubuntu/Debian PRoot를 통해 CLI 코딩 에이전트를 설치하고 실행하는 Bash 도구입니다. **Codex, OpenCode, Antigravity CLI, Grok Build, Muse Code**를 지원합니다.

| 제품 | CITY 명령 | 게스트 실행 파일 | 설치 버전 |
| --- | --- | --- | --- |
| Codex | `codex` | `codex` | 0.154.0 |
| OpenCode | `opencode` | `opencode` | 1.18.31 |
| Google Antigravity CLI | `antigravity` | `agy` | 1.3.1 |
| xAI Grok Build | `grok` | `grok` | 1.0.46 |
| Meta Muse Code | `muse` | `muse` | 1.4.3-R5018.1 |

Antigravity는 터미널 CLI를 설치합니다. 데스크톱 IDE 설치는 포함하지 않습니다.

## 새 기기에 처음 설치

64비트 ARM 또는 x86_64 Termux, PRoot-Distro **5 이상**, 인터넷 연결이 필요합니다. Android 실기기에서의 동작 검증은 아직 남아 있습니다.

**이미 CITY를 설치한 기기는 아래의 「기존 기기 업데이트」로 이동하세요.** 릴리스마다 CITY2·CITY3 폴더나 새 distro를 만들 필요가 없습니다. CITY 폴더는 설치기·런처이고, 실제 실행 환경은 기본적으로 `city-ubuntu` 하나를 계속 사용합니다.

```bash
pkg update && pkg install git
git clone https://github.com/Chiriri722/CITY.git "$HOME/CITY"
cd "$HOME/CITY"
bash city.sh install all       # 다섯 CLI 모두 설치
# 하나만 설치: bash city.sh install antigravity   # 또는 codex / opencode / grok / muse
bash city.sh status
```

로컬 작업물을 아직 원격에 push하지 않았다면 clone 대신 `CITY` 폴더 전체를 Termux의 `$HOME/CITY`로 복사합니다.

기본 배포판은 Ubuntu 24.04이며 전용 컨테이너 `city-ubuntu`를 생성합니다. Debian 12를 쓰려면 설치와 실행에 동일한 변수를 지정합니다.

```bash
export CITY_DISTRO=debian      # 선택 사항, 컨테이너 이름: city-debian
bash "$HOME/CITY/city.sh" install all
```

## 기존 기기 업데이트

기존에 사용하던 폴더 하나를 계속 사용합니다. 다음 예제는 **CITY3 + Ubuntu**이며, CITY 또는 CITY2를 쓰면 첫 줄의 경로만 바꾸세요. Debian 사용자는 `CITY_DISTRO=debian`으로 바꿉니다.

먼저 체크아웃의 수정사항을 확인합니다.

```bash
CITY_DIR="$HOME/CITY3"
export CITY_DISTRO=ubuntu
git -C "$CITY_DIR" status --short
```

출력이 있으면 해당 로컬 작업을 보존하고 차이를 확인한 뒤 진행하세요. 강제 `reset`이나 폴더 삭제로 해결하지 않습니다. 최신 코드가 GitHub에 반영되어 있다면 **같은 Termux 셸에서** 이어서 실행합니다.

```bash
git -C "$CITY_DIR" pull --ff-only &&
bash "$CITY_DIR/city.sh" status &&
bash "$CITY_DIR/city.sh" update &&
bash "$CITY_DIR/city.sh" status
```

`pull`이 실패하면 뒤의 단계로 넘어가지 말고 메시지를 확인하세요. `city.sh`만 복사하면 함께 쓰는 `scripts/`가 누락될 수 있으므로 수동 반영 시에도 체크아웃 전체를 갱신합니다.

| 명령 | 동작 |
| --- | --- |
| `status` | 체크아웃 경로/커밋, 대상 distro, 관리 상태, 에이전트의 기록된 활성 버전과 CITY 지정 버전 조회 |
| `update` 또는 `update all` | **이미 설치된** 에이전트만 같은 distro에서 갱신 |
| `update opencode` | 설치된 OpenCode만 갱신 |
| `install muse` | 같은 distro에 Muse를 새로 추가하거나 다시 설치 |
| `install all` | 같은 distro에 지원되는 다섯 CLI 모두 설치 |

`update`는 없는 distro를 생성하지 않으며, 명시한 에이전트가 미설치 상태면 `install`을 안내합니다. 설치된 에이전트가 하나도 없으면 변경 없이 종료합니다. 갱신 기준은 현재 체크아웃에 고정된 버전이며 공급자 사이트의 최신 버전을 자동 탐색하는 명령은 아닙니다. 실제 모델 로그인이나 설정 이전도 자동 실행하지 않습니다.

새 지원 대상만 추가하고 바로 실행하는 예:

```bash
bash "$CITY_DIR/city.sh" install muse
bash "$CITY_DIR/city.sh" muse --version
bash "$CITY_DIR/city.sh" muse
```

### 상태 출력 읽기

- `missing`: 선택한 CITY distro가 없습니다. 기존에 Debian을 썼는지 먼저 확인하고, 새 설치가 필요한 경우에만 `install`을 사용합니다.
- `legacy`: 이전 형식의 CITY 관리 표식입니다. OS와 아키텍처가 호환되며, 다음 `install`/실제 업데이트 시 생성 당시 이미지 기록을 보존해 새 형식으로 이전합니다.
- `managed`: 관리 표식과 OS/아키텍처가 현재 CITY와 호환됩니다.
- `unmanaged` / `incompatible`: 표식 누락·손상, 경로 이상 또는 OS/아키텍처 불일치입니다. 자동 재설치하지 않습니다. 출력과 `proot-distro list` 결과를 확인하세요.
- 에이전트 `absent`는 미설치, `invalid`는 링크·설치 기록·실행 파일에 문제가 있는 상태입니다. `update all`은 이런 비정상 설치를 건너뛰지 않고 중단합니다.

`status`는 패키지 설치, PRoot 로그인, 에이전트 실행, 관리 표식 이전을 하지 않습니다. 표시 버전은 설치 기록이며 CLI 자체 업데이트까지 검사하는 값은 아닙니다. 실제 바이너리 버전은 `bash "$CITY_DIR/city.sh" opencode --version`처럼 확인합니다. 정상 조회와 미설치 환경은 종료 코드 0, 비정상 환경/에이전트는 2입니다.

관리 표식을 이전한 이후에는 최신 CITY 체크아웃을 계속 사용하세요. 예전 설치기는 새 표식을 이해하지 못해 설치를 거부할 수 있습니다.

### 폴더와 별칭 통일

CITY·CITY2·CITY3가 모두 남아 있어도 같은 Termux에서 같은 `CITY_DISTRO`를 사용하면 같은 distro를 가리킵니다. 유지할 폴더를 정한 뒤 `~/.bashrc`의 기존 별칭 경로도 맞춥니다. 예를 들어 CITY3 + Ubuntu를 유지한다면 다음 별칭을 사용합니다.

```bash
alias city='CITY_DISTRO=ubuntu bash "$HOME/CITY3/city.sh"'
```

저장 후 새 Termux 셸을 열거나 `source ~/.bashrc`를 실행하면 `city status`, `city update`, `city opencode`로 사용할 수 있습니다. 기존 `opencode`/`codex` 별칭이 CITY2 등 다른 폴더를 가리키는지도 확인하세요. 이름을 CITY로 맞추기 위해 폴더를 옮길 필요는 없습니다.

### 구 폴더·배포판 정리

`proot-distro list`에 `city-ubuntu`, `ubuntu`가 보이면 실제 distro는 두 개입니다. 현재 CITY의 Ubuntu 대상은 `city-ubuntu`이고 별도의 `ubuntu`는 다른 도구가 쓰는 환경일 수 있습니다. CITY는 그것을 자동 인수하거나 삭제하지 않습니다.

구 폴더/환경을 정리하기 전에는 실행 중인 에이전트를 종료하고 작업물·설정부터 보존합니다. 아래는 **백업 예시**이며 해당 distro가 실제 존재하는지 먼저 확인하세요. 백업에는 인증 정보가 포함될 수 있으므로 공개 저장소에 올리지 않습니다.

```bash
proot-distro list
mkdir -p "$HOME/city-backups"
city_backup_stamp=$(date +%Y%m%d-%H%M%S)
proot-distro backup city-ubuntu --output "$HOME/city-backups/city-ubuntu-$city_backup_stamp.tar.gz"
# 공유된 Termux 홈은 컨테이너 백업과 별도로 보존합니다.
tar --exclude='./city-backups' -czf "$HOME/city-backups/home-$city_backup_stamp.tar.gz" -C "$HOME" .
```

별도 `ubuntu`도 정리할 예정이면 그 환경 역시 따로 백업합니다. 공유 저장소를 가리키는 심볼릭 링크의 대상 파일은 위 홈 백업에 포함되지 않습니다. 백업 성공과 내용 확인, 유지할 환경의 로그인·실제 프로젝트 작업 확인을 마친 후에만 구 폴더를 정리하세요. 구 폴더 안의 프로젝트나 `.venv`도 먼저 확인합니다. 경로/OS가 바뀐 가상환경은 의존성 기록으로 재생성하는 편이 안전합니다.

실제 distro 삭제는 사용하지 않는다는 확인 후 별도로 수행합니다. `reset`은 업데이트 명령이 아니며, `restore`도 같은 이름의 운영 환경을 덮어쓸 수 있습니다. [PRoot-Distro 백업·복원 문서](https://github.com/termux/proot-distro/blob/v5.8.0/README.md#backup--archive-a-container)를 확인하세요. CITY에는 자동 삭제/정리 명령을 넣지 않았습니다.

## 실행과 로그인

프로젝트를 Termux 홈 아래에 두고 실행합니다. 홈은 게스트의 `/root`에 연결되며 현재 작업 폴더와 인자를 전달합니다.

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

로그인에 표시되는 URL은 Android 브라우저에서 직접 엽니다. Codex의 기기 코드 로그인은 계정/워크스페이스 설정에서 허용되어 있어야 합니다. 서비스 계정과 이용 요금은 각 공급자의 정책을 따릅니다. 호스트 환경 변수는 PRoot 게스트에 자동 전달되지 않습니다.

원하면 `~/.bashrc`에 `alias city='bash "$HOME/CITY/city.sh"'`를 추가해 `city codex`, `city opencode`, `city antigravity`, `city grok`, `city muse`로 실행할 수 있습니다. 폴더명이 `CITY2`라면 모든 예제의 경로도 `CITY2`로 바꾸세요. 작업 폴더를 CITY로 고정할 필요는 없습니다.

### 2차 지원 CLI의 인증

- [Antigravity 공식 인증 문서](https://antigravity.google/docs/cli/install): 로컬 로그인은 브라우저와 Linux Secret Service/D-Bus를 사용하며 SSH 환경에서는 수동 URL/코드 흐름을 제공합니다. Termux PRoot에서 해당 로그인 흐름은 실기기 확인이 필요합니다. 브라우저 없는 환경에는 아래 Gemini API 키 방식을 사용할 수 있습니다.
- [Grok Build 공식 인증 문서](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/02-authentication.md): `grok login --device-auth`의 URL/코드를 Android 브라우저에서 사용합니다. 게스트의 `XAI_API_KEY`도 지원하며 저장된 로그인 세션이 우선합니다.
- [Muse Code 공식 인증 문서](https://dev.meta.ai/docs/muse-code/auth): 첫 실행 또는 `/login`에서 브라우저/키 인증을 선택합니다. 키를 저장하려면 `bash "$HOME/CITY/city.sh" muse auth set --api-key-stdin`에 표준 입력으로 전달하세요. 게스트의 `META_API_KEY`는 저장된 인증보다 우선합니다.

Antigravity의 API 키 모드는 `~/.gemini/antigravity-cli/settings.json`에 `"modelProvider": "gemini"` 설정과 `GEMINI_API_KEY`가 **둘 다** 필요합니다. 기존 JSON의 다른 설정은 유지해 해당 필드를 추가하세요. 공유 홈이므로 이 파일은 Termux 홈에서도 편집할 수 있습니다. 키를 셸 기록에 남기지 않고 같은 게스트 세션에서 실행하는 예:

```bash
proot-distro login --user root --isolated --shared-home "city-${CITY_DISTRO:-ubuntu}" -- /bin/bash --noprofile --norc
# 아래부터는 게스트 셸입니다.
export PATH="/opt/city/antigravity/bin:/opt/city/node-v22.23.2/bin:$PATH"
cd /root/projects/demo
read -rsp 'GEMINI_API_KEY: ' GEMINI_API_KEY; printf '\n'
export GEMINI_API_KEY
agy
exit
```

키는 위 게스트 세션에만 적용됩니다. 호스트에서 `export`하거나 `.env`에 넣는 것으로 Antigravity 인증이 설정되지는 않습니다. CITY는 사용자의 로그인·API 키·승인 설정을 자동 변경하지 않습니다.

## Python 작업 환경

초기 설치와 재설치 시 **게스트 배포판 내부**에 `python3`, `python-is-python3`, `python3-pip`, `python3-venv`, `python3-cryptography`를 설치합니다. 에이전트는 `/usr/bin/python3` 또는 `python`으로 작업할 수 있으며, 기본 `cryptography`는 배포판에서 관리하는 버전입니다. Termux의 Python이나 가상환경을 가져다 쓰지 않습니다.

프로젝트별 패키지 또는 다른 버전이 필요하면 OpenCode/Codex의 게스트 셸에서 다음처럼 별도 환경을 만드세요. 시스템 Python에 강제 pip 설치하는 옵션은 필요하지 않습니다.

```bash
python3 -m venv .venv
.venv/bin/python -m pip install cryptography
.venv/bin/python -c 'from cryptography.fernet import Fernet; print("cryptography ready")'
```

기존 설치도 수정본 전체를 반영한 뒤 `bash "$HOME/CITY3/city.sh" update opencode`를 실행하면 Python 환경을 보강합니다. 사용하는 체크아웃 폴더명에 맞춰 경로를 바꾸세요. 이후 에이전트에게 게스트 Python 또는 `.venv/bin/python`을 사용하도록 알려주면 됩니다.

## 설치 동작

- Node.js **22.23.2**와 위 표의 CLI 버전을 설치합니다. OCI 인덱스·플랫폼 manifest·rootfs의 SHA-256과 Node SHA-256, 최상위 npm 패키지 SHA-512를 확인합니다. Codex·OpenCode·Grok은 공식 npm 패키지를 사용하며 추가 의존성은 npm의 무결성 검증을 사용합니다.
- Antigravity는 공식 Linux ARM64/x64 tarball과 SHA-512, Muse는 공식 Linux ARM64/x64 단일 바이너리와 SHA-256을 사용합니다. 배포 스크립트의 셸 프로필 수정 단계는 실행하지 않습니다. 두 CLI도 기존 에이전트와 같은 임시 설치·실행 확인·활성 링크 전환 절차를 거칩니다.
- PRoot-Distro 5.8.0의 `image@sha256:…` 해석 문제를 피하기 위해 Python 표준 라이브러리로 검증한 rootfs를 로컬 아카이브로 설치합니다. 현재 고정한 Ubuntu·Debian의 단일 gzip 레이어만 허용하며 여러 레이어는 거부합니다. 다운로드 실패 시 설치를 시작하지 않고 임시 파일을 정리합니다.
- `/opt/city` 아래에 에이전트별 버전을 분리합니다. 다운로드·체크섬·`--version` 검증 후 해당 에이전트의 활성 링크만 전환합니다. 재실행 시 설치 기록이 일치하고 기동 검사를 통과한 같은 버전을 재사용합니다.
- `install all`은 Codex → OpenCode → Antigravity → Grok → Muse 순서입니다. 중간에 실패해도 앞선 성공분은 유지되며 같은 명령으로 재시도할 수 있습니다. 배포판 생성 도중 중단되어 소유 표시가 없는 컨테이너는 자동으로 덮어쓰지 않습니다.
- CITY 유지보수자가 `city.sh`의 버전·공식 URL·digest를 갱신하고 내부 설치기의 허용 URL과 맞추면, 사용자는 체크아웃을 갱신한 뒤 `update`로 반영합니다. 이전 버전 디렉터리는 자동 삭제하지 않습니다. 이는 CITY가 설치하는 배포물의 고정이며, CLI 자체의 업데이트 기능을 잠그는 설정은 아닙니다.
- 기존 distro는 새 기본 이미지로 덮어쓰지 않습니다. `CITY_ENV_V1` 관리 표식에 OS ID/릴리스, 아키텍처, 생성 당시 이미지 출처를 기록합니다. 호환 범위는 현재 Ubuntu 24.04 / Debian 12이며, OS 메이저 업그레이드는 별도 이전 작업입니다.
- 알려진 이전 CITY 이미지의 표식만 호환성 확인 후 이전합니다. 출처를 새 이미지 digest로 바꾸지 않습니다. OS 정보는 데이터로 읽고 게스트 파일을 호스트 셸에서 실행하지 않습니다.
- `install`/`update`는 같은 설치 잠금을 사용합니다. 환경/설치 대상 사전 확인 후 변경하며, 게스트 시스템 패키지도 보강하므로 전체 업데이트가 단일 트랜잭션인 것은 아닙니다.

2차 배포물 출처(2026-10-08 확인): [Antigravity 공식 설치 스크립트](https://antigravity.google/cli/install.sh)와 [ARM64 manifest](https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_arm64.json) / [x64 manifest](https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_amd64.json), [Grok 공식 npm 배포 정보](https://registry.npmjs.org/@xai-official/grok/1.0.46), [Muse 공식 설치 스크립트](https://dev.meta.ai/install.sh)와 [stable 채널](https://api.meta.ai/muse-code/channels/muse-stable). 채널의 최신 버전이 달라져도 CITY는 코드에 기록된 URL과 체크섬으로 설치합니다.

PRoot는 보안 격리용 가상 머신이 아닙니다. 에이전트는 공유된 홈에 접근할 수 있으며 Android 커널에 따라 샌드박스·서브프로세스 기능이 제한될 수 있습니다. CITY는 에이전트의 승인·샌드박스 설정을 자동 해제하지 않습니다. 공유 저장소(`/sdcard` 등)는 지원하지 않습니다.

## 검증

```bash
python3 tests/check.py        # Linux: 네트워크 없는 CLI 검사
shellcheck city.sh scripts/environment.sh scripts/guest-install.sh
bash -n city.sh
bash -n scripts/environment.sh
bash -n scripts/guest-install.sh
```

실제 다운로드·설치·반복 업데이트·실패 시 링크 보존 검사는 **폐기 가능한 Linux 컨테이너에서만** 실행합니다. Python 3, `ca-certificates`, 최신 [Termux PRoot](https://github.com/termux/proot)를 준비한 뒤 `CITY_INTEGRATION=1 python3 tests/check.py`로 실행합니다. Debian 환경은 `CITY_DISTRO=debian`도 지정합니다. 테스트별 `/data/data/com.termux.citycheck*/files/usr` 아래에 실제 rootfs를 만들고 PRoot 안에서 apt/npm 설치를 수행합니다. Android/PRoot-Distro 명령 연결 부분은 테스트 어댑터를 사용하므로 실기기 검증을 대신하지 않습니다.

Linux 배포판의 오래된 PRoot 5.1.0은 이 검사에서 존재하는 npm 파일도 찾지 못했습니다. 테스트 컨테이너에서는 Termux PRoot 소스 `a179d3e8a4e045aaa1fb8cc3284f23509d96d353`을 빌드해 사용합니다. Termux 기기에는 별도 빌드가 필요하지 않습니다.

2026-10-10 환경 재사용 변경 검증:

- 네트워크 없는 검사 20개 통과(선택적 통합 검사 2개는 기본 실행에서 생략), ShellCheck·Bash 구문 검사 통과.
- Ubuntu 24.04·Debian 12 x64 실제 rootfs + Termux PRoot: `install all → update → update all`, 다섯 CLI의 CITY 실행 경로를 통한 `--version`, 기본 Python/venv/cryptography, 무결성 오류 시 활성 링크 보존 검사 통과. 각 실행에서 distro 생성은 한 번뿐이며 공유 홈의 프로젝트 파일을 보존했습니다.
- 레거시 표식 이전, Ubuntu/Debian 및 ARM64/x64 메타데이터, 기본 이미지 변경 시 원래 출처 보존, CITY/CITY2/CITY3의 동일 환경 선택, 잘못된 OS·아키텍처·표식·링크 거부는 네트워크 없는 fixture 검사로 확인했습니다. 이번 ARM64 확인은 실제 ARM64 실행 검사가 아닙니다.

2026-09-17 수정 후 Linux x86_64에서 전체 12개 검사, 두 CLI의 실제 `--version`, ShellCheck와 Bash 구문 검사를 통과했습니다. 실제 PRoot-Distro 5.8.0으로 Ubuntu 24.04·Debian 12의 ARM64/x64 아카이브 설치와 x64 게스트 실행도 확인했습니다. ARM64 실행과 Android 실기기 재검증은 별도입니다.

Python 환경 보강은 Debian 12·Ubuntu 24.04의 x86_64 컨테이너에서 기본 `cryptography` 암복호화, venv 생성, pip wheel 설치 후 암복호화를 검증했습니다. 회귀 검사에도 Python 환경 확인을 추가했습니다.

2026-10-08 2차 지원 검증:

- Debian 12 x64: 14개 중 13개 검사 통과, 기존 실제 PRoot-Distro 이미지 검사는 환경 변수 미설정으로 1개 생략. ShellCheck 통과.
- Debian 12·Ubuntu 24.04 x64: 다섯 CLI의 실제 설치·재설치와 **CITY 실행 경로를 통한** `--version`, 기존 Python/venv/cryptography 검사 통과.
- Antigravity·Grok·Muse ARM64: 코드에 지정한 공식 배포물의 체크섬 및 ELF 아키텍처 확인, QEMU에서 각각 `--version` 통과. Android 실기기나 ARM64 전체 설치 검증과는 구분합니다.
- Antigravity·Grok·Muse x64: Debian의 실제 PRoot 5.1.0 안에서도 `--version` 통과. Termux의 PRoot-Distro 전체 실행 환경을 재현한 검사는 아닙니다.
- 네트워크 없는 회귀 검사: 새 명령 전달, ARM64/x64 네이티브 설치 경로, 재설치·업그레이드, 체크섬 오류·기동 실패 시 기존 활성 링크 보존, 임시 파일 정리 확인.

인증된 모델 요청·Android 터미널 UI·실제 프로젝트 도구 실행은 기기에서 확인해야 합니다. 설치 검증 과정에서 로그인하거나 유료 모델 요청을 보내지는 않습니다.

실제 PRoot-Distro 검사도 실행하려면 폐기 가능한 Linux 컨테이너에 `proot`를 설치하고 공식 v5.8.0 소스를 준비한 뒤 `CITY_PROOT_SOURCE=/path/to/proot-distro python3 tests/check.py`를 실행합니다. Ubuntu·Debian의 ARM64/x64 아카이브를 다운로드·설치하고 x64 게스트 실행을 확인합니다.

## 첫 설치의 `Image not found` 오류

PRoot-Distro 5.8.0의 [주소 파서](https://github.com/termux/proot-distro/blob/v5.8.0/proot_distro/helpers/docker/refs.py)는 기존 `ubuntu@sha256:…` 인자를 `library/ubuntu@sha256` 저장소로 잘못 해석합니다. CITY의 첫 버전에 있던 호환성 문제입니다. 수정된 CITY 파일 전체를 기기에 반영한 후 `bash "$HOME/CITY/city.sh" install all`을 다시 실행하세요. 이번 로그처럼 이미지 조회 단계에서 실패한 경우 PRoot-Distro가 실패한 컨테이너를 정리하므로 별도 삭제는 필요하지 않습니다.

전원이 끊기는 등의 이유로 `unmanaged` 또는 `incompatible`이 나오면 기존 폴더를 자동 삭제하지 않습니다. 이전 버전의 `Refusing unmanaged distro`도 같은 점검 대상입니다. `city.sh status`와 `proot-distro list` 결과를 확인한 뒤 복구해야 합니다. 미러 경고나 업그레이드 가능한 패키지 개수는 이번 오류의 원인이 아닙니다.

Termux에서 남은 확인: 첫 설치 또는 기존 환경의 `status → update → status`, distro 수 유지, 사용하는 CLI의 `--version`, 로그인 유지, 실제 프로젝트 작업, Ctrl+C 종료. 개발 시 새 에이전트는 `city.sh`의 패키지 정보·명령 선택·목록과 내부 설치기의 허용 목록에 추가합니다.

기존 [FreeBuff Termux](https://github.com/Chiriri722/Freebuff_In_Termux)의 PRoot 설치·홈 매핑 방식을 범용화했습니다. MIT 라이선스입니다.

참고: [Codex 설치](https://github.com/openai/codex), [Codex 로그인](https://developers.openai.com/codex/auth/), [OpenCode 설치](https://opencode.ai/docs/), [PRoot-Distro](https://github.com/termux/proot-distro), [Node 체크섬](https://nodejs.org/dist/v22.23.2/SHASUMS256.txt).
