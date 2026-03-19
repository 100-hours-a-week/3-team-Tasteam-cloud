#!/usr/bin/env bash
set -euo pipefail
exec > >(tee /var/log/k8s-bootstrap.log) 2>&1

AWS_REGION="${aws_region}"
ENVIRONMENT="${environment}"

# ── IMDSv2 토큰 발급 (http_tokens=required 이므로 필수) ──
IMDS_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds:21600")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $${IMDS_TOKEN}" \
  http://169.254.169.254/latest/meta-data/instance-id)

# ── 호스트네임 설정 ──
hostnamectl set-hostname "$${ENVIRONMENT}-ec2-k8s-worker-$${INSTANCE_ID}"

# ── 타임존/NTP ──
timedatectl set-timezone Asia/Seoul
timedatectl set-ntp true

# ── swap 비활성화 ──
swapoff -a
sed -i.bak '/ swap / s/^/#/' /etc/fstab

# ── 패키지 설치 ──
apt-get update
apt-get install -y \
  apt-transport-https ca-certificates curl gnupg unzip \
  jq socat conntrack ebtables ethtool containerd

# ── AWS CLI v2 설치 ──
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install
rm -rf /tmp/awscliv2.zip /tmp/aws

# ── 커널 모듈 / sysctl ──
cat <<MOD > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
MOD
modprobe overlay
modprobe br_netfilter

cat <<SYS > /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
SYS
sysctl --system

# ── containerd 설정 ──
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable --now containerd

# ── kubeadm/kubelet/kubectl 설치 ──
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' \
  > /etc/apt/sources.list.d/kubernetes.list

apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable kubelet

# ── SSM 에서 join 정보 읽기 ──
JOIN_TOKEN=$(/usr/local/bin/aws ssm get-parameter \
  --region "$${AWS_REGION}" \
  --name "/$${ENVIRONMENT}/tasteam/k8s/join-token" \
  --with-decryption \
  --query 'Parameter.Value' --output text)

CA_CERT_HASH=$(/usr/local/bin/aws ssm get-parameter \
  --region "$${AWS_REGION}" \
  --name "/$${ENVIRONMENT}/tasteam/k8s/ca-cert-hash" \
  --query 'Parameter.Value' --output text)

API_ENDPOINT=$(/usr/local/bin/aws ssm get-parameter \
  --region "$${AWS_REGION}" \
  --name "/$${ENVIRONMENT}/tasteam/k8s/api-endpoint" \
  --query 'Parameter.Value' --output text)

# ── kubeadm join (worker 레이블 자동 부여) ──
NODE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $${IMDS_TOKEN}" \
  http://169.254.169.254/latest/meta-data/local-ipv4)

cat <<JOINEOF > /tmp/kubeadm-join.yaml
apiVersion: kubeadm.k8s.io/v1beta4
kind: JoinConfiguration
discovery:
  bootstrapToken:
    apiServerEndpoint: "$${API_ENDPOINT}:6443"
    token: "$${JOIN_TOKEN}"
    caCertHashes:
      - "sha256:$${CA_CERT_HASH}"
nodeRegistration:
  criSocket: unix:///run/containerd/containerd.sock
  kubeletExtraArgs:
    - name: node-ip
      value: "$${NODE_IP}"
JOINEOF

kubeadm join --config /tmp/kubeadm-join.yaml

echo "kubeadm join completed at $(date)"
