#!/bin/bash

LOGFILE="$HOME/monitor.log"
SERVICE_DIR="$HOME/sample-microService"
REPO_URL="https://github.com/IITJ-M23CSA521/sample-microService.git"
stress_cores=3
scaling_triggered=0
#LOGFILE="monitoring.log"
stress_cores=3
high_cpu_threshold=75
low_cpu_threshold=25
scaling_triggered=0
high_cpu_count=0

log() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1" | tee -a "$LOGFILE"
}

log "----- Monitoring Script Started -----"

# --- Install Dependencies ---
log "Installing dependencies..."
apt update && apt install -y git sysstat stress-ng curl nodejs npm

# --- Clone Microservice ---
log "Cloning microservice..."
rm -rf "$SERVICE_DIR"
git clone "$REPO_URL" "$SERVICE_DIR"
cd "$SERVICE_DIR" || exit 1
npm install

# --- Start Microservice ---
log "Starting microservice..."
npm start &  # Assumes npm start exists
service_pid=$!

# --- Monitoring Loop ---
echo "Starting CPU Monitoring and Scaling..." | tee "$LOGFILE"

while true; do
    echo "Increasing Load for 2 minutes using $stress_cores CPU workers..." | tee -a "$LOGFILE"
    stress-ng --cpu $stress_cores --cpu-method matrixprod --timeout 300 & 
    stress_pid=$!

    sleep 60  # Allow stress to build CPU load

    # Measure CPU usage
    cpu_idle=$(mpstat 1 1 | awk '/all/ {print $(NF); exit}')
    cpu_usage=$(awk -v idle="$cpu_idle" 'BEGIN { printf "%.0f", 100 - idle }')
    
    echo "$(date +"%Y-%m-%d %H:%M:%S") - CPU Usage: ${cpu_usage}%" | tee -a "$LOGFILE"

    # Check if CPU usage is high
    if (( cpu_usage > high_cpu_threshold )); then
        ((high_cpu_count++))
    else
        high_cpu_count=0
    fi

    # Trigger scaling if CPU usage high
    if [[ $high_cpu_count -ge 1 && $scaling_triggered -eq 0 ]]; then
        echo "High CPU detected! Triggering cloud autoscaling..." | tee -a "$LOGFILE"

        gcloud compute instance-groups managed set-autoscaling node-instance-group \
            --min-num-replicas=1 --max-num-replicas=3 \
            --target-cpu-utilization=0.75 \
            --cool-down-period=15 \
            --zone=us-west4-b 2>&1 | tee -a "$LOGFILE"

        echo "$(date +"%Y-%m-%d %H:%M:%S") - Scaling triggered." | tee -a "$LOGFILE"
        scaling_triggered=1
    fi

    echo "🔽 Stopping Load Generator..." | tee -a "$LOGFILE"
    pkill -9 -f "stress-ng"
    sleep 5

    # Wait for CPU to stabilize before scaling down
    while true; do
        cpu_idle=$(mpstat 1 1 | awk '/all/ {print $(NF); exit}')
        temp_cpu_usage=$(awk -v idle="$cpu_idle" 'BEGIN { printf "%.0f", 100 - idle }')
        echo "$(date +"%Y-%m-%d %H:%M:%S") - Temp CPU Usage: ${temp_cpu_usage}%" | tee -a "$LOGFILE"

        if (( temp_cpu_usage < low_cpu_threshold )); then
            echo "✅ CPU usage normal. Scaling down..." | tee -a "$LOGFILE"

            gcloud compute instance-groups managed resize node-instance-group --size=1 --zone=us-west4-b 2>&1 | tee -a "$LOGFILE"

            echo "$(date +"%Y-%m-%d %H:%M:%S") - VMs reduced to 1." | tee -a "$LOGFILE"
            scaling_triggered=0
            break
        fi
        sleep 30
    done

    sleep 30  # Pause before next cycle
done