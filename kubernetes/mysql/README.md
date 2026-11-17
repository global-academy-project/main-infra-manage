# MySQL Kubernetes 이관

## 목적과 범위

Docker Compose의 MySQL과 Flyway 마이그레이션을 Kubernetes로 이관하기 위한 작업 문서입니다. `api-service.yaml`은 범위에서 제외합니다. **현재 매니페스트는 초안이며 그대로 배포할 수 없습니다.** 아래의 적용 전 항목과 운영 절차는 구현 및 검증이 필요합니다.

기본 Compose 설정은 `mysql:8.4.13-oraclelinux9`와 `database-data` 볼륨을 사용합니다. Flyway는 `db/migration`을 `/flyway/sql`에 마운트하고 MySQL health check가 통과한 뒤 실행됩니다.

## Kubernetes 구성

| 파일 | 현재 구성 |
| --- | --- |
| [configmap.yaml](./configmap.yaml) | MySQL과 Flyway Job에 주입할 비밀이 아닌 환경변수 |
| [secret-example.yaml](./secret-example.yaml) | MySQL 및 Flyway Secret 작성용 예시. 실제 값으로 교체하기 전에는 사용할 수 없음 |
| `secret.yaml` | 로컬 전용 Secret 파일. `.gitignore` 대상 |
| [volume.yaml](./volume.yaml) | `mysql-data` PVC. 1Gi, `ReadWriteOnce` |
| [service.yaml](./service.yaml) | 내부 포트 3306, 외부 NodePort 30036 |
| [statefulset.yaml](./statefulset.yaml) | MySQL 단일 인스턴스, CPU·메모리 설정 및 PVC 마운트 |
| [job.yaml](./job.yaml) | Flyway 마이그레이션 Job 초안 |
| [kustomize.yaml](./kustomize.yaml) | 매니페스트 묶음 초안. 현재 Kustomize가 인식하는 파일명이 아님 |

클러스터 내부 클라이언트는 같은 네임스페이스에서 `mysql-service:3306`으로 접속합니다. 다른 네임스페이스에서는 서비스의 전체 DNS 이름을 사용합니다. NodePort가 외부에 도달 가능한지는 클러스터 네트워크와 방화벽에 따라 달라집니다. 외부 접속이 불필요하면 ClusterIP로 전환하는 것을 검토합니다.

### 데이터베이스와 환경변수

- `MYSQL_DATABASE: ocrdb`는 업무 DB 설정이고, `agent_kb`는 지식 DB입니다. 둘을 같은 이름으로 맞출 필요는 없습니다. 업무 DB 계정과 KB 계정의 용도를 구분합니다.
- StatefulSet은 `mysql-config`와 `mysql-secret`을 `envFrom`으로 참조합니다. 예시의 `MYSQL_USER: user`와 비밀번호는 실제 애플리케이션 설정과 맞춰야 합니다.
- [10-agent-kb.sh](../../db/init/10-agent-kb.sh)는 `agent_kb`와 `kb_owner`, `kb_ingest`, `kb_reader` 계정을 생성합니다. `KB_OWNER_PASSWORD`, `KB_INGEST_PASSWORD`, `KB_READER_PASSWORD`가 필요합니다.
- ConfigMap의 `data`는 문자열입니다. `EMBEDDING_MAX_TOKENS: "8192"`와 `EMBEDDING_MAX_BATCH_SIZE: "8"`처럼 따옴표로 작성합니다. 컨테이너 환경변수도 문자열이므로 숫자로 사용할 경우 애플리케이션이나 설정 라이브러리에서 정수로 변환해야 합니다. 현재 값은 Flyway Job에 주입되며, 임베딩 애플리케이션에 자동으로 전달되지는 않습니다.

## 적용 전 정리할 항목

1. `kustomize.yaml`을 Kustomize가 인식하는 `kustomization.yaml`로 변경하고, 존재하지 않는 `secrets.yaml`, `deployment.yaml` 대신 실제 리소스 목록을 구성합니다. Secret은 로컬 생성 또는 별도 관리 방식에 맞게 연결합니다.
2. StatefulSet의 `command`는 현재 Pod spec에 있어 유효하지 않습니다. MySQL 이미지의 초기화 ENTRYPOINT를 유지하도록 컨테이너의 `args`로 옵션을 전달하는 방식 등을 검토합니다.
3. 현재 같은 PVC가 `/var/lib/mysql`과 `/docker-entrypoint-initdb.d`에 마운트되어 있습니다. 초기화 스크립트를 제공하는 구성이 아니므로, 데이터 볼륨과 분리하여 스크립트를 제공해야 합니다. 스크립트와 이미지의 초기화는 데이터 디렉터리가 비어 있는 최초 기동에만 자동 실행됩니다.
4. [mysql-migration.Dockerfile](../../docker/mysql-migration.Dockerfile)은 SQL 파일과 `mysql-service:3306/agent_kb`, `kb_owner`, `migrate` 기본 인자를 이미지에 포함합니다. 이를 `migration:v1.0.0`으로 빌드하고 클러스터 노드에서 이미지를 사용할 수 있게 해야 합니다. Job에서 별도 SQL 마운트가 필수는 아니며 `/flyway/sql`에 마운트하면 이미지의 SQL이 가려집니다.
5. Job이 MySQL 준비를 기다리는 방식과 재시도·시간 제한을 정합니다. `restartPolicy: Never`여도 Job이 실패한 Pod 대신 새 Pod를 생성해 재시도할 수 있습니다. Job 완료와 Flyway 결과를 확인하는 절차도 필요합니다.
6. PVC를 생성할 StorageClass와 스토리지 프로비저너를 확인합니다. 1Gi의 적정성을 실제 데이터 증가량과 백업·운영 요구에 따라 검토합니다.
7. StatefulSet의 안정적인 Pod별 DNS가 필요하다면 별도 headless Service와 `serviceName` 구성을 검토합니다. 현재 `mysql-service`는 NodePort Service입니다.

## Secret 관리와 교체

`secret-example.yaml`의 `data` 값은 설명용 문자열입니다. `data`에는 Base64 인코딩 값이 필요하고, 평문을 입력할 때는 `stringData`를 사용할 수 있습니다. **Base64는 암호화가 아닙니다.** 실제 비밀번호와 인증서는 Git에 넣지 않고, Kubernetes Secret 접근을 RBAC으로 제한하며 클러스터의 저장 시 암호화 설정을 확인합니다. 외부 비밀 관리 서비스 연동도 검토합니다.

`mysql-secret`과 `mysql-init-secret`은 각각 따로 준비합니다. Flyway의 `FLYWAY_PASSWORD`는 DB의 `kb_owner` 비밀번호와 일치해야 합니다. Secret 파일과 백업, 명령 기록 및 로그에 비밀값이 노출되지 않도록 관리합니다.

### 비밀번호 교체 절차

1. 대상 계정을 사용하는 클라이언트, 점검 시간 및 롤백 방법을 확인합니다.
2. MySQL에서 해당 계정의 비밀번호를 변경하고, 관련 Secret을 같은 값으로 갱신합니다. 예를 들어 `kb_owner`는 Flyway의 `FLYWAY_PASSWORD`와 함께 갱신합니다.
3. 환경변수로 Secret을 읽는 각 애플리케이션 Pod를 재시작하고 연결을 확인합니다. 새 설정으로 Flyway를 다시 실행하려면 새 Job이 필요합니다.
4. 새 비밀번호로 연결되고 이전 비밀번호는 더 이상 사용할 수 없는지 확인합니다.

**Secret 변경만으로 기존 MySQL 계정 비밀번호가 바뀌지는 않습니다.** 기존 PVC에서는 초기화 환경변수를 바꿔도 초기화가 다시 실행되지 않습니다. DB와 클라이언트 설정을 변경하는 사이에 접속 중단이 발생할 수 있으므로 점검 시간을 확보합니다.

## DB 연결 암호화

현재 매니페스트에는 MySQL TLS 인증서와 TLS 강제 설정이 없습니다. Service나 NodePort만으로 연결이 암호화되지는 않습니다.

1. MySQL 서버 인증서·개인키와 클라이언트가 신뢰할 CA를 준비합니다. 인증서 SAN에는 클라이언트가 실제로 사용하는 서비스 DNS 이름이 포함되어야 합니다.
2. 인증서와 키를 Secret으로 제공하고 읽기 전용 마운트 및 MySQL TLS 설정을 구성합니다.
3. Spring, Flyway 및 다른 DB 클라이언트가 CA와 서버 이름을 검증하도록 설정합니다. JDBC 클라이언트는 드라이버의 `sslMode=VERIFY_IDENTITY` 설정과 신뢰 저장소 구성을 검토합니다.
4. 모든 클라이언트의 TLS 연결을 검증한 뒤 MySQL의 `require_secure_transport=ON`을 적용합니다. 연결한 세션에서 `SHOW SESSION STATUS LIKE 'Ssl_cipher';`의 값으로 TLS 사용 여부를 확인합니다.

인증서 교체 시 서버 인증서와 클라이언트의 CA 신뢰를 함께 갱신하고, 필요하면 MySQL 재시작에 따른 중단 시간을 확보합니다. 외부 접속이 필요하다면 TLS와 별도로 네트워크 접근도 제한합니다.

## 리소스와 장애 대응

현재 StatefulSet의 CPU 요청/제한은 각각 `1`/`2`, 메모리 요청/제한은 `1Gi`/`2Gi`입니다. 요청은 Pod 스케줄링에 사용되며 CPU 제한 초과 시 실행이 제한되고 메모리 제한 초과 시 OOM 종료될 수 있습니다. 이 값이 적정하다고 확정하지 말고 실제 부하, MySQL 버퍼, 연결 수 및 메모리 사용량을 측정해 조정합니다.

현재 `startupProbe`, `readinessProbe`, `livenessProbe`는 없습니다. 초기화 시간을 허용하는 startup probe와 인증된 쿼리 성공을 확인하는 readiness probe를 설계합니다. 별도 최소 권한 계정을 사용할 경우 인증 정보는 안전하게 주입하고 TLS 검증 설정도 맞춥니다. liveness probe는 일시적인 부하를 장애로 오인해 DB를 반복 재시작하지 않도록 신중히 도입합니다. readiness가 준비되지 않으면 일반적으로 Service의 새 연결 대상에서 제외되지만 기존 연결 종료를 보장하지는 않습니다.

MySQL은 단일 인스턴스이므로 장애 중 DB를 사용할 수 없습니다. Pod 재생성이 데이터 손상이나 노드·스토리지 장애의 자동 복구를 보장하지는 않습니다. 장애 시:

1. Pod, PVC, 이벤트와 MySQL 로그를 확인합니다.
2. OOM, 디스크 부족, 스토리지 연결 실패 등 원인을 해결합니다.
3. 기존 PVC를 다시 마운트한 MySQL이 정상 기동하고 데이터와 애플리케이션 연결이 정상인지 확인합니다.
4. 데이터가 손상된 경우 검증된 백업에서 복원합니다. 노드 장애 시 기존 MySQL 프로세스가 완전히 중지됐는지 확인하기 전에는 Pod를 강제 삭제하거나 동일 데이터를 다른 인스턴스에서 열지 않습니다.

평소 백업 주기, 허용 데이터 손실 시간, 복원 목표 시간과 복원 테스트를 정합니다. PVC는 백업이나 고가용성을 대신하지 않습니다.

## 권장 이관 순서

1. 업무 DB와 지식 DB의 계정·권한, 이미지, Secret, 스토리지 및 TLS 정책을 확정합니다.
2. 위 적용 전 항목을 수정하고 초기화 스크립트, readiness와 Job 실행 순서를 검증합니다.
3. PVC, Service, StatefulSet을 적용하고 MySQL 및 계정 준비를 확인합니다.
4. 기존 데이터를 옮길 때는 쓰기를 중단하고 백업한 뒤 새 MySQL에 복원합니다. 새 PVC는 Compose 볼륨과 별개이며 데이터가 자동으로 복사되지 않습니다.
5. Flyway Job의 성공과 스키마를 확인하고 애플리케이션의 DB 주소를 전환합니다. 신규 환경도 Flyway 실행 전에 DB와 계정을 준비해야 합니다.
6. 연결과 주요 기능, 복구 가능성을 확인할 때까지 기존 볼륨과 백업을 보존합니다.

## 검증

적용하기 전에 Kustomize 파일명과 리소스 목록을 수정하고 렌더링 및 검증해야 합니다. **현재 상태에서는 `kubectl apply -k`를 실행하지 않습니다.** 비밀값이 렌더링 결과나 로그에 노출되지 않도록 주의합니다.

수정 및 적용 후에는 실제 네임스페이스와 Pod 이름으로 다음을 확인합니다.

```powershell
kubectl -n <namespace> get statefulset,pods,pvc,services,jobs
kubectl -n <namespace> describe pvc mysql-data
kubectl -n <namespace> logs statefulset/mysql-statefulset
kubectl -n <namespace> logs job/kb-init
```

`<namespace>`는 실제 값으로 바꿉니다. Job 성공 여부, DB 계정별 권한, 애플리케이션 연결과 TLS 사용 여부를 함께 확인합니다.
