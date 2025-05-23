#!/usr/bin/env bash

# Uptime Kuma Push Script
# Monitors ping latency and total disk usage, and pushes to Uptime Kuma

# --- Configuration ---
# Base Uptime Kuma Push URL with default parameters
UPTIME_KUMA_PUSH_URL=""
# IP address to ping
PING_IP=""
# Disk usage threshold percentage (if usage >= threshold, status is 'down')
DISK_THRESHOLD="90"

# --- Get Average Ping Latency ---
# Ping the IP 5 times and calculate the average latency
# Handle both standard ping and BusyBox ping output formats
PING_OUTPUT=$(ping -c 5 $PING_IP 2>&1)
if [[ "$PING_OUTPUT" == *"rtt min/avg/max/mdev"* ]]; then
    # Standard ping output format
    AVERAGE_PING=$(echo "$PING_OUTPUT" | grep 'rtt min/avg/max/mdev' | awk -F'/' '{print $5}' | awk '{print $1}')
else
    # BusyBox ping output format - extract average from summary line
    AVERAGE_PING=$(echo "$PING_OUTPUT" | grep -E 'round-trip min/avg/max = [0-9.]+/[0-9.]+/[0-9.]+' | awk -F'/' '{print $4}' | awk '{print $1}')
    # If still not found, try alternative BusyBox format
    if [[ -z "$AVERAGE_PING" ]]; then
        AVERAGE_PING=$(echo "$PING_OUTPUT" | grep -A1 '^---' | grep '^rtt' | awk -F'/' '{print $5}' | awk '{print $1}')
    fi
fi

# Check if ping was successful and we got a valid number
if [[ -z "$AVERAGE_PING" || ! "$AVERAGE_PING" =~ ^[0-9.]+$ ]]; then
    AVERAGE_PING=0 # Set to 0 if ping fails or output format changes
fi

# --- Get Total Disk Usage ---
# Get root filesystem usage percentage
TOTAL_DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')

# Check if we got a number
if [[ -z "$TOTAL_DISK_USAGE" || ! "$TOTAL_DISK_USAGE" =~ ^[0-9]+$ ]]; then
    TOTAL_DISK_USAGE=0 # Set to 0 if command fails or output format changes
fi

# --- Determine Service Status ---
# Determine status based on total disk usage
if [[ "$TOTAL_DISK_USAGE" -lt "$DISK_THRESHOLD" ]]; then
    SERVICE_STATUS="up"
else
    SERVICE_STATUS="down"
fi

# --- Build Message ---
# Create a message string
MESSAGE="Total disk usage is ${TOTAL_DISK_USAGE}%"

# --- Execute Curl Command ---
# Build and execute the curl command to push to Uptime Kuma
# Replace default parameters with actual values (URL encode message)
ENCODED_MSG=$(printf '%s' "${MESSAGE}" | jq -sRr @uri)
# Remove all default parameters first
BASE_URL="${UPTIME_KUMA_PUSH_URL%%\?*}"
FULL_URL="${BASE_URL}?status=${SERVICE_STATUS}&msg=${ENCODED_MSG}&ping=${AVERAGE_PING}"
curl --silent "${FULL_URL}"

# Always log debug info regardless of terminal
{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo "Ping IP: ${PING_IP}"
    echo "Average Ping: ${AVERAGE_PING}ms" 
    echo "Disk Usage: ${TOTAL_DISK_USAGE}%"
    echo "Service Status: ${SERVICE_STATUS}"
    echo "Final Push URL: ${FULL_URL}"
    echo "Curl Exit Code: $?"
} >> /var/log/uptime_push.log
