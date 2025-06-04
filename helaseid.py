import os
import json
import time
import socket
import subprocess
from datetime import datetime, timezone, timedelta
import requests

# Load configuration from .env
from dotenv import load_dotenv
load_dotenv("/.env")

# Default configurations
TIMEZONE = os.getenv("TIMEZONE", "Asia/Jakarta")
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")
TEAMS_WEBHOOK_URL = os.getenv("TEAMS_WEBHOOK_URL", "")
NOTIFICATION_ENABLED = os.getenv("NOTIFICATION_ENABLED", "true").lower() == "true"
IPS = os.getenv("IPS", "").split()
PORT = int(os.getenv("PORT", 9092))
DELAY = float(os.getenv("DELAY", 0.01))
MAX_RETRY = int(os.getenv("MAX_RETRY", 10))
NAMESPACE = os.getenv("NAMESPACE", "default")
SERVICE_NAME = os.getenv("SERVICE_NAME", "")

PREV_STATUS = {}
STATUS = {}

# Set timezone
try:
    tz_path = f"/usr/share/zoneinfo/{TIMEZONE}"
    if os.path.exists(tz_path):
        os.symlink(tz_path, "/etc/localtime")
        with open("/etc/timezone", "w") as tz_file:
            tz_file.write(TIMEZONE)
except Exception as e:
    print(f"Error setting timezone: {e}")


def get_timestamp():
    now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    milliseconds = f".{int(time.time() * 1000) % 1000:03d}"
    return now + milliseconds


def send_teams_notification(level, message):
    if not TEAMS_WEBHOOK_URL:
        return

    payload = {
        "@type": "MessageCard",
        "@context": "http://schema.org/extensions",
        "summary": "🚀 Health Check Notification",
        "themeColor": "FF0000" if level == "ERROR" else "00FF00",
        "title": "🚀 Health Check Notification",
        "text": f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] **{level}**: {message}"
    }
    try:
        requests.post(TEAMS_WEBHOOK_URL, json=payload)
    except Exception as e:
        print(f"Failed to send Teams notification: {e}")


def log(level, message):
    timestamp = get_timestamp()
    if LOG_LEVEL == "DEBUG" or level in ("EVENT", "INFO", "ERROR"):
        log_entry = {"timestamp": timestamp, "level": level, "message": message}
        print(json.dumps(log_entry))
        if NOTIFICATION_ENABLED and level in ("ERROR", "EVENT"):
            send_teams_notification(level, message)


def check_health(ip, port):
    try:
        with socket.create_connection((ip, port), timeout=3):
            return True
    except Exception:
        return False


def update_endpoints():
    healthy_ips = []
    status_changed = False

    for ip in IPS:
        if STATUS.get(ip) != PREV_STATUS.get(ip):
            status_changed = True
        if STATUS.get(ip) == "Healthy":
            healthy_ips.append({"ip": ip})

    if not status_changed:
        return

    try:
        if healthy_ips:
            json_patch = [{
                "op": "replace",
                "path": "/subsets/0/addresses",
                "value": healthy_ips
            }]
            log("EVENT", f"Updating Kubernetes endpoints with healthy IPs: {healthy_ips}")
        else:
            json_patch = [{"op": "remove", "path": "/subsets/0/addresses"}]
            log("EVENT", "No healthy IPs available, clearing Kubernetes endpoints.")

        subprocess.run([
            "kubectl", "patch", "endpoints", SERVICE_NAME,
            "-n", NAMESPACE, "--type=json",
            "-p", json.dumps(json_patch)
        ], check=True)
        log("EVENT", f"Finished updating Kubernetes endpoints.")
    except subprocess.CalledProcessError as e:
        log("ERROR", f"Failed to patch endpoints: {e}")


if not IPS:
    log("ERROR", "No IPs defined in ConfigMap! Exiting...")
    exit(1)

log("INFO", f"LOG_LEVEL            : {LOG_LEVEL}")
log("INFO", f"PORT                 : {PORT}")
log("INFO", f"DELAY                : {DELAY}")
log("INFO", f"MAX_RETRY            : {MAX_RETRY}")
log("INFO", f"SERVICE_NAME         : {SERVICE_NAME}")
log("INFO", f"NAMESPACE            : {NAMESPACE}")
log("INFO", f"NOTIFICATION_ENABLED : {NOTIFICATION_ENABLED}")
log("DEBUG", f"TEAMS_WEBHOOK_URL    : {TEAMS_WEBHOOK_URL}")

# Health check loop
while True:
    for ip in IPS:
        PREV_STATUS[ip] = STATUS.get(ip, "Unknown")
        STATUS[ip] = "Healthy" if check_health(ip, PORT) else "NotHealthy"

    update_endpoints()
    log("DEBUG", f"Sleeping for {DELAY} seconds...")
    try:
        time.sleep(DELAY)
    except KeyboardInterrupt:
        log("ERROR", "Sleep interrupted by user. Exiting...")
        break
