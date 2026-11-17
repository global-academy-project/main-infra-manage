# Docker 실행 가이드

## 대상과 실행 위치

- [docker-compose.yml](./docker-compose.yml): 웹, API, AI 모델, 데이터베이스와 초기화 작업을 함께 실행합니다.
- [migration.Dockerfile](./migration.Dockerfile): **Kubernetes Job에서 실행할 DB 마이그레이션용 이미지**를 빌드합니다. Flyway와 SQL 파일을 포함하며, MySQL 서버 이미지나 Docker Compose용 Dockerfile이 아닙니다.

아래 PowerShell 명령은 모두 저장소 루트인 `main-infra-manage`에서 실행합니다.

```powershell
Set-Location C:\projects\org\main-infra-manage
```

Docker Desktop과 Docker Compose v2가 필요합니다. Compose가 빌드하는 다른 프로젝트도 다음처럼 같은 상위 디렉터리에 준비해야 합니다.

```text
상위 디렉터리
├─ main-infra-manage
├─ main-vite-web
├─ main-server
└─ main-ai-model
```

## Docker Compose

### 서비스와 접속 포트

| 서비스                    | 역할                          | 호스트에서 접속          | 컨테이너 간 주소                |
| ------------------------- | ----------------------------- | ------------------------ | ------------------------------- |
| `vite-web-application`    | Vite 웹 애플리케이션          | `http://localhost:50001` | `vite-web-application:50001`    |
| `spring-boot-application` | Spring Boot API               | 직접 노출하지 않음       | `spring-boot-application:60001` |
| `python-ai-model`         | AI API                        | `http://localhost:60100` | `python-ai-model:60100`         |
| `python-embedding-model`  | 임베딩 모델 API               | 직접 노출하지 않음       | `python-embedding-model:60110`  |
| `database-mysql-server`   | MySQL                         | `localhost:60010`        | `database-mysql-server:3306`    |
| `kb-migrator`             | Flyway 스키마 마이그레이션    | 해당 없음                | MySQL에 접속하는 일회성 작업    |
| `qdrant-server`           | 벡터 데이터베이스             | `http://localhost:60011` | `qdrant-server:6333`            |
| `qdrant-init`             | Qdrant 컬렉션과 인덱스 초기화 | 해당 없음                | 일회성 작업                     |
| `kb-ingest`               | 지식 데이터 적재 API          | `http://localhost:8001`  | `kb-ingest:8001`                |

컨테이너끼리는 기본 bridge 네트워크에서 서비스 이름과 컨테이너 포트로 통신합니다. 예를 들어 MySQL에 접속할 때 호스트에서는 `localhost:60010`, 다른 컨테이너에서는 `database-mysql-server:3306`을 사용합니다.

현재 포트 매핑에는 호스트 IP 제한이 없으므로 로컬 컴퓨터 외부에서도 접근할 수 있습니다. 개발 환경을 넘어 사용할 때는 방화벽과 바인딩 주소를 검토합니다.

### 환경변수 준비

로컬 전용 `docker/.env` 파일에 값을 준비합니다. 아래 명령은 이 파일을 `--env-file`로 명시해서 사용합니다. 실제 비밀번호와 토큰은 문서나 Git에 포함하지 않습니다.

| 구분            | 환경변수                                                                                      |
| --------------- | --------------------------------------------------------------------------------------------- |
| 업무 DB         | `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_ROOT_PASSWORD`                       |
| 지식 DB 계정    | `KB_OWNER_PASSWORD`, `KB_INGEST_PASSWORD`, `KB_READER_PASSWORD`                               |
| 내부 API와 인증 | `INTERNAL_API_TOKEN`, `JWT_SECRET`, `KB_INGEST_API_TOKEN`                                     |
| Qdrant          | `QDRANT_API_KEY`, `QDRANT_READ_ONLY_API_KEY`                                                  |
| 임베딩          | `EMBEDDING_API_KEY`                                                                           |
| 선택 설정       | `ADMIN_EMAIL`, `ADMIN_PASSWORD`, `LLM_ADAPTERS`, `CHECK_RULES_TOOL`, `KOSHA_MSDS_SERVICE_KEY` |

Compose의 `${변수:?오류 메시지}`는 값이 비어 있으면 실행을 차단합니다. 이런 검사가 없는 변수도 애플리케이션이나 DB 초기화에서 필요할 수 있습니다. 특히 MySQL 초기화 스크립트는 세 가지 `KB_*_PASSWORD` 값을 요구합니다.

### 실행과 확인

```powershell
# 환경변수 치환과 Compose 설정 검사
docker compose --env-file docker\.env -f docker\docker-compose.yml config --quiet

# 이미지 빌드 및 전체 서비스 시작
docker compose --env-file docker\.env -f docker\docker-compose.yml up -d --build

# 일회성 작업을 포함한 상태 확인
docker compose --env-file docker\.env -f docker\docker-compose.yml ps -a

# 마이그레이션 결과 확인
docker compose --env-file docker\.env -f docker\docker-compose.yml logs kb-migrator

# 서비스 중지 및 컨테이너/네트워크 제거
docker compose --env-file docker\.env -f docker\docker-compose.yml down
```

`kb-migrator`와 `qdrant-init`은 정상 완료 후 종료됩니다. 종료 코드가 `0`인지 로그와 상태를 함께 확인합니다.

첫 실행에서는 모델 다운로드와 DB 초기화로 준비 시간이 길어질 수 있습니다.

### 시작 의존성

- Spring Boot는 MySQL과 Qdrant의 health check 통과를 기다립니다.
- Flyway는 MySQL의 health check 통과를 기다린 뒤 실행됩니다.
- Qdrant 초기화 작업은 Qdrant의 health check 통과를 기다립니다.
- AI API는 Qdrant 초기화 성공, Qdrant와 임베딩 API의 health check 통과를 기다립니다.
- 적재 API는 Qdrant 초기화 성공, Qdrant와 MySQL의 health check 통과를 기다립니다.

현재 Spring Boot와 적재 API는 Flyway 완료를 기다리도록 설정되어 있지 않습니다. 전체 서비스 시작이 곧 스키마 마이그레이션 완료를 의미하지는 않습니다. `depends_on`은 시작 조건이며, 운영 중 의존 서비스 장애에 대한 자동 복구를 보장하지 않습니다.

### 데이터와 SQL 파일

Compose의 상대 마운트 경로는 `docker-compose.yml`이 있는 디렉터리 기준입니다.

| 원본                                           | 컨테이너 경로                         | 용도                                                      |
| ---------------------------------------------- | ------------------------------------- | --------------------------------------------------------- |
| [db/init](../db/init)                          | MySQL의 `/docker-entrypoint-initdb.d` | 초기 DB와 계정 생성, 읽기 전용                            |
| [db/verify](../db/verify)                      | MySQL의 `/opt/verify`                 | 검증 스크립트, 읽기 전용. 마운트만으로 자동 실행되지 않음 |
| [db/migration](../db/migration)                | Flyway의 `/flyway/sql`                | 버전별 스키마 마이그레이션                                |
| `database-data` 볼륨                           | MySQL의 `/var/lib/mysql`              | MySQL 데이터 영속 저장                                    |
| `qdrant-data` 볼륨                             | Qdrant의 `/qdrant/storage`            | 벡터 데이터 영속 저장                                     |
| `ai-model-cache`, `embedding-model-cache` 볼륨 | 각 서비스의 `/models/huggingface`     | 모델 캐시                                                 |

MySQL 초기화 스크립트는 데이터 디렉터리가 비어 있는 최초 실행에만 자동 실행됩니다. 기존 볼륨에서는 환경변수나 스크립트를 수정해도 초기화가 반복되지 않습니다.

Flyway는 `agent_kb` DB에 `kb_owner` 계정으로 접속하여 `V1__kb_init.sql`, `V2__eval.sql` 등을 적용합니다. 적용된 마이그레이션을 수정하기보다 새 버전 파일을 추가합니다.

기존 DB가 준비된 상태에서 마이그레이션을 다시 실행하려면:

```powershell
docker compose --env-file docker\.env -f docker\docker-compose.yml run --rm kb-migrator
```

일반적인 `down`은 named volume을 보존합니다. **`down -v`는 DB와 모델 캐시 등 Compose가 관리하는 named volume을 삭제하므로, 데이터 초기화가 목적이 아니라면 사용하지 않습니다.**

## migration.Dockerfile — Kubernetes용 DB 마이그레이션 이미지

### 역할

`migration.Dockerfile`은 **Kubernetes Job에서 DB 스키마 마이그레이션을 실행하기 위한 Dockerfile**입니다. 로컬 디렉터리를 직접 마운트하는 대신 SQL을 이미지에 포함해 클러스터에 배포합니다.

Docker Compose의 `kb-migrator`는 이 Dockerfile을 사용하지 않습니다. Compose는 공식 Flyway 이미지에 호스트의 SQL 디렉터리를 마운트하는 기존 방식을 사용합니다.

| 설정                                                  | 의미                                               |
| ----------------------------------------------------- | -------------------------------------------------- |
| `FROM flyway/flyway:13.12-alpine`                     | Flyway 기반 이미지                                 |
| `USER 65003:65003`                                    | 이후 실행 시 사용할 UID/GID                        |
| `COPY --chown=65003:65003 db/migration/ /flyway/sql/` | SQL을 이미지에 복사하고 소유자 지정                |
| `CMD [...]`                                           | 기반 이미지의 Flyway ENTRYPOINT에 전달할 기본 인자 |

이미지 빌드 시에는 SQL을 복사할 뿐 DB에 접속하거나 마이그레이션을 실행하지 않습니다. 마이그레이션은 컨테이너 실행 시 수행됩니다.

### 빌드 컨텍스트와 빌드 명령

```powershell
docker build -f docker\migration.Dockerfile -t flyway-with-migrations:local .
```

- `-f`는 사용할 Dockerfile 위치입니다.
- 마지막 `.`은 현재 디렉터리, 즉 저장소 루트를 빌드 컨텍스트로 지정합니다.
- `COPY db/migration/`은 Dockerfile 위치가 아니라 빌드 컨텍스트를 기준으로 해석됩니다.
- Dockerfile과 SQL이 같은 디렉터리에 있을 필요는 없지만, SQL은 빌드 컨텍스트 안에 있어야 합니다.

`docker` 디렉터리를 컨텍스트로 사용하면 별도로 존재하는 `docker/db/migration`을 복사할 수 있어 루트의 SQL과 혼동될 수 있습니다. 이 문서에서는 Compose와 동일하게 저장소 루트의 `db/migration`을 기준으로 빌드합니다.

SQL을 변경한 경우 이미지를 다시 빌드해야 합니다.

### Kubernetes Job 실행 시 확인할 항목

현재 Dockerfile의 기본 접속 대상은 Kubernetes Service 이름인 `mysql-service:3306/agent_kb`이며, 사용자는 `kb_owner`입니다.

- Kubernetes에서는 해당 Service에 접근 가능한 네임스페이스/네트워크에서 실행하고, `FLYWAY_PASSWORD`를 Secret 등으로 주입해야 합니다.
- 로컬 Docker에서 단독 실행하면 Kubernetes의 Service 이름이 자동으로 해석되지는 않습니다.
- Job의 컨테이너 이미지에 빌드한 이미지를 지정하고, `/flyway/sql`에 별도 볼륨을 마운트하지 않아야 이미지에 포함된 SQL을 사용합니다. 해당 경로에 마운트하면 이미지의 SQL이 가려집니다.
- Kubernetes에서 Flyway 인자를 재정의할 때는 `args`를 사용합니다. `command`는 이미지의 ENTRYPOINT 자체를 대체합니다.
- 다른 클러스터/노드에서 실행하려면 이미지 레지스트리에 push하는 등 실행 환경에서 이미지를 가져올 수 있도록 준비해야 합니다.

DB와 계정은 마이그레이션 전에 준비되어 있어야 합니다. SQL을 이미지에 포함하는 것만으로 MySQL 초기화 스크립트나 영속 데이터까지 함께 제공되는 것은 아닙니다.