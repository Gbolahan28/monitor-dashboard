# Netdata Monitoring Project

A basic system health monitoring setup using [Netdata](https://github.com/netdata/netdata),
automated with shell scripts. Built as a learning project to understand monitoring
fundamentals before moving on to more advanced tools/pipelines.

## What's included

| Script | Purpose |
|---|---|
| `setup.sh` | Installs Netdata, verifies it's running, adds a custom CPU alert, and adds a custom dashboard page |
| `test_dashboard.sh` | Generates CPU/memory/disk load and confirms Netdata picks it up |
| `cleanup.sh` | Fully uninstalls Netdata and removes config/data left behind |

## Requirements covered

- **Install Netdata on a Linux system** - `setup.sh` uses the official kickstart
  installer (`https://get.netdata.cloud/kickstart.sh`) in non-interactive mode.
- **Monitor CPU, memory, disk I/O** - collected automatically by Netdata out of
  the box, no extra config needed.
- **Access the dashboard** - default UI on `http://<server-ip>:19999/`.
- **Customize the dashboard** - `setup.sh` drops a custom page at
  `/custom-dashboard.html` that embeds a hand-picked set of charts
  (CPU, RAM, disk I/O, load) using Netdata's `dashboard.js` embed API.
- **Set up an alert** - `setup.sh` writes `/etc/netdata/health.d/cpu_custom.conf`,
  which warns at 80% CPU and goes critical at 95%.

## Usage

```bash
# 1. Install and configure
sudo ./setup.sh

# 2. Generate load and verify monitoring + alerting works
./test_dashboard.sh 30      # optional: duration in seconds, default 30

# 3. Tear everything down when you're done
sudo ./cleanup.sh
```

## Notes

- The dashboard is **unauthenticated by default**. On a public server (e.g. a
  DigitalOcean droplet), restrict port `19999` to your own IP:
  ```bash
  sudo ufw allow from <your-ip> to any port 19999
  ```
- Check active alerts at any time with:
  ```bash
  curl -s http://localhost:19999/api/v1/alarms?active | python3 -m json.tool
  ```
- To see the raw CPU chart data Netdata is collecting:
  ```bash
  curl -s "http://localhost:19999/api/v1/data?chart=system.cpu&points=5" | python3 -m json.tool
  ```

## Next steps (future projects)

- Centralize metrics from multiple servers into Netdata Cloud or a Prometheus/Grafana stack
- Wire alert notifications into Slack/email (currently just visible in-dashboard)
- Add this setup to a CI/CD pipeline that provisions monitoring on every new droplet
