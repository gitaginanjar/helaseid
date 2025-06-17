#!/bin/bash

# Load Configurations
CONFIG_FILE="/.env"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "ERROR: Config file $CONFIG_FILE not found! Exiting..."
    exit 1
fi

# Set Default Variables
TIMEZONE=${TIMEZONE:-"Asia/Jakarta"}
LOG_LEVEL=${LOG_LEVEL:-"INFO"}
TEAMS_WEBHOOK_URL=${TEAMS_WEBHOOK_URL:-""}
NOTIFICATION_ENABLED=${NOTIFICATION_ENABLED:-"true"}
declare -A STATUS

# Ensure the timezone is set dynamically if TIMEZONE is provided
if [ -n "${TIMEZONE}" ]; then
    echo "Setting timezone to ${TIMEZONE} ..."
    ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
    echo "${TIMEZONE}" > /etc/timezone
fi

# Function to generate a timestamp in the required format
function Function_get_timestamp() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'$(awk 'BEGIN{srand(); printf ".%03d\n", int(rand()*1000)}'))"
}

# Function to Send Notifications to Microsoft Teams
function Function_send_teams_notification() {
    local level="$1"
    local message="$2"
    if [[ -n "$TEAMS_WEBHOOK_URL" ]]; then
        json_payload=$(jq -n \
            --arg title "Ã°Å¸â€â€ Health Check Notification" \
            --arg level "$level" \
            --arg message "$message" \
            --arg timestamp "$(date '+%Y-%m-%d %H:%M:%S')" \
            '{
                "@type": "MessageCard",
                "@context": "http://schema.org/extensions",
                "summary": $title,
                "themeColor": ($level == "ERROR" ? "FF0000" : "00FF00"),
                "title": $title,
                "text": "[" + $timestamp + "] **" + $level + "**: " + $message
            }')
        curl -H "Content-Type: application/json" -d "$json_payload" "$TEAMS_WEBHOOK_URL"
    fi
}

# Function to Log Messages
function Function_log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(Function_get_timestamp)
    # Only log messages if the level is DEBUG or the log level is INFO but message is EVENT/ERROR
    if [[ "$LOG_LEVEL" == "DEBUG" || "$level" == "EVENT" || "$level" == "INFO" || "$level" == "ERROR" ]]; then
        echo "{\"timestamp\": \"$timestamp\", \"level\": \"$level\", \"message\": \"$message\"}"
        if [[ "$NOTIFICATION_ENABLED" == "true" && ("$level" == "ERROR" || "$level" == "EVENT") ]]; then
            Function_send_teams_notification "$level" "$message"
        fi
    fi
}

# Function to Check Health
function Function_check_health() {
    local ip="$1"
    local port="$2"
    if nc -vz "$ip" "$port" &>/dev/null; then
        return 0  # Healthy
    else
        return 1  # Not Healthy
    fi
}

declare -A PREV_STATUS

# Function to Update Kubernetes Endpoints
function Function_update_endpoints() {
    local healthy_ips=()
    local status_changed=false

    for ip in "${IPS[@]}"; do
        if [[ "${STATUS[$ip]}" != "${PREV_STATUS[$ip]}" ]]; then
            status_changed=true
        fi
        if [[ "${STATUS[$ip]}" == "Healthy" ]]; then
            healthy_ips+=("{\"ip\": \"$ip\"}")
        fi
    done

    if [[ "$status_changed" == "true" ]]; then
        if [[ ${#healthy_ips[@]} -gt 0 ]]; then
            local json_payload="[{\"op\": \"replace\", \"path\": \"/subsets/0/addresses\", \"value\": [$(IFS=,; echo "${healthy_ips[*]}")]}]"
            Function_log "EVENT" "Updating Kubernetes endpoints with healthy IPs: ${healthy_ips[*]}"
            kubectl patch endpoints "$SERVICE_NAME" -n "$NAMESPACE" --type='json' -p="$json_payload"
            Function_log "EVENT" "Finished updating Kubernetes endpoints with healthy IPs: ${healthy_ips[*]}"
        else
            Function_log "EVENT" "No healthy IPs available, clearing Kubernetes endpoints."
            kubectl patch endpoints "$SERVICE_NAME" -n "$NAMESPACE" --type='json' -p="[{\"op\": \"remove\", \"path\": \"/subsets/0/addresses\"}]"
            Function_log "EVENT" "Finished clearing Kubernetes endpoints."
        fi
    fi
}

# Ensure IPS array is populated
IFS=' ' read -r -a IPS <<< "${IPS[@]}"
if [[ ${#IPS[@]} -eq 0 ]]; then
    Function_log "ERROR" "No IPs defined in ConfigMap! Exiting..."
    exit 1
fi

Function_log "INFO" "LOG_LEVEL            : $LOG_LEVEL"
Function_log "INFO" "PORT                 : $PORT"
Function_log "INFO" "DELAY                : $DELAY"
Function_log "INFO" "MAX_RETRY            : $MAX_RETRY"
Function_log "INFO" "SERVICE_NAME         : $SERVICE_NAME"
Function_log "INFO" "NAMESPACE            : $NAMESPACE"
Function_log "INFO" "NOTIFICATION_ENABLED : $NOTIFICATION_ENABLED"
Function_log "DEBUG" "TEAMS_WEBHOOK_URL   : $TEAMS_WEBHOOK_URL"

# Main Health Check Loop
while true; do
    for ip in "${IPS[@]}"; do
        Function_check_health "$ip" "$PORT"
        result=$?
        PREV_STATUS["$ip"]=${STATUS["$ip"]:-"Unknown"}

        if [[ $result -eq 0 ]]; then
            STATUS["$ip"]="Healthy"
        else
            STATUS["$ip"]="NotHealthy"
        fi
    done

    Function_update_endpoints
    Function_log "DEBUG" "Sleeping for $DELAY seconds..."
    sleep "$DELAY" || Function_log "ERROR" "Sleep interrupted!"
done
