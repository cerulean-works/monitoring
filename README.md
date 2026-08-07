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

## Quick Start

### Prerequisites
- Docker & Docker Compose
- NVIDIA GPU Driver & NVIDIA Container Toolkit

### Commands

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
