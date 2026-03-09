# stg 스프링 서버 디스크 100% - Docker 컨테이너 로그

## 문제 상황
stg 환경에서 디스크 사용률 100%로 서버 용량이 꽉 참.

### 발생 시점
- 2026-03-09

### 서버 상태
```
$ df -h
Filesystem  Size  Used Avail Use% Mounted on
/dev/root    20G   20G     0 100% /
```

## 원인 분석

### 조사 과정
1. `/var/log` 확인 → 201MB (용의자 아님)
2. `docker system df` 확인 → 이미지 1.7GB, 컨테이너 3.9MB (표면적으로는 정상)
3. `sudo du -h --max-depth=2 /` → `/var/lib` 18GB 차지 확인
4. `/var/lib/docker/*` glob 확장 실패 → 권한 문제 (`sudo bash -c`로 우회)
5. `/var/lib/docker/containers` = 14GB 확인
6. 특정 컨테이너(Spring BE) 로그 파일 1개 = **14GB**

### 직접 원인
Docker 기본 로그 드라이버(`json-file`)에 로그 로테이션 미설정.
Spring 앱의 stdout 로그가 Docker 컨테이너 로그 파일(`*-json.log`)에 무제한으로 쌓임.

```
$ sudo bash -c 'ls -lh /var/lib/docker/containers/*/*-json.log'
-rw-r----- 1 root root  14G Mar  9 13:54 .../fda94d6b...-json.log  ← Spring BE
-rw-r----- 1 root root  20K Mar  9 13:55 .../a327f573...-json.log  ← Grafana Alloy
```

### 참고
- `docker system df`는 컨테이너 로그 크기를 포함하지 않아 표면적으로 정상으로 보임
- `/var/lib/docker/`는 일반 유저 권한으로 접근 불가하여 `du`로 직접 확인 시 누락됨
- `sudo du -sh /var/lib/docker/*`도 glob이 sudo 전에 현재 유저 권한으로 확장되어 실패 → `sudo bash -c 'du -sh /var/lib/docker/*'`로 우회 필요

## 해결

### 즉시 조치
로그 파일 truncate로 14GB 확보 (컨테이너 재시작 불필요):
```bash
sudo truncate -s 0 /var/lib/docker/containers/fda94d6b6efd07c39c70c9132ed8d9a97d09d17ea42e0de0ab24c4a322fa271d/fda94d6b6efd07c39c70c9132ed8d9a97d09d17ea42e0de0ab24c4a322fa271d-json.log
```

### 재발 방지
`docker-compose.yml`에 컨테이너별 로그 로테이션 설정 추가:
```yaml
services:
  backend:
    logging:
      driver: json-file
      options:
        max-size: "100m"
        max-file: "3"
```

- 컨테이너당 로그 최대 100MB × 3파일 = 300MB로 제한
- Docker 재시작 없이 컨테이너 재생성(`docker compose up -d`)만으로 적용
- 인프라 코드로 관리되어 재현성 확보
