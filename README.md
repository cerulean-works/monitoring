# Monitoring Stack

A Docker Compose stack for monitoring host and GPU metrics using **Prometheus**, **Grafana**, **NVIDIA DCGM Exporter**, and **Node Exporter**.

## Services & Endpoints

| Service | Endpoint | Description |
| :--- | :--- | :--- |
| **Prometheus** | `http://localhost:9090` | Time-series metrics database (scrapes every 1s) |
| **Grafana** | `http://localhost:3000` | Metrics visualization (`admin` / `admin`) |
| **DCGM Exporter** | `http://localhost:9400/metrics` | NVIDIA GPU metrics exporter |
| **Node Exporter** | `http://localhost:9100/metrics` | Host hardware & OS metrics exporter (via `/proc`, `/sys`, `/` mounts) |

*Note: All services run in `network_mode: host`.*

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

## Grafana 啟動說明與優化 (Grafana Startup Note)

### 初次啟動需要時間的原因
當初次啟動 Docker Stack 或執行 `docker compose down -v`（刪除 Volume 重新建立）時，Grafana 需要 5~15 秒完成以下作業：
1. **SQLite 資料庫初始化與 Migration**：在 `grafana.db` 建立基本表結構與系統遷移。
2. **Provisioning 自動匯入**：掃描並載入 Prometheus Data Source 及 JSON Dashboard 配置。
3. **服務模組初始化**：啟動 Alerting 引擎、Plugin 系統與 HTTP Server。

### 已配置的優化與解決方案
為了加速 Grafana 啟動並便於監控狀態，已在 `docker-compose.yaml` 中調整以下設定：

1. **關閉統計與更新檢查**（加速啟動）：
   - `GF_ANALYTICS_REPORTING_ENABLED=false`
   - `GF_ANALYTICS_CHECK_FOR_UPDATES=false`
2. **新增 Healthcheck 機制**（狀態自動檢測）：
   - 配置了 `/api/health` 探針。可使用 `docker compose ps` 查看 Grafana 狀態：
     - `Up (health: starting)`：正在初始化
     - `Up (healthy)`：已完成啟動，可直接訪問 `http://localhost:3000`
3. **保持 Volume 資料持久化**（建議作業方式）：
   - 停止服務時請使用 `docker compose down`（**不要加 `-v`**）。第二次與後續啟動時，SQLite 資料庫已初始化完成，將在數秒內迅速就緒。


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

