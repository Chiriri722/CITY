# CITY

Termux에서 Ubuntu/Debian PRoot를 통해 CLI 코딩 에이전트를 설치하고 실행하는 Bash 도구입니다. 1차 지원 대상은 **Codex**와 **OpenCode**입니다.

## 설치

64비트 ARM 또는 x86_64 Termux, PRoot-Distro **5 이상**, 인터넷 연결이 필요합니다. Android 실기기에서의 동작 검증은 아직 남아 있습니다.

```bash
pkg update && pkg install git
git clone https://github.com/Chiriri722/CITY.git "$HOME/CITY"
cd "$HOME/CITY"
bash city.sh install all       # 또는 codex / opencode
```

로컬 작업물을 아직 원격에 push하지 않았다면 clone 대신 `CITY` 폴더 전체를 Termux의 `$HOME/CITY`로 복사합니다.

기본 배포판은 Ubuntu 24.04이며 전용 컨테이너 `city-ubuntu`를 생성합니다. Debian 12를 쓰려면 설치와 실행에 동일한 변수를 지정합니다.

```bash
export CITY_DISTRO=debian      # 선택 사항, 컨테이너 이름: city-debian
bash "$HOME/CITY/city.sh" install all
```

## 실행과 로그인

프로젝트를 Termux 홈 아래에 두고 실행합니다. 홈은 게스트의 `/root`에 연결되며 현재 작업 폴더와 인자를 전달합니다.

```bash
mkdir -p "$HOME/projects/demo"
cd "$HOME/projects/demo"
bash "$HOME/CITY/city.sh" codex login --device-auth
bash "$HOME/CITY/city.sh" codex
bash "$HOME/CITY/city.sh" opencode auth login
bash "$HOME/CITY/city.sh" opencode
```

로그인에 표시되는 URL은 Android 브라우저에서 직접 엽니다. Codex의 기기 코드 로그인은 계정/워크스페이스 설정에서 허용되어 있어야 합니다. 서비스 계정과 이용 요금은 각 공급자의 정책을 따릅니다. 호스트 환경 변수는 PRoot 게스트에 자동 전달되지 않습니다.

원하면 `~/.bashrc`에 `alias city='bash "$HOME/CITY/city.sh"'`를 추가해 `city codex`, `city opencode`로 실행할 수 있습니다.

## Python 작업 환경

초기 설치와 재설치 시 **게스트 배포판 내부**에 `python3`, `python-is-python3`, `python3-pip`, `python3-venv`, `python3-cryptography`를 설치합니다. 에이전트는 `/usr/bin/python3` 또는 `python`으로 작업할 수 있으며, 기본 `cryptography`는 배포판에서 관리하는 버전입니다. Termux의 Python이나 가상환경을 가져다 쓰지 않습니다.

프로젝트별 패키지 또는 다른 버전이 필요하면 OpenCode/Codex의 게스트 셸에서 다음처럼 별도 환경을 만드세요. 시스템 Python에 강제 pip 설치하는 옵션은 필요하지 않습니다.

```bash
python3 -m venv .venv
.venv/bin/python -m pip install cryptography
.venv/bin/python -c 'from cryptography.fernet import Fernet; print("cryptography ready")'
```

기존 설치도 수정본 전체를 반영한 뒤 `bash "$HOME/CITY2/city.sh" install opencode`를 다시 실행하면 Python 환경을 추가합니다. 폴더명이 `CITY`라면 경로를 맞춰 바꾸세요. 이후 에이전트에게 게스트 Python 또는 `.venv/bin/python`을 사용하도록 알려주면 됩니다.

## 설치 동작

- Node.js **22.23.2**, Codex **0.154.0**, OpenCode **1.18.31**을 고정 설치합니다. OCI 인덱스·플랫폼 manifest·rootfs의 SHA-256과 Node SHA-256, 최상위 npm 패키지 SHA-512를 확인합니다. npm의 추가 의존성 설치는 npm의 무결성 검증을 사용합니다.
- PRoot-Distro 5.8.0의 `image@sha256:…` 해석 문제를 피하기 위해 Python 표준 라이브러리로 검증한 rootfs를 로컬 아카이브로 설치합니다. 현재 고정한 Ubuntu·Debian의 단일 gzip 레이어만 허용하며 여러 레이어는 거부합니다. 다운로드 실패 시 설치를 시작하지 않고 임시 파일을 정리합니다.
- `/opt/city` 아래에 에이전트별 버전을 분리합니다. 다운로드·체크섬·`--version` 검증 후 해당 에이전트의 활성 링크만 전환합니다. 재실행 시 검증된 같은 버전을 재사용합니다.
- `install all`은 순차 설치입니다. 두 번째 설치가 실패해도 첫 번째 성공분은 유지되며 같은 명령으로 재시도할 수 있습니다. 배포판 생성 도중 중단되어 소유 표시가 없는 컨테이너는 자동으로 덮어쓰지 않습니다.
- 업데이트는 `city.sh`의 버전·공식 digest를 갱신한 뒤 다시 설치합니다. 이전 버전 디렉터리는 자동 삭제하지 않습니다.

PRoot는 보안 격리용 가상 머신이 아닙니다. 에이전트는 공유된 홈에 접근할 수 있으며 Android 커널에 따라 샌드박스·서브프로세스 기능이 제한될 수 있습니다. CITY는 에이전트의 승인·샌드박스 설정을 자동 해제하지 않습니다. 공유 저장소(`/sdcard` 등)는 지원하지 않습니다.

## 검증

```bash
python3 tests/check.py        # Linux: 네트워크 없는 CLI 검사
shellcheck city.sh scripts/guest-install.sh
bash -n city.sh
bash -n scripts/guest-install.sh
```

실제 다운로드·설치·재설치·실패 시 링크 보존 검사는 **폐기 가능한 Linux 컨테이너에서만** `CITY_INTEGRATION=1 python3 tests/check.py`로 실행합니다. `/opt/city`와 테스트용 `/data/data/com.termux/files/usr`를 쓰며 apt/npm 다운로드를 수행합니다. Android 경계만 모의 처리하므로 실기기 검증을 대신하지 않습니다.

2026-09-17 수정 후 Linux x86_64에서 전체 12개 검사, 두 CLI의 실제 `--version`, ShellCheck와 Bash 구문 검사를 통과했습니다. 실제 PRoot-Distro 5.8.0으로 Ubuntu 24.04·Debian 12의 ARM64/x64 아카이브 설치와 x64 게스트 실행도 확인했습니다. ARM64 실행과 Android 실기기 재검증은 별도입니다.

Python 환경 보강은 Debian 12·Ubuntu 24.04의 x86_64 컨테이너에서 기본 `cryptography` 암복호화, venv 생성, pip wheel 설치 후 암복호화를 검증했습니다. 회귀 검사에도 Python 환경 확인을 추가했습니다.

실제 PRoot-Distro 검사도 실행하려면 폐기 가능한 Linux 컨테이너에 `proot`를 설치하고 공식 v5.8.0 소스를 준비한 뒤 `CITY_PROOT_SOURCE=/path/to/proot-distro python3 tests/check.py`를 실행합니다. Ubuntu·Debian의 ARM64/x64 아카이브를 다운로드·설치하고 x64 게스트 실행을 확인합니다.

## 첫 설치의 `Image not found` 오류

PRoot-Distro 5.8.0의 [주소 파서](https://github.com/termux/proot-distro/blob/v5.8.0/proot_distro/helpers/docker/refs.py)는 기존 `ubuntu@sha256:…` 인자를 `library/ubuntu@sha256` 저장소로 잘못 해석합니다. CITY의 첫 버전에 있던 호환성 문제입니다. 수정된 CITY 파일 전체를 기기에 반영한 후 `bash "$HOME/CITY/city.sh" install all`을 다시 실행하세요. 이번 로그처럼 이미지 조회 단계에서 실패한 경우 PRoot-Distro가 실패한 컨테이너를 정리하므로 별도 삭제는 필요하지 않습니다.

전원이 끊기는 등의 이유로 `Refusing unmanaged distro`가 나오면 기존 폴더를 자동 삭제하지 않습니다. 해당 메시지와 `proot-distro list` 결과를 확인한 뒤 복구해야 합니다. 미러 경고나 업그레이드 가능한 패키지 개수는 이번 오류의 원인이 아닙니다.

Termux에서 남은 확인: `install all`, 두 CLI의 `--version`, 로그인, 실제 프로젝트 작업, Ctrl+C 종료. 개발 시 새 에이전트는 `city.sh`의 패키지 정보·명령 선택과 내부 설치기의 허용 목록에 추가합니다.

기존 [FreeBuff Termux](https://github.com/Chiriri722/Freebuff_In_Termux)의 PRoot 설치·홈 매핑 방식을 범용화했습니다. MIT 라이선스입니다.

참고: [Codex 설치](https://github.com/openai/codex), [Codex 로그인](https://developers.openai.com/codex/auth/), [OpenCode 설치](https://opencode.ai/docs/), [PRoot-Distro](https://github.com/termux/proot-distro), [Node 체크섬](https://nodejs.org/dist/v22.23.2/SHASUMS256.txt).
