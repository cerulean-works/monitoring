# Monitoring Stack

A Docker Compose stack for host, GPU, and vLLM metrics plus systemd logs using **Prometheus**, **Grafana**, **Loki**, **Grafana Alloy**, **NVIDIA DCGM Exporter**, and **Node Exporter**.

## Services & Endpoints

| Service | Endpoint | Description |
| :--- | :--- | :--- |
| **Prometheus** | `http://localhost:9090` | Time-series metrics database (scrapes every 1s) |
| **Grafana** | `http://localhost:3000` | Metrics visualization (credentials are configured in `.env`) |
| **DCGM Exporter** | `http://dcgm-exporter:9400/metrics` (Compose network only) | NVIDIA GPU metrics exporter |
| **Node Exporter** | `http://node-exporter:9100/metrics` (Compose network only) | Host hardware & OS metrics exporter (via `/proc`, `/sys`, `/` mounts) |
| **Loki** | `http://loki:3100` (Compose network only) | Local log storage; provisioned automatically in Grafana |
| **Grafana Alloy** | Compose service only | Reads systemd journals and sends logs to Loki |

*Note: All services use the isolated Compose bridge network. Only Grafana and Prometheus publish ports, both on host loopback. Exporters, Loki, and Alloy are reachable only by other services in the Compose network.*

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
# Create local configuration files (these files are ignored by Git)
cp .env.example .env
cp prometheus/targets/vllm.yml.example prometheus/targets/vllm.yml

# Edit the Grafana credentials and vLLM target before starting
${EDITOR:-vi} .env
${EDITOR:-vi} prometheus/targets/vllm.yml

# Validate the resolved configuration
docker compose config

# Start stack
docker compose up -d

# View status / logs
docker compose ps
docker compose logs -f

# Stop stack
docker compose down
```

## vLLM and systemd logs

Prometheus scrapes the vLLM `/metrics` endpoint through the `vllm` job in `prometheus/prometheus.yml`. The repository contains only the safe template `prometheus/targets/vllm.yml.example`; your actual target belongs in `prometheus/targets/vllm.yml`, which is ignored by Git. The template uses `host.docker.internal:8000`, mapped to Docker's host gateway by Compose. A vLLM process on the host must listen on an address reachable from containers, such as `0.0.0.0`, rather than only `127.0.0.1`. For a containerized vLLM service attached to the same Compose network, use its service name and port instead.

## Local configuration and public repositories

Do not commit `.env` or files matching `prometheus/targets/*.yml`. They contain deployment-specific values and are intentionally excluded by `.gitignore`. The committed templates are:

| Template | Local file | Configure |
| :--- | :--- | :--- |
| `.env.example` | `.env` | Grafana administrator username and a strong password |
| `prometheus/targets/vllm.yml.example` | `prometheus/targets/vllm.yml` | Reachable vLLM metrics endpoint and optional labels |

After changing either local file, run `docker compose config` to validate Compose settings. Prometheus discovers target-file changes automatically; check `http://localhost:9090/targets` to confirm the vLLM endpoint is healthy.

Grafana automatically provisions both Prometheus and Loki from `grafana/provisioning/datasources/prometheus.yml` during `docker compose up`. No manual data source setup is required. The provisioned data sources use Compose service DNS (`prometheus:9090` and `loki:3100`) and keep internal traffic off the host network.

## Pinned container versions

Every image in `docker-compose.yaml` uses an explicit version tag; no service uses `latest` or an implicit default tag. This prevents routine upstream releases from silently changing the stack during `docker compose pull`.

| Service | Image |
| :--- | :--- |
| DCGM Exporter | `nvcr.io/nvidia/k8s/dcgm-exporter:2.1.4-2.3.1-ubuntu20.04` |
| Node Exporter | `prom/node-exporter:v1.12.1` |
| Prometheus | `prom/prometheus:v3.13.2` |
| Grafana | `grafana/grafana:13.1.2` |
| Loki | `grafana/loki:3.7.0` |
| Alloy | `grafana/alloy:v1.11.3` |

Upgrade versions deliberately: change one tag at a time, run `docker compose pull <service>`, start the stack, and verify health before committing the new tag.

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
docker compose exec grafana wget -qO- http://loki:3100/ready
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
├── .env.example
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
├── alloy/
│   └── config.alloy
├── loki/
│   └── loki-config.yaml
└── prometheus/
    ├── prometheus.yml
    └── targets/
        └── vllm.yml.example
```
