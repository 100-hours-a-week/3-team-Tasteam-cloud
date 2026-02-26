# Alloy 메트릭 전송: pull에서 push(remote_write)로 전환

## 배경

각 서버의 Alloy가 로컬 메트릭(node_exporter, cAdvisor 등)을 수집한 뒤, 중앙 Prometheus로 전송하는 구간의 방식을 결정해야 했다.

## 문제

pull 방식(중앙 Prometheus가 각 Alloy를 scrape)을 사용하려면:

- 각 서버의 Alloy 메트릭 엔드포인트를 **외부에 노출**하고, 보안 그룹에서 인바운드 포트를 개방해야 함
- 서버마다 수집 대상 컴포넌트가 다른데(예: Caddy 서버는 node + cAdvisor + Caddy, Spring 서버는 node + cAdvisor + JVM 등), 이를 중앙 Prometheus에서 **서버별·컴포넌트별로 scrape 설정을 개별 관리**해야 함
- 서버가 늘어나면 이 설정이 비례해서 복잡해짐

반면 push 방식에서는 각 Alloy가 자신이 수집할 대상을 로컬에서 정의하고 전송까지 처리하므로, 중앙 Prometheus는 `remote_write` 수신만 하면 된다.


## push/pull 비교

| | push (remote_write) | pull (중앙 scrape) |
|---|---|---|
| **장점** | 네트워크 구성이 단순 (Alloy가 직접 전송) | 설정 변경 시 중앙 Prometheus만 수정하면 됨 |
| **단점** | 다수의 타겟이 동시에 push하면 서버 부하 가능 | 서버 확장 시 서비스 디스커버리 설정이 복잡해짐 |

## 결정 근거

- `prometheus.remote_write`는 충분히 성숙된 공식 기능이므로, push 방식 채택에 따른 기술적 불이익이 크지 않음
- push의 주요 단점(서버 부하)은 Alloy의 **백프레셔 메커니즘**이 내장되어 있어 완화됨
- 현재 인프라 규모에서는 push 방식의 단순한 네트워크 구성이 더 실용적

## 결론

Alloy → Prometheus 전송 구간을 `prometheus.remote_write`(push) 방식으로 채택.
로컬 메트릭 수집(node_exporter, cAdvisor, Caddy 등)은 Alloy 내부에서 여전히 scrape(pull)로 동작.