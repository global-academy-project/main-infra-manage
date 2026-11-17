#### 10/23/2026 PM 23:00
- 작업자가 코드를 변경하고 Commit 이후 Push할 경우 Actions가 GitHub API를 통해 Location을 조회하지 않도록 변경
- Pull Request Template Body에 작업된 Commit SHA-256이 자동으로 작성되도록 개선

#### 10/23/2026 PM 23:30
- 앞으로 코드 변경, 문서 파일 추가 등 해당 파일 타입 혹은 브런치 이름에 따라 PR에 붙는 라벨의 종류가 다르게 Actions가 적용 하도록 변경 됐습니다.
- 작업자의 수동 라벨 부여 방식을 대응하는 목적으로 적용하는 범위는 "document" "enhancement" "refactor" "bug" "release" 으로 이후 분기 처리 거쳐 feature/**, hotfix 등 특정 브런치로 오픈할 경우 부여되도록 개선할 예정입니다.

#### 10/24/2026 AM 09:06
- PR Body내 SHA Hash값이 적용됨과 동시에 작업자의 커밋 메시지가 함께 조회되어 한줄에 같이 추가 되도록 개선

#### 10/24/2026 AM 09:55
- PR Open으로 Assignees에서 사용자를 Actions Bot이 추가 하도록 기능이 추가 됐습니다.
    - 이 업데이트는 작업자의 수동 작업의 범위를 좁히는 데 필요한 기능이기에 조금 더 쉬운 로그 추적이 가능해 집니다.

# MySQL Kubernetes 변경 내역

#### 2026-11-17 PM 22:34

#### 추가
- `mysql-client-data` PVC를 Kustomize 리소스에 포함해 StatefulSet의 MySQL 데이터 볼륨을 함께 배포하도록 구성.
- `db/init`의 초기화 스크립트와 `db/verify`의 검증 파일을 ConfigMap으로 생성하도록 Kustomize generator를 추가.
- StatefulSet에서 MySQL 초기화 스크립트와 검증 파일을 각각 읽기 전용으로 마운트.
- Flyway Job에 MySQL 준비 확인용 init container를 추가. `kb_owner` 계정으로 `agent_kb`에 접속해 쿼리가 성공한 뒤 Flyway를 시작하며, 최대 5분 대기.

##### 수정
- MySQL 시작 옵션을 Pod 수준의 잘못된 `command` 설정 대신 컨테이너의 `args`로 전달해 이미지의 초기화 ENTRYPOINT를 유지.
- MySQL 컨테이너에 주입되는 ConfigMap에서 `MYSQL_HOST` 설정을 비활성화. 컨테이너 내부 초기화 스크립트가 로컬 MySQL socket으로 접속하도록 함. Kubernetes에서 실행하는 애플리케이션은 `mysql-service:3306`을 사용.
- 초기화·검증 파일을 PVC 데이터 디렉터리와 분리해 ConfigMap 볼륨으로 제공.

#### 검증 및 적용 참고
- `kubectl kustomize kubernetes/mysql` 렌더링 성공.
- StatefulSet 단일 리소스의 서버 dry-run 검증 성공.
- Job Pod 템플릿은 생성 후 수정할 수 없으므로 변경된 Job 매니페스트를 적용할 때 기존 `kb-init` Job을 삭제한 후 다시 생성해야 함.
- MySQL 초기화 스크립트는 데이터 디렉터리가 비어 있을 때만 자동 실행됨. 기존 PVC에 대해 재실행할 때는 스크립트를 별도로 실행하고 결과를 확인해야 함.