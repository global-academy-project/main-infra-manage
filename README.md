# Main Project for Infra Manager

웹, Spring Boot API, Python AI 서비스를 로컬 통합 환경과 Kubernetes 리소스로
연결하는 인프라 저장소입니다. 서비스 코드는 각 프로젝트 저장소에서 관리하고,
이 저장소에서는 Compose 구성, 데이터베이스 초기화 및 마이그레이션, 모니터링,
Kubernetes 초안을 관리합니다.

## 빠른 시작: Docker Compose

Docker Desktop과 Docker Compose v2를 준비하고, 다음 저장소들이 같은 상위
디렉터리에 있는지 확인합니다.

```text
main-infra-manage
main-vite-web
main-server
main-ai-model
```

`docker/.env`를 로컬에서 만들고 필요한 변수와 비밀 값을 입력합니다.
필수 변수 목록과 서비스별 동작은 [Docker 실행 가이드](docker/README.md)에
정리되어 있습니다. 저장소에 실제 비밀번호, 토큰 또는 API 키를 커밋하지 마세요.

저장소 루트에서 Compose 설정을 검증하고 서비스를 실행합니다.

```powershell
docker compose --env-file .\docker\.env -f .\docker\docker-compose.yml config --quiet
docker compose --env-file .\docker\.env -f .\docker\docker-compose.yml up -d --build
docker compose --env-file .\docker\.env -f .\docker\docker-compose.yml ps -a
```

컨테이너 간 연결 주소와 호스트 공개 포트, 초기화 작업, 로그 확인 절차는
[Docker 실행 가이드](docker/README.md)를 참고하세요. 개발용 데이터베이스만
실행하는 `docker-compose.dev.yml` 구성은 아래의 개발 DB 보관 안내를 따릅니다.

## Kubernetes

`kubernetes/`에는 Compose 구성을 옮기기 위한 진행 중인 매니페스트 초안이 있습니다.
배포 전에 [Kubernetes README](kubernetes/README.md)와 각 서비스 매니페스트를
검토하세요. 초안의 Secret 리소스에 실제 운영 비밀 값을 두지 말고, 클러스터의
Secret 관리 방식을 정한 뒤 적용해야 합니다.

## 저장소 구성

| 경로 | 내용 |
|---|---|
| `docker/` | Compose 구성, 실행 가이드, 모니터링 설정 |
| `db/init/` | MySQL 최초 데이터 디렉터리 초기화 스크립트 |
| `db/migration/` | Flyway 데이터베이스 마이그레이션 |
| `db/verify/` | 수동 검증용 스크립트 |
| `kubernetes/` | Kubernetes 리소스 및 Kustomize 초안 |
| `utils/` | 인프라 관리 유틸리티 |

## Development web proxy

The web container forwards `/api` requests to
`http://spring-boot-application:60001` through `VITE_API_PROXY_TARGET`.
Inside the web container, `localhost` refers to the web container itself, not
Spring. Spring does not need a published host port for this connection.

## Development database storage

In [the development Compose configuration](docker/docker-compose.dev.yml), MySQL
uses `database-data`, while Qdrant retains the existing `default` volume.
Never mount the same data volume into both database services.

Spring waits for an authenticated MySQL health check before starting.
Initialization scripts run only when MySQL initializes an empty data directory.

When separating an existing shared volume, inspect and back up its contents first.
The new MySQL volume does not automatically migrate old MySQL data.
Do not use `docker compose down --volumes` when preserving database data.

From the repository root, validate and start the database with:

```powershell
docker compose --env-file .\docker\.env -f .\docker\docker-compose.dev.yml config --quiet
docker compose --env-file .\docker\.env -f .\docker\docker-compose.dev.yml up -d --wait database-mysql-server
```

## Docker Compose configuration

For the main Compose stack's image, healthcheck, volume, and environment variable
notes, see the [Docker execution guide](docker/README.md).
