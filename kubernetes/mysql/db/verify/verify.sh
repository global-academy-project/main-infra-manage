#!/usr/bin/env bash
# 검증: 실제 배포와 같은 조건으로
#   1) MySQL 8.4 최초 기동 → infra/db/init/10-agent-kb.sh 자동 실행 (agent_kb DB + kb_* 계정)
#   2) 업무 DB: 앱 계정(app)으로 V1~V9, R__ 적용  (Spring Flyway와 같은 순서)
#   3) 지식 DB: kb_owner로 main-ai-model/db/migration 적용 (agent-kb-migrate와 같은 순서)
#   4) 정상 흐름 → 위반 케이스(데이터 제약 + 계정 권한)
# 사용: main-infra-manage 폴더에서  bash db/verify/verify.sh   (Docker 필요)
#   mainProject/ 아래에 main-infra-manage, main-server, main-ai-model 이 나란히 있다고 가정한다.
#   위치가 다르면: SERVER_DIR=/c/.../main-server AI_MODEL_DIR=/c/.../main-ai-model bash db/verify/verify.sh
#   Windows: PowerShell이 아니라 Git Bash에서 실행. Docker Desktop이 켜져 있어야 한다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# main-infra-manage 저장소 루트 = 이 스크립트의 두 단계 위 (db/verify)
INFRA="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT="$(cd "$INFRA/.." && pwd)"

# 옆 저장소 찾기: 환경 변수 > 표준 이름 > 옆 폴더 중 표시 파일이 있는 곳 (main-server-main 같은 이름도 찾음)
find_sibling() {  # $1 = 표준 폴더 이름, $2 = 그 저장소 안에 있어야 하는 파일
  local c
  for c in "$PROJECT/$1" "$PROJECT"/*; do
    if [ -f "$c/$2" ]; then (cd "$c" && pwd); return 0; fi
  done
  return 1
}
SERVER_DIR="${SERVER_DIR:-$(find_sibling main-server src/main/resources/db/migration/V1__baseline_ocr.sql || true)}"
AI_MODEL_DIR="${AI_MODEL_DIR:-$(find_sibling main-ai-model db/migration/V1__kb_init.sql || true)}"
MIG="$SERVER_DIR/src/main/resources/db/migration"
KB_MIG="$AI_MODEL_DIR/db/migration"
if [ -z "$SERVER_DIR" ] || [ ! -f "$MIG/V1__baseline_ocr.sql" ]; then
  echo "업무 DB 마이그레이션(main-server/src/main/resources/db/migration)을 찾지 못했습니다." >&2
  echo "  main-server를 main-infra-manage 옆에 두거나 SERVER_DIR=<경로> 를 붙여 실행하세요." >&2; exit 1
fi
if [ -z "$AI_MODEL_DIR" ] || [ ! -f "$KB_MIG/V1__kb_init.sql" ]; then
  echo "지식 DB 마이그레이션(main-ai-model/db/migration)을 찾지 못했습니다." >&2
  echo "  main-ai-model을 main-infra-manage 옆에 두거나 AI_MODEL_DIR=<경로> 를 붙여 실행하세요." >&2; exit 1
fi

# Windows Git Bash 대응
#  - Git Bash는 "/docker-entrypoint-initdb.d" 같은 리눅스 경로를 C:/Program Files/Git/... 로 바꿔 버린다 → 변환 끔
#  - 마운트할 내 폴더 경로는 Docker Desktop이 알아듣는 C:/... 형식으로
if command -v cygpath >/dev/null 2>&1; then
  export MSYS_NO_PATHCONV=1
  HOST_DIR="$(cygpath -m "$INFRA")"
else
  HOST_DIR="$INFRA"
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker에 연결할 수 없습니다. Docker Desktop을 켜고 다시 실행하세요." >&2; exit 1
fi

# 줄바꿈 확인: Windows에서 CRLF로 받으면 컨테이너 안 초기화 스크립트가 깨진다
if grep -q $'\r' "$INFRA/db/init/10-agent-kb.sh" "$SCRIPT_DIR/negative_tests.sh" 2>/dev/null; then
  echo "스크립트 줄바꿈이 CRLF입니다. main-infra-manage 루트에서: git add --renormalize . (또는 에디터에서 LF로 저장) 후 다시 실행하세요." >&2; exit 1
fi
echo "업무 DB 스키마: $MIG"
echo "지식 DB 스키마: $KB_MIG"
NAME=schema-verify-mysql

docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" \
  -e MYSQL_ROOT_PASSWORD=root -e MYSQL_DATABASE=verify -e MYSQL_USER=app -e MYSQL_PASSWORD=app \
  -e KB_OWNER_PASSWORD=owner -e KB_INGEST_PASSWORD=ingest -e KB_READER_PASSWORD=reader \
  -e TZ=Asia/Seoul \
  -v "$HOST_DIR/db/init:/docker-entrypoint-initdb.d:ro" \
  mysql:8.4 --log-bin-trust-function-creators=1 --default-time-zone=+09:00 >/dev/null
# KEEP=1 bash infra/db/verify/verify.sh 로 실행하면 끝난 뒤 컨테이너를 지우지 않음 (원인 확인용)
trap '[ "${KEEP:-0}" = "1" ] || docker rm -f "$NAME" >/dev/null 2>&1 || true' EXIT

sql() { echo "docker exec -i $NAME mysql --protocol=tcp -h127.0.0.1 --default-character-set=utf8mb4 -u$1 -p$2 $3"; }
export RUN="$(sql app app verify)"
export RUN_KB_OWNER="$(sql kb_owner owner agent_kb)"
export RUN_KB_INGEST="$(sql kb_ingest ingest agent_kb)"
export RUN_KB_READER="$(sql kb_reader reader agent_kb)"
export RUN_APP_NODB="$(sql app app '')"
export RUN_KB_INGEST_NODB="$(sql kb_ingest ingest '')"
export RUN_KB_READER_NODB="$(sql kb_reader reader '')"

# 초기화 중 임시 서버는 TCP를 열지 않으므로, TCP로 kb_reader 접속이 되면 초기화 스크립트까지 끝난 것
echo "MySQL 기동·초기화 대기... (처음엔 1분쯤 걸림, 최대 3분)"
waited=0
until $RUN_KB_READER -e "SELECT 1" >/dev/null 2>&1; do
  sleep 3; waited=$((waited+3))
  if ! docker ps -q -f name="^${NAME}$" | grep -q .; then
    echo "MySQL 컨테이너가 중간에 꺼졌습니다. 로그:" >&2; docker logs "$NAME" --tail 40 >&2; exit 1
  fi
  if [ "$waited" -ge 180 ]; then
    echo "3분이 지나도 kb_reader로 접속이 안 됩니다 (지식 DB 초기화 스크립트 실패 가능성). 로그:" >&2
    docker logs "$NAME" --tail 40 >&2
    echo "--- 초기화 폴더 안 파일 (10-agent-kb.sh가 보여야 정상):" >&2
    docker exec "$NAME" ls -l /docker-entrypoint-initdb.d >&2 || true
    exit 1
  fi
done
echo "MySQL 준비 완료 (${waited}초)"

echo "=== 업무 DB (Spring 소유)"
for f in $(ls "$MIG" | grep -E '^V[0-9_]+__.*\.sql$' | sort -V); do
  echo "적용: $f"; $RUN < "$MIG/$f"
done
for f in $(ls "$MIG" | grep -E '^R__.*\.sql$'); do
  echo "적용: $f"; $RUN < "$MIG/$f"
  echo "재적용(반복 실행 확인): $f"; $RUN < "$MIG/$f"
done

echo "=== 지식 DB agent_kb (FastAPI 소유)"
for f in $(ls "$KB_MIG" | grep -E '^V[0-9_]+__.*\.sql$' | sort -V); do
  echo "적용(kb_owner): $f"; $RUN_KB_OWNER < "$KB_MIG/$f"
done

echo "--- 테이블 수 (기대: 업무 62 = 기존 5 + 신규 57 / 지식 6)"
$RUN <<< "SELECT table_schema, COUNT(*) AS tables FROM information_schema.tables WHERE table_schema IN ('verify') AND table_type='BASE TABLE' GROUP BY table_schema;"
$RUN_KB_OWNER <<< "SELECT table_schema, COUNT(*) AS tables FROM information_schema.tables WHERE table_schema IN ('agent_kb') AND table_type='BASE TABLE' GROUP BY table_schema;"

echo "--- 정상 흐름 (현장 드롭다운, 시나리오 A·B·C·D, 편집·임시저장·제출·PDF 출력, 알림)"
$RUN < "$SCRIPT_DIR/smoke_test.sql"
echo "--- 위반 케이스"
bash "$SCRIPT_DIR/negative_tests.sh"
echo "완료"
