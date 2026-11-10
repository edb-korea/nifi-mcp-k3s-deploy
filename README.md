# nifi-mcp-k3s-deploy

k3s(Kubernetes)에 **Apache NiFi 2.11.0**과 **[nifipilot-plus](https://github.com/edb-korea/nifipilot-plus) MCP 서버**를
한 Pod 안의 사이드카로 배포하는 매니페스트와 스크립트입니다. AI 에이전트(Claude 등)가 MCP로 NiFi 플로우를 조회·구성·운영할 수 있게 합니다.

```
┌──────────────────────────── k3s VM ─────────────────────────────┐
│  Pod "nifi" (한 Pod = 같은 localhost)                             │
│   ┌──────────────────┐  https://localhost:8443  ┌──────────────┐ │
│   │ nifi (2.11.0)    │ <──────────────────────  │ mcp (사이드카) │ │
│   │ 8443  UI/API     │                          │ 8000  /mcp   │ │
│   └──────────────────┘                          └──────────────┘ │
│   PVC nifi-data (저장소)      Secret nifi-credentials             │
│   Service nifi (8443)         Service nifi-mcp (8000, ClusterIP)  │
└──────────────────────────────────────────────────────────────────┘
        ▲ kubectl port-forward + SSH 터널로만 접근 (외부에 포트를 열지 않음)
```

## 검증 상태

| 항목 | 상태 |
|---|---|
| 매니페스트 + 스크립트(build/deploy/verify)를 Docker 안의 실제 k3s(v1.34)에 배포 | 통과 |
| 그 NiFi에 port-forward로 접속해 쓰기 도구 포함 59단계 live 테스트 | 통과 (59/59) |
| 사이드카 amd64 이미지 빌드 | 통과 |
| **AWS VM에서의 배포, `push-image.sh`(scp/ssh) 구간** | **미검증: 이 VM에서 처음 실행하게 됩니다** |
| NiFi 1.x, 클러스터, LDAP/OIDC 로그인, Ingress 노출 | 미검증 |

## 사전 준비

**k3s VM**
- 메모리 **8GB 이상 권장**(NiFi 힙 최대 2GB, 컨테이너 한도 4GB). 4GB VM은 OOMKilled 위험이 큽니다. vCPU 2개 이상, 디스크 20GB 이상.
- k3s가 설치되어 있고 `sudo k3s kubectl get nodes`가 `Ready`, `sudo k3s kubectl get sc`에 `local-path (default)`가 있어야 합니다.
- Security Group에서 **SSH(22)만** 열면 됩니다. 8443/8000은 열지 마세요. MCP 엔드포인트에는 인증이 없습니다.
- Red Hat 계열이면 `nm-cloud-setup` 비활성화, firewalld, SELinux(`k3s-selinux`) 확인이 필요합니다. 아래 문제 해결 참고.

**작업 PC**: Docker(buildx 포함), `ssh`/`scp`, [nifipilot-plus](https://github.com/edb-korea/nifipilot-plus) 체크아웃(이 repo와 같은 상위 폴더).

```bash
git clone https://github.com/edb-korea/nifipilot-plus ../nifipilot-plus   # 이 repo 옆에 둡니다
ssh <user>@<vm-ip> uname -m      # x86_64 = amd64, aarch64 = arm64
```

## 배포 순서

### 1. 사이드카 이미지 빌드 (작업 PC)

```bash
./scripts/build-image.sh                        # 기본 linux/amd64
PLATFORM=linux/arm64 ./scripts/build-image.sh   # Graviton(arm64) VM이면
```

`dist/nifipilot-plus_0.1.0-<arch>.tar`가 만들어집니다. Apple Silicon에서 amd64를 빌드하면 에뮬레이션이라 느립니다.

### 2. 이미지와 파일을 VM으로 전달 (작업 PC)

```bash
./scripts/push-image.sh <user>@<vm-ip>                                   # VM 아키텍처에 맞는 tar를 자동 선택
SSH_OPTS="-i ~/.ssh/my-key.pem" ./scripts/push-image.sh <user>@<vm-ip>   # 키 파일을 쓰는 경우
rsync -av --exclude dist --exclude .git ./ <user>@<vm-ip>:~/nifi-mcp-k3s-deploy/
```

이미지는 레지스트리 없이 k3s의 containerd에 직접 임포트합니다(매니페스트는 `imagePullPolicy: IfNotPresent`).

### 3. 배포 (VM)

```bash
ssh <user>@<vm-ip>
cd ~/nifi-mcp-k3s-deploy
KUBECTL="sudo k3s kubectl" ./scripts/deploy.sh
```

비밀번호를 물어봅니다(**12자 이상**, 화면에 표시되지 않음). `NIFI_PASSWORD` 환경변수로 줄 수도 있습니다.
네임스페이스 `nifi`와 Secret을 만들고 매니페스트를 적용한 뒤 NiFi가 준비될 때까지 기다립니다.
**NiFi 이미지(약 1GB)를 받고 첫 기동하는 데 수 분이 걸립니다.**

### 4. 검증 (VM)

```bash
KUBECTL="sudo k3s kubectl" ./scripts/verify.sh
```

컨테이너 2개가 `ready`이고, `tools: 29  mode: readonly`와 `NiFi 2.11.0`이 출력되면 정상입니다.

### 5. 접속

NiFi UI와 MCP 엔드포인트는 클러스터 안에서만 열려 있습니다. VM에서 port-forward하고, 작업 PC에서 SSH 터널로 가져옵니다.

```bash
# VM (각각 별도 터미널)
sudo k3s kubectl -n nifi port-forward svc/nifi 8443:8443
sudo k3s kubectl -n nifi port-forward svc/nifi-mcp 8000:8000

# 작업 PC
ssh -N -L 8443:localhost:8443 -L 8000:localhost:8000 <user>@<vm-ip>
```

- NiFi UI: <https://localhost:8443/nifi> (자체 서명 인증서 경고는 무시, 계정은 `admin` + 위에서 정한 비밀번호)
- 반드시 `localhost:8443`으로 접속하세요. NiFi는 `Host` 헤더를 검사하고 `NIFI_WEB_PROXY_HOST`에 등록된 값만 허용합니다(그 밖의 주소는 400).
- Claude Code에 MCP 연결:

```bash
claude mcp add --transport http nifi http://localhost:8000/mcp
```

## 설정

기본은 **읽기 전용**입니다(쓰기/제어 도구는 등록되지 않아 모델에게 보이지 않음). 사이드카 환경변수는 `manifests/nifi-with-mcp.yaml`의 `mcp` 컨테이너에 있습니다.

| 변수 | 기본값 | 설명 |
|---|---|---|
| `MCP_MODE` | `readonly` | `full`이면 쓰기/제어 도구 37개 추가(총 66개) |
| `MCP_TOOLSETS` | `all` | `core,flow,services,parameters,ports,guides` 중 일부만 노출 |
| `MCP_DRY_RUN` | `false` | `true`면 쓰기 도구가 실행하지 않고 "무엇을 할지"만 보고 |
| `NIFI_VERIFY_SSL` | `false` | NiFi의 자체 서명 인증서 때문에 `false` |

적용된 Deployment를 직접 바꾸는 방법(매니페스트를 고치고 `deploy.sh`를 다시 실행해도 됩니다):

```bash
sudo k3s kubectl -n nifi set env deploy/nifi -c mcp MCP_MODE=full      # 쓰기 도구 켜기
sudo k3s kubectl -n nifi set env deploy/nifi -c mcp MCP_MODE=readonly  # 다시 읽기 전용
```

> `set env`를 쓰면 NiFi도 함께 재시작됩니다(같은 Pod). `full` 모드는 에이전트가 플로우를 삭제·수정할 수 있으므로, 먼저 `MCP_DRY_RUN=true`로 확인하세요.

## 운영

```bash
K="sudo k3s kubectl -n nifi"
$K get pods                                   # 상태 (READY 2/2 가 정상)
$K logs deploy/nifi -c nifi --tail 100        # NiFi 로그
$K logs deploy/nifi -c mcp --tail 100         # MCP 서버 로그
$K exec deploy/nifi -c mcp -- tail -n 20 /tmp/audit.log   # MCP 호출 감사 로그
$K rollout restart deploy/nifi                # 재시작 (비밀번호 변경 후에도 필요)
```

- **비밀번호 변경**: `NIFI_PASSWORD=<새 비밀번호> KUBECTL="sudo k3s kubectl" ./scripts/deploy.sh` 후 `rollout restart deploy/nifi`.
- **NiFi 버전 변경**: `manifests/nifi-with-mcp.yaml`의 `apache/nifi:2.11.0`을 바꾸고 `deploy.sh`를 다시 실행합니다. 2.2.0과 2.11.0만 검증했습니다.
- **데이터**: NiFi의 리포지토리와 state는 PVC(`nifi-data`, 10Gi)에 있습니다. 플로우 정의(`flow.json.gz`)는 emptyDir에 있어서 **컨테이너 재시작에는 남지만 Pod가 새로 만들어지면 사라집니다.** 잃으면 안 되는 플로우는 NiFi Registry나 플로우 내보내기로 따로 보관하세요.
- **삭제**: `./scripts/uninstall.sh`는 배포만 지우고 데이터를 남깁니다. `--purge`는 네임스페이스와 데이터를 모두 지웁니다.

## 문제 해결

| 증상 | 원인과 조치 |
|---|---|
| `mcp` 컨테이너 `ErrImagePull` / `ImagePullBackOff` | 이미지가 containerd에 없음. `push-image.sh`를 다시 실행하고 `sudo k3s ctr images ls \| grep nifipilot-plus`로 확인 |
| `exec format error` | VM과 이미지 아키텍처가 다름. `uname -m`을 확인하고 `PLATFORM`을 맞춰 다시 빌드·전달 |
| `CreateContainerConfigError` | `kubectl describe pod`의 Events 확인. Secret `nifi-credentials`가 없으면 `deploy.sh`를 실행하지 않은 것 |
| `nifi` 컨테이너가 `OOMKilled`로 반복 재시작 | VM 메모리 부족. 8GB 이상으로 올리거나 매니페스트의 `NIFI_JVM_HEAP_MAX`와 메모리 한도를 낮춤 |
| 브라우저에서 `Invalid host header` / 400 | `localhost:8443` 이외의 주소로 접속함. 다른 주소를 쓰려면 `NIFI_WEB_PROXY_HOST`에 `host:port`를 추가 |
| PVC가 `Pending` | `sudo k3s kubectl get sc`에 `local-path`가 있는지, 디스크 여유가 있는지 확인 |
| 첫 기동이 매우 느림 | 정상입니다. 이미지 다운로드와 초기화로 수 분 걸리며 startupProbe가 최대 10분 기다립니다 |
| Pod 안에서 쓰기 오류(Red Hat, SELinux enforcing) | `k3s-selinux` 설치 여부와 `ausearch -m avc -ts recent` 확인 |
| k3s 자체가 올라오지 않거나 Pod 네트워크 불통(Red Hat) | `sudo systemctl disable --now nm-cloud-setup.service nm-cloud-setup.timer` 후 재부팅, firewalld에서 `10.42.0.0/16`, `10.43.0.0/16`을 신뢰 영역에 추가 |

## 보안 주의

- MCP 엔드포인트(8000)에는 **인증이 없습니다.** Service는 ClusterIP이고, 접근은 port-forward와 SSH 터널로만 하세요. NodePort/Ingress/LoadBalancer로 노출하지 마세요.
- NiFi 비밀번호는 Secret에 저장되며 이 repo에는 없습니다. 스크립트가 임시 파일(권한 600)을 쓰고 끝나면 삭제합니다.
- `.gitignore`가 `dist/`, `*.tar`, `.env`를 제외합니다.

## 파일 구성

| 경로 | 역할 |
|---|---|
| `manifests/nifi-with-mcp.yaml` | Namespace, PVC, Deployment(NiFi + MCP 사이드카), Service 2개 |
| `scripts/build-image.sh` | 사이드카 이미지를 빌드해 `dist/*.tar`로 저장 |
| `scripts/push-image.sh` | VM으로 복사하고 k3s containerd에 임포트 |
| `scripts/deploy.sh` | 네임스페이스와 Secret 생성, 매니페스트 적용, 기동 대기 |
| `scripts/verify.sh` | 컨테이너 상태 확인과 사이드카 안에서 MCP 호출 |
| `scripts/uninstall.sh` | 삭제 (`--purge`는 데이터까지) |

## 라이선스

Apache License 2.0. NiFi 이미지는 Apache NiFi 프로젝트의 것이고, MCP 서버는 [nifipilot-plus](https://github.com/edb-korea/nifipilot-plus)입니다.
