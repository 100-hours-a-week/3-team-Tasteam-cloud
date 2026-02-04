#!/bin/bash

echo "=== Loki Ready ==="
curl http://localhost:3100/ready

echo -e "\n=== Prometheus Healthy ==="
curl http://localhost:9090/-/healthy

echo -e "\n=== Grafana Health ==="
curl http://localhost:3000/api/health

echo -e "\n=== Container Status ==="
docker compose ps
