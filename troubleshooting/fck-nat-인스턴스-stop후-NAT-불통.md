# fck-nat 인스턴스 stop 후 NAT 불통 트러블슈팅

## 일시
2026-03-14

## 증상
- CodeDeploy 배포 실패: `CodeDeploy agent was not able to receive the lifecycle event`
- stg-ec2-spring(10.12.140.228)에서 외부 인터넷 연결 불가
- `apt update`, `curl https://codedeploy.ap-northeast-2.amazonaws.com` 모두 타임아웃

## 환경
- **프라이빗 인스턴스**: stg-ec2-spring (`i-07737316d2c4a6064`, `10.12.140.228`)
- **NAT 인스턴스**: stg-ec2-nat (`i-06d72a692b22890f6`, `10.12.11.110`, fck-nat v1.4.0 AL2023 ARM64)
- **리전**: ap-northeast-2
- **VPC**: `vpc-0b486fb509b5203df` (`10.12.0.0/16`)

## 원인 분석

### AWS 인프라 점검 결과 (모두 정상)

| 항목 | 상태 |
|------|------|
| fck-nat 인스턴스 상태 | running, SourceDestCheck=false |
| EIP 연결 | `43.200.120.58` 정상 연결 |
| 프라이빗 서브넷 라우트 | `0.0.0.0/0` → fck-nat ENI (active) |
| 퍼블릭 서브넷 라우트 | `0.0.0.0/0` → IGW (active) |
| 보안 그룹 | 인바운드: VPC 전체 허용 / 아웃바운드: 전체 허용 |
| NACL | 양쪽 서브넷 전체 허용 |

### 근본 원인: 수동 stop/start로 인한 NAT 규칙 미초기화

CloudTrail 조회 결과:

```
StartInstances  2026-03-13 20:05:54 KST  marcus
StopInstances   2026-03-12 11:48:36 KST  devon
StartInstances  2026-03-11 13:51:49 KST  devon
StopInstances   2026-03-11 10:09:16 KST  devon
StartInstances  2026-03-10 09:34:43 KST  devon
```

- devon이 03-12에 fck-nat 인스턴스를 **stop**, marcus가 03-13에 **start**
- fck-nat AMI는 최초 부팅(cloud-init) 시 iptables MASQUERADE 규칙을 설정
- `stop → start`는 cloud-init이 완전히 재실행되지 않아 NAT 규칙이 누락될 수 있음
- 프라이빗 서브넷의 모든 아웃바운드 트래픽이 fck-nat을 경유하므로 NAT 불통 = 인터넷 전체 불통

## 해결
- fck-nat 인스턴스 **reboot** 실행 → OS 레벨 재시작으로 systemd 서비스가 다시 올라오며 iptables 규칙 복구
- reboot 후 stg-ec2-spring에서 인터넷 연결 정상 확인

## 재발 방지
- NAT 인스턴스는 stop하면 프라이빗 서브넷 전체가 인터넷 불통 → 팀원 공유 필요
- `DisableApiStop` 활성화 또는 IAM 정책으로 NAT 인스턴스 stop 권한 제한 검토
- t4g.micro 기준 월 ~$6 수준이므로 상시 가동 유지 권장
