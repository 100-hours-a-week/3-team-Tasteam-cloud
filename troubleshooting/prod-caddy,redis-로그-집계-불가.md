prod의 spring, caddy, redis 모니터링을 구축하던 중

스프링은 메트릭, 로그 모두 잘 집계되는거 확인. 근데 캐디는 메트릭 로그 다 안 잡히고, 레디스는 메트릭은 잡히는데 로그는 안 잡힘.

## 캐디의 경우
일단 nc -zv 10.10.131.197 3100 9090이 실패. 라우트 테이블에 shared-vpc와의 연결 없음 발견.
루트 추가하니까 바로 메트릭 로그 둘 다 잘 수집됨.

## 레디스의 경우
얼로이의 도커 로그를 보니 
  time="2026-02-26T14:42:36Z" level=error msg="Couldn't connect to redis instance (redis:6379)"
로 도배된 것을 확인

그래서 서로 다른 컴포즈 파일로 인한 네트워크 문제를 확인, host.docker.internal로 고쳤고 반영했더니 얼로이가 레디스를 못 찾는 문제는 해결.
근데 여전히 중앙 로키에서는 로그가 안 뜸.

nc -zv 10.10.131.197 3100 9090은 성공.

curl -X POST -H "Content-Type: application/json" \
  http://10.10.131.197:3100/loki/api/v1/push \
  -d '{
    "streams": [{
      "stream": { "job": "test", "host": "prod-instance" },
      "values": [["'"$(date +%s)"'000000000", "test log from prod instance"]]
    }]
  }'
를 날렸더니 job: test인 로그가 loki에서 집계되는 것도 확인.

네트워크 문제는 아닌 듯.

그럼 뭐지? 왜 {environment="prod", role="redis"}의 결과가 아무것도 안 뜨는 거지?

docker compose up -d를 하면 redis 이름이 충돌된다고 해서 alloy만 재시작해왔는데, 이 부분이 아무래도 찜찜.
웬만하면 clay가 해놓은 부분은 안 건드리려 했는데 AOF 영속화도 된다고 하고, 아직 prod가 실제 서비스 중인 것도 아니라서 그냥 redis 컨테이너 완전 제거하고 docker compose up -d로 재시작함.
얼로이도 재시작.

해결됨. 진즉에 재기동할 걸.