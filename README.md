# Monitoring Stack

A Docker Compose stack for monitoring host and GPU metrics using **Prometheus**, **Grafana**, **NVIDIA DCGM Exporter**, and **Node Exporter**.

## Services & Endpoints

| Service | Endpoint | Description |
| :--- | :--- | :--- |
| **Prometheus** | `http://localhost:9090` | Time-series metrics database (scrapes every 1s) |
| **Grafana** | `http://localhost:3000` | Metrics visualization (`admin` / `admin`) |
| **DCGM Exporter** | `http://localhost:9400/metrics` | NVIDIA GPU metrics exporter |
| **Node Exporter** | `http://localhost:9100/metrics` | System hardware & OS metrics exporter |

*Note: Services run in `network_mode: host`.*

## Prerequisites

Before running the stack, ensure your system meets the following requirements:

1. **NVIDIA GPU & CUDA Driver**: A supported NVIDIA GPU with installed proprietary NVIDIA drivers.
2. **Docker & Docker Compose**: Installed and running daemon.
3. **NVIDIA Container Toolkit**: Required by `dcgm-exporter` to access GPU devices inside containers.
   - Installation guide: [NVIDIA Container Toolkit Docs](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)

### Verification Commands

```bash
# 1. Verify GPU & Driver on host
nvidia-smi

# 2. Verify NVIDIA Container Toolkit / CUDA container support
docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi
```

## Quick Start

```bash
# Start stack
docker compose up -d

# View status / logs
docker compose ps
docker compose logs -f

# Stop stack
docker compose down
```

## Structure

```text
monitoring/
├── docker-compose.yaml
├── .gitignore
├── README.md
└── prometheus/
    └── prometheus.yml
```
