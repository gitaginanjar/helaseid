# HELASEID - Headless Automatic Service Discovery © by [G. Ginanjar](https://github.com/gitaginanjar)

![HELASEID Logo](./logo/helaseid-logo.png)

## Overview
HELASEID (Headless Automatic Service Discovery) is a lightweight, containerized BASH-based solution for dynamically updating Kubernetes endpoints for headless services. It continuously monitors the health of service instances and updates the corresponding Kubernetes `Endpoints` object accordingly.

The name **HELASEID** is inspired by two powerful supervillains:
- **Hela** (Marvel) : Beautiful yet resourceful.
- **Darkseid** (DC) : Resilient and strategic.

This tool embodies their strengthsÃ¢â‚¬â€efficiency, adaptability, and robustness.

## Features
- **Automated Health Checks:** Monitors service health via TCP probes.
- **Kubernetes Endpoint Management:** Dynamically updates the `Endpoints` object.
- **Microsoft Teams Integration:** Sends alerts on failures.
- **Lightweight & Efficient:** Runs with minimal CPU and memory footprint.
- **Configurable via Kubernetes ConfigMap & Secrets:** Environment-based configuration.

## Architecture
HELASEID follows a simple yet effective architecture:
1. Loads configuration from Kubernetes `ConfigMap`.
2. Performs health checks on configured service IPs.
3. Updates Kubernetes `Endpoints` to reflect live instances.
4. Sends notifications to Microsoft Teams when failures occur.

## Installation
### Prerequisites
- Kubernetes cluster (tested on v1.24+)
- `kubectl` access with permissions to modify `Endpoints`
- Microsoft Teams Webhook (optional for alerts)

### Deployment Steps
1. **Deploy Kubernetes Manifests:**
```bash
git clone git@bitbucket.org:mandiri-sekuritas/helaseid.git
cd helaseid
kubectl apply -f manifests/
```
2. **Verify Deployment:**
```bash
kubectl get pods -n datastream
```
3. **Check Logs:**
```bash
kubectl logs -f deployment/datastream-helaseid-dev -n datastream
```

## Configuration
HELASEID uses a ConfigMap (`datastream-helaseid-dev`) to define environment variables:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: datastream-helaseid-dev
  namespace: datastream
data:
  config.env: |
    IPS=("10.188.2.3" "10.188.2.4" "10.188.2.5")
    PORT=9092
    MAX_RETRY=10
    DELAY=0.01
    LOG_LEVEL=INFO
    NAMESPACE=datastream
    SERVICE_NAME=datastream-redpanda-api-dev
```
- `IPS` - List of service instance IPs to monitor.
- `PORT` - Service port to check health.
- `MAX_RETRY` - Maximum retries before marking unhealthy.
- `DELAY` - Delay between health checks.
- `LOG_LEVEL` - Logging verbosity (`DEBUG`, `INFO`, `ERROR`).
- `NAMESPACE` - Kubernetes namespace.
- `SERVICE_NAME` - Kubernetes service name.

## Microsoft Teams Integration
To enable Teams notifications, add a Kubernetes `Secret` with a webhook URL:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: datastream-hslc-dev
type: Opaque
data:
  TEAMS_WEBHOOK_URL: <Base64-encoded-webhook-URL>
```

## Running Locally
To test outside Kubernetes, build and run the container:
```bash
docker build -t helaseid:latest .
docker run --rm -e IPS="10.188.2.3 10.188.2.4" -e PORT=9092 helaseid
```

## Future Enhancements
- Support for multi-cluster service discovery.
- Dynamic IP retrieval via Kubernetes API.
- Metrics export for Prometheus integration.
- Support multi-zone/multi-region discovery with dynamic preferences and master pinning.

## Author
- [G. Ginanjar](https://github.com/gitaginanjar).

