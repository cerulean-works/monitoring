# Monitoring Stack

A Docker Compose stack for host, GPU, and vLLM metrics plus systemd logs using **Prometheus**, **Grafana**, **Loki**, **Grafana Alloy**, **NVIDIA DCGM Exporter**, and **Node Exporter**.

## Services & Endpoints

| Service | Endpoint | Description |
| :--- | :--- | :--- |
| **Prometheus** | `http://localhost:9090` | Time-series metrics database (scrapes every 1s) |
| **Grafana** | `http://localhost:3000` | Metrics visualization (`admin` / `admin`) |
| **DCGM Exporter** | `http://localhost:9400/metrics` | NVIDIA GPU metrics exporter |
| **Node Exporter** | `http://localhost:9100/metrics` | Host hardware & OS metrics exporter (via `/proc`, `/sys`, `/` mounts) |
| **Loki** | `http://localhost:3100/ready` | Local log storage |
| **Grafana Alloy** | Compose service only | Reads systemd journals and sends logs to Loki |

*Note: Metrics services and Grafana use host networking; Loki and Alloy use the Compose network. Loki is published only on host loopback.*

## Prerequisites

Before running the stack, ensure your system meets the following requirements:

1. **NVIDIA GPU & CUDA Driver**: A supported NVIDIA GPU with installed proprietary NVIDIA drivers.
2. **Docker & Docker Compose**: Installed and running daemon.
3. **NVIDIA Container Toolkit**: Required by `dcgm-exporter` to access GPU devices inside containers.
   - Installation guide: [NVIDIA Container Toolkit Docs](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
4. **Disable Host Node Exporter (If Applicable)**: If `node_exporter` was running natively via `systemd`, stop and disable it to avoid port 9100 conflict:
   ```bash
   sudo systemctl stop node_exporter
   sudo systemctl disable node_exporter
   ```

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

## vLLM and systemd logs

Prometheus scrapes the vLLM `/metrics` endpoint configured by the `vllm-qwen` job in `prometheus/prometheus.yml`. Update that target for your vLLM server.

Alloy reads persistent and runtime journals and labels entries with their systemd `unit`. In Grafana, open **Explore**, choose **Loki**, then query:

```logql
{job="systemd-journal"}
{job="systemd-journal", unit="vllm.service"}
{job="systemd-journal", unit=~"vllm.*"} |= "ERROR"
```

Replace `vllm.service` with the actual service unit. If vLLM runs in Docker, configure Docker's `journald` logging driver or add a Docker log source to Alloy.

Verify the pipeline with:

```bash
docker compose config
docker compose up -d
curl -fsS http://localhost:3100/ready
docker compose logs alloy loki
```

## Grafana Startup Notes & Optimizations

### Why Initial Startup Takes Time
On the initial start of the Docker stack or after running `docker compose down -v` (which removes persistent volumes), Grafana takes approximately 5–15 seconds to complete its initial setup:
1. **SQLite Database Initialization & Migrations**: Creating initial database schemas and executing migrations in `grafana.db`.
2. **Automatic Provisioning**: Scanning and importing provisioned data sources (Prometheus) and JSON dashboards.
3. **Service Initialization**: Starting the alerting engine, plugin loader, and HTTP server.

### Applied Optimizations & Solutions
To accelerate Grafana's startup process and provide status visibility, the following configurations are included in [`docker-compose.yaml`](file:///srv/monitoring/docker-compose.yaml):

1. **Disabled Online Reporting & Update Checks**:
   - `GF_ANALYTICS_REPORTING_ENABLED=false`
   - `GF_ANALYTICS_CHECK_FOR_UPDATES=false`
2. **Docker Healthcheck Probe**:
   - Monitored via `/api/health`. Check status via `docker compose ps`:
     - `Up (health: starting)`: Initializing database and services.
     - `Up (healthy)`: Ready to accept requests at `http://localhost:3000`.
3. **Data Persistence**:
   - Stop the stack using `docker compose down` (**avoid using `-v`**). Subsequent launches reuse the initialized database and reach readiness in just a few seconds.

## Structure

```text
monitoring/
├── docker-compose.yaml
├── .gitignore
├── README.md
├── grafana/
│   ├── dashboards/
│   │   ├── 23382_rev1.json
│   │   └── 24784_rev1.json
│   └── provisioning/
│       ├── dashboards/
│       │   └── default.yml
│       └── datasources/
│           └── prometheus.yml
└── prometheus/
    └── prometheus.yml
```
