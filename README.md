# Monitoring Stack

A Docker Compose stack for host and process metrics, optional GPU and vLLM metrics, and optional vLLM systemd logs using **Prometheus**, **Grafana**, **Loki**, **Grafana Alloy**, **NVIDIA DCGM Exporter**, **Node Exporter**, and **process-exporter**. The default mode collects host and process metrics without a GPU or journal access. GPU monitoring and vLLM log collection can be enabled independently.

## Services & Endpoints

| Service | Endpoint | Description |
| :--- | :--- | :--- |
| **Prometheus** | `http://localhost:9090` | Time-series metrics database (scrapes every 1s) |
| **Grafana** | `http://localhost:3000` | Metrics visualization (credentials are configured in `.env`) |
| **DCGM Exporter** (GPU mode only) | `http://dcgm-exporter:9400/metrics` (Compose network only) | NVIDIA GPU metrics exporter |
| **Node Exporter** | `http://node-exporter:9100/metrics` (Compose network only) | Host hardware & OS metrics exporter (via `/proc`, `/sys`, `/` mounts) |
| **process-exporter** | `http://process-exporter:9256/metrics` (Compose network only) | Host process groups: CPU, memory, disk I/O, threads, and file descriptors |
| **Loki** (logs enabled only) | `http://loki:3100` (Compose network only) | Local log storage; provisioned automatically in Grafana when enabled |
| **Grafana Alloy** (logs enabled only) | Compose service only | Reads vLLM systemd journal entries and sends them to Loki |

*Note: All services use the isolated Compose bridge network. Only Grafana and Prometheus publish ports, both on host loopback. Exporters, Loki, and Alloy are reachable only by other services in the Compose network.*

## Prerequisites

Before running the stack, ensure your system meets the following requirements:

1. **Linux host**: Host monitoring uses Linux `/proc`, `/sys`, and `/` mounts. Optional journal collection additionally uses systemd journal paths and `/etc/machine-id`.
2. **Docker & Docker Compose**: Installed and running daemon. No GPU is required for the default mode.
3. **NVIDIA GPU, driver, and Container Toolkit (GPU mode only)**: A supported NVIDIA GPU with installed proprietary NVIDIA drivers. The NVIDIA Container Toolkit is required by `dcgm-exporter` to access GPU devices inside containers.
   - Installation guide: [NVIDIA Container Toolkit Docs](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
4. **systemd-managed vLLM (optional, for the vLLM dashboard log panel)**: Run vLLM as either a system service or a user service, and include `vllm` in the unit name (for example, `vllm.service` or `vllm-qwen.service`). The dashboard discovers matching units automatically and does not require a fixed unit name. Metrics monitoring still works if vLLM is started another way, but the systemd log panel will have no matching logs. Host monitoring does not require vLLM.
   - System service: install the unit under `/etc/systemd/system/`, then enable and start it with `sudo systemctl enable --now <unit>.service`.
   - User service: install the unit under `~/.config/systemd/user/`, then enable and start it with `systemctl --user enable --now <unit>.service`. On a headless host where the service must start at boot and continue after logout, enable lingering with `sudo loginctl enable-linger "$USER"`.
   - Alloy reads the host journals mounted from `/var/log/journal` and `/run/log/journal`. Ensure journald is retaining the vLLM service logs in one of those locations.

### Verification Commands

These checks apply only to GPU mode; skip them on servers without a GPU.

```bash
# 1. Verify GPU & Driver on host
nvidia-smi

# 2. Verify NVIDIA Container Toolkit / CUDA container support
docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi
```

## Quick Start

### Without a GPU (default)

```bash
# Create local credentials (this file is ignored by Git)
cp .env.example .env

# Set the Grafana credentials before starting
${EDITOR:-vi} .env

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

This starts Node Exporter, process-exporter, Prometheus, and Grafana. Open Grafana's **Node Exporter Dashboard** for host metrics or **Process Monitoring** for process-group metrics. DCGM Exporter, its Prometheus scrape job, Loki, and Alloy are absent in this mode; no host journals are mounted or collected. GPU dashboards remain provisioned and show no current GPU data. vLLM metrics panels require a configured vLLM endpoint, and log panels require log collection to be enabled separately.

### With an NVIDIA GPU

Complete the credential setup above, then uncomment the following line in `.env`:

```dotenv
COMPOSE_FILE=docker-compose.yaml:docker-compose.gpu.yaml
```

Run the same commands for configuration validation and startup:

```bash
docker compose config
docker compose up -d
```

The GPU override adds DCGM Exporter with its NVIDIA device reservation and mounts `prometheus/gpu.yml` as an additional scrape configuration. Prometheus loads it through [`scrape_config_files`](https://prometheus.io/docs/prometheus/latest/configuration/configuration/), keeping the host-monitoring configuration shared between both modes. The `.env` setting also applies to `ps`, `logs`, and `down`. Alternatively, supply `-f docker-compose.yaml -f docker-compose.gpu.yaml` to each Compose command, as described in the [Compose merge documentation](https://docs.docker.com/compose/how-tos/multiple-compose-files/merge/).

**Existing GPU deployments:** enable this setting before the first `docker compose up -d` after updating, since GPU monitoring is now opt-in.

### Optional vLLM log collection

Log collection is **off by default**, including in GPU mode. To enable it, select exactly one active `COMPOSE_FILE` line in `.env`:

| Features | `COMPOSE_FILE` value |
| :--- | :--- |
| Host metrics only | Leave `COMPOSE_FILE` commented out |
| Host + GPU metrics | `docker-compose.yaml:docker-compose.gpu.yaml` |
| Host metrics + vLLM logs | `docker-compose.yaml:docker-compose.logs.yaml` |
| Host + GPU metrics + vLLM logs | `docker-compose.yaml:docker-compose.gpu.yaml:docker-compose.logs.yaml` |

Then apply the selection:

```bash
docker compose config
docker compose up -d --remove-orphans
```

The logs override starts Loki and Alloy, mounts the host journals, and provisions the Loki data source in Grafana. Alloy forwards only entries whose system or user systemd unit name contains `vllm` (case-insensitive). Other units are discarded before forwarding. vLLM metrics collection does not require this override.

**Existing log-enabled deployments:** include `docker-compose.logs.yaml` in `COMPOSE_FILE` to retain log collection after updating.

### Disabling optional features

Remove `docker-compose.logs.yaml` from `COMPOSE_FILE` to stop log collection, remove `docker-compose.gpu.yaml` to stop GPU monitoring, or comment out the line to return to host metrics only. Unset `COMPOSE_FILE` in your shell if it overrides `.env`, then run `docker compose up -d --remove-orphans`.

The command removes disabled services. When logs are disabled, Grafana loads `loki-disabled.yml` instead of the enabled Loki provisioning file, removing the previous Loki data source. Stored logs remain in the `loki-data` volume but are unavailable in Grafana until logs are re-enabled. Metrics, dashboards, Alloy journal positions, and stored log volumes are retained. Avoid `down -v`, which deletes volumes belonging to the selected configuration.

### Verify the selected mode

```bash
docker compose config --services
docker compose ps
# Prometheus targets: http://localhost:9090/targets
```

The default configuration lists four services. GPU monitoring adds one (`dcgm-exporter`); log collection adds two (`loki` and `alloy`). On the Prometheus targets page, `node_exporter` and `process_exporter` should become healthy in every mode and `dcgm_exporter` should appear only in GPU mode. Grafana's Loki data source appears only when logs are enabled.

## Process monitoring

[process-exporter](https://github.com/ncabatoff/process-exporter) is included in every mode and scraped through `process-exporter:9256` every second. It reads the Linux host's `/proc` through a read-only mount, uses the host PID namespace, and runs as root with `SYS_PTRACE` to read process counters across users. It does not publish a host port. On Docker Desktop or OrbStack, these are the Docker Linux VM's processes, rather than native macOS processes.

For an existing deployment, start the new service and restart Prometheus to load the added scrape job:

```bash
docker compose up -d
docker compose restart prometheus
```

The default `process-exporter/config.yml` groups matching processes by `{{.Comm}}`, the process name (up to 15 characters). Programs with the same name share a group; Python applications therefore commonly appear together. To identify vLLM separately, place a matching rule before the fallback:

```yaml
process_names:
  - name: vllm
    cmdline:
      - '(?i)vllm'
  - name: "{{.Comm}}"
    cmdline:
      - '.+'
```

The first matching rule wins. Adjust the matcher to your service's command line, then apply configuration changes with:

```bash
docker compose up -d --force-recreate process-exporter
```

Open Grafana's **Process Monitoring** dashboard and select an instance and process group. The dashboard includes CPU, resident memory, disk reads/writes, process and thread counts, file descriptors, and thread states. CPU usage of 100% represents one CPU core; groups can exceed 100%. Resident memory totals can count shared pages more than once.

Per-thread-name metrics and `smaps` collection are disabled to reduce collection cost. Group thread counts and resident memory remain available. Enable `--threads=true` or `--gather-smaps=true` in Compose if the additional detail is needed. Avoid group names containing PIDs or full command lines, which create many distinct metric series.

Verify collection in Prometheus with:

```promql
up{job="process_exporter"}
namedprocess_namegroup_num_procs{job="process_exporter"}
sum by (groupname) (rate(namedprocess_namegroup_cpu_seconds_total{job="process_exporter"}[1m]))
namedprocess_namegroup_memory_bytes{job="process_exporter",memtype="resident"}
```

An `up` value of `1` confirms HTTP scraping. Also inspect `namedprocess_scrape_errors`, `namedprocess_scrape_procread_errors`, and `namedprocess_scrape_partial_errors`: restricted `/proc` access can leave some process fields unavailable even when the target is healthy.

## vLLM and systemd logs

vLLM monitoring is optional in both modes. If you have a reachable vLLM endpoint, create and edit its local target file:

```bash
cp prometheus/targets/vllm.yml.example prometheus/targets/vllm.yml
${EDITOR:-vi} prometheus/targets/vllm.yml
```

Prometheus scrapes the vLLM `/metrics` endpoint through the `vllm` job in `prometheus/prometheus.yml`. The repository contains only the safe template `prometheus/targets/vllm.yml.example`; your actual target belongs in `prometheus/targets/vllm.yml`, which is ignored by Git. The template uses `host.docker.internal:8000`, mapped to Docker's host gateway by Compose. A vLLM process on the host must listen on an address reachable from containers, such as `0.0.0.0`, rather than only `127.0.0.1`. For a containerized vLLM service attached to the same Compose network, use its service name and port instead.

## Local configuration and public repositories

Do not commit `.env` or files matching `prometheus/targets/*.yml`. They contain deployment-specific values and are intentionally excluded by `.gitignore`. The committed templates are:

| Template | Local file | Configure |
| :--- | :--- | :--- |
| `.env.example` | `.env` | Grafana credentials, Prometheus retention, optional host data directories, and feature selection |
| `prometheus/targets/vllm.yml.example` | `prometheus/targets/vllm.yml` | Reachable vLLM metrics endpoint and optional labels |

After changing either local file, run `docker compose config` to validate Compose settings. Prometheus discovers target-file changes automatically; check `http://localhost:9090/targets` to confirm the vLLM endpoint is healthy.

Grafana automatically provisions Prometheus from `grafana/provisioning/datasources/prometheus.yml`. When logs are enabled, the logs override additionally mounts `grafana/provisioning/optional/loki.yml` to provision Loki. No manual data source setup is required. The provisioned data sources use Compose service DNS (`prometheus:9090` and `loki:3100`) and keep internal traffic off the host network.

## Retention and data locations

Prometheus now retains metrics for **180 days (approximately six months)** by default. Set `PROMETHEUS_RETENTION_TIME` to another supported duration, such as `90d` or `365d`, if needed. This is a rolling duration, not six calendar months. The setting controls Prometheus metrics retention and is applied when the container starts. It cannot restore samples that were already deleted. Allow enough disk space for the selected duration; no storage-size retention limit is configured. See the [Prometheus storage documentation](https://prometheus.io/docs/prometheus/latest/storage/).

The following settings work in `.env` or in the environment of the process executing `docker compose`. Exported environment variables take precedence; `.env` is optional.

| Variable | Default | Container data directory |
| :--- | :--- | :--- |
| `PROMETHEUS_RETENTION_TIME` | `180d` | Retention duration |
| `MONITORING_DATA_DIR` | Unset; retain named volumes | Common host parent directory |
| `PROMETHEUS_DATA_DIR` | Named volume `prometheus-data` | `/prometheus` |
| `GRAFANA_DATA_DIR` | Named volume `grafana-storage` | `/var/lib/grafana` |
| `LOKI_DATA_DIR` | Named volume `loki-data` | `/loki` |
| `ALLOY_DATA_DIR` | Named volume `alloy-data` | `/var/lib/alloy/data` |

Set **`MONITORING_DATA_DIR=/data`** to store all service data under one absolute host parent directory:

```text
/data/
├── prometheus-data/
├── grafana-storage/
├── loki-data/        # when log collection is enabled
└── alloy-data/       # when log collection is enabled
```

Each service resolves its storage in this order: a nonempty per-service `*_DATA_DIR` override, its subdirectory under a nonempty `MONITORING_DATA_DIR`, or its original named volume if both settings are unset/empty. For example, `PROMETHEUS_DATA_DIR=/fast-disk/prometheus` overrides only Prometheus while the other services continue using `/data`. Clear old per-service overrides if all data should follow the parent directory. On Docker Desktop or OrbStack, the Docker engine must be able to access the selected host directories.

Prepare writable directories before selecting them. For the pinned images, the following Linux commands create directories owned by the corresponding service users:

```bash
sudo install -d -m 0750 -o 65534 -g 65534 /data/prometheus-data
sudo install -d -m 0750 -o 472 -g 0 /data/grafana-storage
# Only needed when log collection is enabled
sudo install -d -m 0750 -o 10001 -g 0 /data/loki-data
sudo install -d -m 0750 -o 0 -g 0 /data/alloy-data
```

For a new deployment with environment variables only, set the Grafana credentials and desired storage settings, then start the stack:

```bash
export GRAFANA_ADMIN_USER='admin'
export GRAFANA_ADMIN_PASSWORD='replace-with-a-strong-password'
export PROMETHEUS_RETENTION_TIME=180d
export MONITORING_DATA_DIR=/data

docker compose config --quiet
docker compose up -d
```

Changing `PROMETHEUS_RETENTION_TIME` requires `docker compose up -d` to recreate Prometheus with its updated command; `restart` alone does not apply a changed Compose command or mount. Confirm the effective duration in Prometheus at **Status > Command-Line Flags**, under `storage.tsdb.retention.time`.

### Moving existing history

Changing the parent or a per-service data path selects different storage; it does **not** copy the old volume. For an existing deployment, stop the stack with its current storage settings before changing the variables:

```bash
docker compose down
```

Prepare the destination directories as above. To move Prometheus history from the default volume, confirm `docker volume inspect prometheus-data` succeeds, then copy it to an empty destination while Prometheus is stopped:

```bash
docker run --rm --user 0:0 \
  --mount type=volume,source=prometheus-data,target=/from,readonly \
  --mount type=bind,source=/data/prometheus-data,target=/to \
  --entrypoint /bin/sh prom/prometheus:v3.13.2 \
  -c 'test -z "$(ls -A /to)" && cp -a /from/. /to/'
```

The command preserves ownership and copies the complete database, including WAL files; it leaves the source volume intact and refuses a nonempty destination. Copy `grafana-storage`, `loki-data`, and `alloy-data` to their corresponding directories in the same way if changing those locations. Then set the chosen path variables and run `docker compose up -d`. Verify historical queries and keep the original volumes until the copied data is confirmed. Reverting a path variable later selects the old volume and its older contents; it does not merge data from both locations.

Container, Docker, or host restarts retain data when the same storage is reused. `docker compose down` retains named volumes; `down -v` removes declared named volumes. Host bind-directory contents remain on disk after container removal. Configuration and provisioned dashboard files continue to come from the repository.

## Pinned container versions

Every image in `docker-compose.yaml`, `docker-compose.gpu.yaml`, and `docker-compose.logs.yaml` uses an explicit version tag; no service uses `latest` or an implicit default tag. This prevents routine upstream releases from silently changing the stack during `docker compose pull`.

| Service | Image |
| :--- | :--- |
| DCGM Exporter | `nvcr.io/nvidia/k8s/dcgm-exporter:2.1.4-2.3.1-ubuntu20.04` |
| Node Exporter | `prom/node-exporter:v1.12.1` |
| process-exporter | `ncabatoff/process-exporter:0.8.7` |
| Prometheus | `prom/prometheus:v3.13.2` |
| Grafana | `grafana/grafana:13.1.2` |
| Loki | `grafana/loki:3.7.0` |
| Alloy | `grafana/alloy:v1.11.3` |

Upgrade versions deliberately: change one tag at a time, run `docker compose pull <service>`, start the stack, and verify health before committing the new tag.

With log collection enabled, Alloy reads persistent and runtime journals, labels entries from both system services and user services with their systemd `unit`, and keeps only units whose names contain `vllm`. The vLLM dashboard's **Log unit** selector automatically lists matching units and selects all matches by default. In Grafana, open **Explore**, choose **Loki**, then query:

```logql
{job="systemd-journal"}
{job="systemd-journal", unit="vllm.service"}
{job="systemd-journal", unit=~"vllm.*"} |= "ERROR"
```

Replace `vllm.service` with the actual service unit. If vLLM runs in Docker, configure Docker's `journald` logging driver or add a Docker log source to Alloy.

After enabling `docker-compose.logs.yaml` in `.env`, verify the pipeline with:

```bash
docker compose config
docker compose up -d
docker compose exec grafana wget -qO- http://loki:3100/ready
docker compose logs alloy loki
```

## Grafana Startup Notes & Optimizations

### Why Initial Startup Takes Time
On the initial start of the Docker stack or after running `docker compose down -v` (which removes persistent volumes), Grafana can take a relatively long time to complete its initial setup. The exact duration depends on host and storage performance:
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
3. **Prometheus Startup Visibility**:
   - Prometheus scrapes Grafana's `/metrics` endpoint every second through the `grafana` job.
   - Open `http://localhost:9090/graph` and query `up{job="grafana"}`. A value of `0` means Grafana is not ready or unreachable; `1` confirms that Grafana has finished starting and is responding to Prometheus.

4. **Data Persistence**:
   - Stop the stack using `docker compose down` (**avoid using `-v`**). Subsequent launches reuse the initialized database and reach readiness in just a few seconds.

## Structure

```text
monitoring/
├── .env.example
├── docker-compose.yaml
├── docker-compose.gpu.yaml
├── docker-compose.logs.yaml
├── .gitignore
├── README.md
├── grafana/
│   ├── dashboards/
│   │   ├── 23382_rev1.json
│   │   ├── 24784_rev1.json
│   │   ├── process-monitoring.json
│   │   └── vllm-comprehensive.json
│   └── provisioning/
│       ├── dashboards/
│       │   └── default.yml
│       ├── datasources/
│       │   └── prometheus.yml
│       └── optional/
│           ├── loki.yml
│           └── loki-disabled.yml
├── alloy/
│   └── config.alloy
├── loki/
│   └── loki-config.yaml
├── process-exporter/
│   └── config.yml
└── prometheus/
    ├── prometheus.yml
    ├── gpu.yml
    └── targets/
        └── vllm.yml.example
```
