# Kubernetes 초안

이 디렉터리는 Docker Compose 구성을 Kubernetes 리소스로 이관하기 위한 초안이다.

현재 상태는 설계와 검증이 진행 중이며, 파일과 매니페스트 구조가 변경될 수 있다.

## 디렉터리 구조

| 경로 | 역할 |
|---|---|
| `common-config.yaml` | 여러 Kubernetes 리소스가 공통으로 사용할 비밀이 아닌 설정 |
| `common-secret.yaml` | 공통 Secret 초안 |
| `kustomization.yaml` | 전체 리소스를 연결하는 루트 Kustomization |
| `vite/` | Vite 웹 Deployment와 Service |
| `spring/` | Spring Boot 애플리케이션 리소스 |
| `agent/` | Python AI 모델 리소스 |
| `embedding/` | 임베딩 모델 리소스 |
| `ingest/` | KB ingest 작업 리소스 |
| `mysql/` | MySQL StatefulSet, Job, Secret, Volume 리소스 |
| `qdrant/` | Qdrant StatefulSet, Job, ConfigMap, Secret 리소스 |

상세 환경 변수 분석서는 [docs/environment-variable-audit.md](../docs/environment-variable-audit.md)를 참고한다.

## 설정 분리 원칙

### ConfigMap

- 비밀번호나 토큰을 포함하지 않는다.
- 여러 독립 서비스가 실제로 소비하는 값만 공통 리소스에 둔다.
- 도메인별 설정은 해당 도메인의 ConfigMap으로 분리한다.
- Pod 내부 주소는 실제 Kubernetes Service 이름과 포트로 작성한다.

예를 들어 `TZ`, `LANG`, `LC_ALL`은 내부 시스템에서 공통으로 사용될 수 있으므로
`common-system-config`에 둔다.

반면 임베딩 모델, 차원, 배치 크기와 같은 설정은 임베딩 관련 리소스에만
주입되도록 `common-embedding-config`로 분리한다.

### Secret

- 비밀번호, API 키, 토큰은 ConfigMap이 아니라 Secret에 둔다.
- 실제 Secret 값은 Git에 커밋하지 않는다.
- 저장소에는 `secret-example.yaml` 또는 운영 환경에서 생성할 Secret 템플릿만 둔다.
- 공통 Secret은 실제로 여러 컴포넌트가 동일한 값을 사용하는 경우에만 사용한다.

## 환경 변수 주입 방식

키가 여러 개이고 동일 도메인의 설정을 함께 소비하는 경우 `envFrom`을 사용한다.

```yaml
envFrom:
  - configMapRef:
      name: common-system-config
  - configMapRef:
      name: common-embedding-config
  - secretRef:
      name: common-embedding-secret
```

`envFrom`은 해당 ConfigMap 또는 Secret의 모든 키를 주입한다.
반드시 필요한 설정만 포함된 리소스인지 확인해야 한다.

키가 1~2개이고 사용 대상을 제한해야 하는 경우 `configMapKeyRef` 또는
`secretKeyRef`를 사용한다.

```yaml
env:
  - name: EMBEDDING_MODEL
    valueFrom:
      configMapKeyRef:
        name: common-embedding-config
        key: EMBEDDING_MODEL
```

## 권장 리소스 초안

| 리소스 | 포함할 설정 |
|---|---|
| `common-system-config` | `TZ`, `LANG`, `LC_ALL` |
| `common-spring-config` | Spring과 Java 공개 설정 |
| `common-python-config` | Python AI 서비스 공개 설정 |
| `common-embedding-config` | 임베딩 모델명, 차원, URL, 배치 설정 |
| `common-model-config` | 모델 클라이언트와 모델 경로 설정 |
| `common-mysql-config` | MySQL 호스트, 포트, 데이터베이스명과 문자셋 |
| `common-kb-config` | Knowledge Base 데이터베이스명과 계정 |
| `common-qdrant-config` | Qdrant 호스트와 공개 설정 |

| Secret | 포함할 값 |
|---|---|
| `common-spring-secret` | JWT, 내부 API 토큰, 관리자 계정 |
| `common-mysql-secret` | MySQL 사용자와 root 비밀번호 |
| `common-kb-secret` | KB 계정 비밀번호와 ingest 토큰 |
| `common-embedding-secret` | 임베딩 API 키 |
| `common-qdrant-secret` | Qdrant API 키 |
| `common-kosha-secret` | KOSHA 서비스 키 |

## Compose와 Kubernetes 주소 매핑

| 역할 | Compose 주소 예시 | Kubernetes 주소 예시 |
|---|---|---|
| Spring | `spring-boot-application:60001` | `spring-service:60001` |
| AI 모델 | `python-ai-model:60100` | `ai-model-service:60100` |
| 임베딩 | `python-embedding-model:60110` | `embedding-service:60110` |
| MySQL | `database-mysql-server:3306` | `mysql-service:3306` |
| Qdrant | `qdrant-server:6333` | `qdrant-service:6333` |

실제 포트와 Service 이름은 각 도메인 디렉터리의 `service.yaml`에서 확인하고,
주소가 여러 설정에 반복될 경우 단일 ConfigMap 키로 통일한다.

## 배포 초안

루트 Kustomization을 적용한다.

```bash
kubectl apply -k kubernetes
```

공통 리소스와 서비스 리소스의 적용 상태를 확인한다.

```bash
kubectl get configmap,secret
kubectl get pods
kubectl get svc
```

## 이후 작업

- Compose 환경 변수를 실제 Kubernetes 환경 변수로 매핑한다.
- Docker 컨테이너 이름을 Kubernetes Service 이름과 포트로 교체한다.
- 공통 Secret의 실제 운영 주입 방식을 정한다.
- 각 도메인 ConfigMap이 필요한 키만 포함하는지 검토한다.
- 공통 설정과 도메인 설정의 중복을 재검토한다.
- StatefulSet, Deployment, Job의 환경 변수 주입 방식과 순서를 문서화한다.
- 매니페스트 검증 후 이 초안을 각 도메인 `README.md`와 동기화한다.
