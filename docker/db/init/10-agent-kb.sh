#!/usr/bin/env bash
# FastAPI 전용 지식 DB(agent_kb)와 계정 3개를 만든다.
#  - MySQL 최초 기동 시 /docker-entrypoint-initdb.d 에서 root로 자동 실행된다.
#  - 이미 데이터가 있는 볼륨이면 자동 실행되지 않으므로 한 번 직접 실행:
#      docker compose exec ocr-mysql bash /docker-entrypoint-initdb.d/10-agent-kb.sh
#  - 여러 번 실행해도 안전하다 (있으면 비밀번호·권한만 다시 맞춤).
#
# 권한 설계 (최소 권한)
#   업무 DB 앱 계정(MYSQL_USER) : 업무 DB만. agent_kb 접근 불가
#   kb_owner                    : agent_kb DDL (마이그레이션 전용, 앱은 이 계정을 쓰지 않음)
#   kb_ingest                   : agent_kb 읽기·쓰기 (적재 작업)
#   kb_reader                   : agent_kb 읽기만 (에이전트 실행)
#   kb_* 계정은 업무 DB에 권한 없음
# -u(미정의 변수 오류)는 쓰지 않는다: 실행 권한이 없으면 MySQL 이미지가 이 파일을 source로 읽는데,
#   그때 -u가 이미지 초기화 스크립트에까지 번져 기동이 깨질 수 있다. 필수 값은 아래 :? 검사로 막는다.
set -eo pipefail

: "${MYSQL_ROOT_PASSWORD:?필요}"
: "${KB_OWNER_PASSWORD:?KB_OWNER_PASSWORD 환경 변수 필요}"
: "${KB_INGEST_PASSWORD:?KB_INGEST_PASSWORD 환경 변수 필요}"
: "${KB_READER_PASSWORD:?KB_READER_PASSWORD 환경 변수 필요}"
KB_DB="${KB_DATABASE:-agent_kb}"

mysql --protocol=socket -uroot -p"$MYSQL_ROOT_PASSWORD" <<SQL
CREATE DATABASE IF NOT EXISTS \`${KB_DB}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'kb_owner'@'%'  IDENTIFIED BY '${KB_OWNER_PASSWORD}';
CREATE USER IF NOT EXISTS 'kb_ingest'@'%' IDENTIFIED BY '${KB_INGEST_PASSWORD}';
CREATE USER IF NOT EXISTS 'kb_reader'@'%' IDENTIFIED BY '${KB_READER_PASSWORD}';
ALTER USER 'kb_owner'@'%'  IDENTIFIED BY '${KB_OWNER_PASSWORD}';
ALTER USER 'kb_ingest'@'%' IDENTIFIED BY '${KB_INGEST_PASSWORD}';
ALTER USER 'kb_reader'@'%' IDENTIFIED BY '${KB_READER_PASSWORD}';

GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, DROP, INDEX, REFERENCES ON \`${KB_DB}\`.* TO 'kb_owner'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON \`${KB_DB}\`.* TO 'kb_ingest'@'%';
GRANT SELECT ON \`${KB_DB}\`.* TO 'kb_reader'@'%';
FLUSH PRIVILEGES;
SQL

echo "[agent-kb] ${KB_DB} 데이터베이스와 kb_owner / kb_ingest / kb_reader 계정 준비 완료"
