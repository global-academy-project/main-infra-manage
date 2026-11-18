# Python AI 모델 파일 배치와 볼륨 복구

## 목적

`python-ai-model` 컨테이너에서 LoRA 어댑터와 안전모델을 사용하기 위한 파일 위치와,
Docker named volume 때문에 파일이 보이지 않을 때의 복구 방법을 설명합니다.

## 필요한 파일

빌드 컨텍스트인 `main-ai-model/adapters/`에 다음 파일이 있어야 합니다.

```text
adapters/
├─ extract/
│  ├─ adapter_config.json
│  └─ adapter_model.safetensors
├─ work_register/
│  ├─ adapter_config.json
│  ├─ adapter_model.safetensors
│  └─ train_meta.json
└─ helmet_nano.onnx
```

`main-ai-model/.dockerignore`의 다음 규칙은 주석 처리해야 합니다.

```dockerignore
# adapters/
```

## Docker 이미지에 포함되는 경로

`main-ai-model/Dockerfile`의 `ai` 스테이지는 다음 경로로 파일을 복사합니다.

```dockerfile
FROM ml-dependencies AS ai

COPY app ./app
COPY adapters/extract/ /models/huggingface/adapters/extract/
COPY adapters/work_register/ /models/huggingface/adapters/work_register/
COPY adapters/helmet_nano.onnx /models/huggingface/yolox/helmet_nano.onnx
```

대상 컨테이너 경로는 다음과 같습니다.

| 원본 빌드 컨텍스트 | 컨테이너 이미지 경로 |
| --- | --- |
| `adapters/extract/` | `/models/huggingface/adapters/extract/` |
| `adapters/work_register/` | `/models/huggingface/adapters/work_register/` |
| `adapters/helmet_nano.onnx` | `/models/huggingface/yolox/helmet_nano.onnx` |

이미지 빌드로 확인합니다.

```powershell
Set-Location C:\projects\org\main-ai-model
docker build --target ai -t main-ai-model:validation .

docker run --rm --entrypoint sh main-ai-model:validation -c "
  test -f /models/huggingface/adapters/extract/adapter_config.json &&
  test -f /models/huggingface/adapters/work_register/adapter_config.json &&
  test -f /models/huggingface/yolox/helmet_nano.onnx &&
  echo MODEL_FILES_OK
"
```

## Compose 볼륨과 환경변수

`docker/docker-compose.yml`의 `python-ai-model`은 `ai-model-cache` named volume을
컨테이너의 `/models/huggingface`에 마운트합니다.

```yaml
environment:
  VISION_MODEL_PATH: /models/huggingface/yolox/yolox_nano.onnx
  VISION_HELMET_MODEL_PATH: /models/huggingface/yolox/helmet_nano.onnx
  LLM_ADAPTERS: '{"extract":"/models/huggingface/adapters/extract","work_register":"/models/huggingface/adapters/work_register"}'

volumes:
  - ai-model-cache:/models/huggingface
```

`/models/huggingface` 전체를 named volume에 마운트하면 볼륨이 이미지의 해당
디렉터리를 덮습니다. 새 볼륨에는 이미지 파일이 처음 복사될 수 있지만, 이미 파일이
있는 기존 볼륨은 새 이미지의 파일로 자동 갱신되지 않습니다.

따라서 다음은 사용하지 않습니다.

```yaml
- ../../main-ai-model/adapters/extract:/models/huggingface/adapters/extract
- ../../main-ai-model/adapters/work_register:/models/huggingface/adapters/work_register
- ../../main-ai-model/adapters/helmet_nano.onnx:/models/huggingface/yolox/helmet_nano.onnx
```

이 경우 호스트 빌드 컨텍스트에 파일이 없어도 Docker가 파일이나 디렉터리 바인드
마운트를 만들거나, 기존 볼륨과 충돌할 수 있습니다.

## 기존 볼륨이 잘못된 경우

컨테이너 내부에 어댑터와 안전모델이 보이지 않는지 먼저 확인합니다.

```powershell
docker exec python-ai-container sh -c "
  test -f /models/huggingface/adapters/extract/adapter_config.json &&
  echo EXTRACT_OK ||
  echo EXTRACT_MISSING

  test -f /models/huggingface/adapters/work_register/adapter_config.json &&
  echo WORK_REGISTER_OK ||
  echo WORK_REGISTER_MISSING

  test -f /models/huggingface/yolox/helmet_nano.onnx &&
  echo HELMET_OK ||
  echo HELMET_MISSING
"
```

이름이 잘못된 볼륨 항목을 확인하고 제거하려면 Compose 설정 검사를 먼저 실행합니다.

```powershell
Set-Location C:\projects\org\main-infra-manage\docker
docker compose config --quiet
```

기존 볼륨에 빈 디렉터리나 오래된 파일이 남은 경우에는 볼륨을 삭제하지 않고
일회성 컨테이너로 필요한 파일만 교체할 수 있습니다.

```powershell
docker stop python-ai-container

docker run -d --name ai-volume-fix `
  --entrypoint sh `
  -v docker_ai-model-cache:/models/huggingface `
  alpine -c "sleep 300"

docker exec ai-volume-fix sh -c "
  rm -rf /models/huggingface/adapters/extract
  rm -rf /models/huggingface/adapters/work_register
  rm -rf /models/huggingface/yolox/helmet_nano.onnx
  mkdir -p /models/huggingface/adapters/extract
  mkdir -p /models/huggingface/adapters/work_register
  mkdir -p /models/huggingface/yolox
"

$cid = docker create docker-python-ai-model

docker cp "${cid}:/models/huggingface/adapters/extract/." ai-volume-fix:/models/huggingface/adapters/extract/
docker cp "${cid}:/models/huggingface/adapters/work_register/." ai-volume-fix:/models/huggingface/adapters/work_register/
docker cp "${cid}:/models/huggingface/yolox/helmet_nano.onnx" ai-volume-fix:/models/huggingface/yolox/helmet_nano.onnx
docker rm $cid

docker exec ai-volume-fix sh -c "
  chown -R 65003:65003 /models/huggingface/adapters
  chown -R 65003:65003 /models/huggingface/yolox
"

docker rm -f ai-volume-fix
```

볼륨 이름은 프로젝트 이름과 디렉터리에 따라 달라질 수 있습니다.
실제 이름은 다음 명령으로 확인합니다.

```powershell
docker inspect python-ai-container --format '{{json .Mounts}}'
docker volume ls
```

## 재빌드와 재생성

파일과 Compose 설정을 반영한 후 컨테이너를 다시 빌드합니다.

```powershell
Set-Location C:\projects\org\main-infra-manage\docker

docker compose config --quiet
docker compose up python-ai-model -d --build --force-recreate
```

재생성 후 확인합니다.

```powershell
docker exec python-ai-container sh -c "
  test -f /models/huggingface/adapters/extract/adapter_config.json && echo EXTRACT_OK
  test -f /models/huggingface/adapters/work_register/adapter_config.json && echo WORK_REGISTER_OK
  test -f /models/huggingface/yolox/helmet_nano.onnx && echo HELMET_OK
  printenv VISION_HELMET_MODEL_PATH
  printenv LLM_ADAPTERS
"

docker compose ps python-ai-model
docker compose logs --tail=100 python-ai-model
docker inspect python-ai-container --format '{{json .State.Health}}'
```

헬스체크가 `starting` 상태에서 끝나지 않고 `healthy`가 되려면 모델 로드와
FastAPI 기동이 모두 완료되어야 합니다.

## 주의 사항

- `down -v`는 `ai-model-cache`를 포함한 named volume을 삭제하므로 일반 재실행에는 사용하지 않습니다.
- 모델 파일을 변경했으면 이미지를 다시 빌드해야 합니다.
- 기존 볼륨을 유지하는 경우 Docker 이미지의 복사만으로 볼륨 내부 파일이 갱신되지 않을 수 있습니다.
- 컨테이너가 root가 아닌 `65003` 사용자로 실행되므로 볼륨의 소유권도 필요합니다.
- 어댑터를 사용하려면 학습에 사용한 기본 모델과 호환되는 어댑터가 있어야 합니다.
