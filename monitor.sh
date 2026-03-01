#!/bin/bash

UPS_SERVER=${UPS_SERVER:-localhost}
UPS_PORT=${UPS_PORT:-3493}
UPS_NAME=${UPS_NAME:-ups}
CHECK_INTERVAL=${CHECK_INTERVAL:-30}
BATTERY_LEVEL_SHUTDOWN=${BATTERY_LEVEL_SHUTDOWN:-}
ON_BATTERY_TIMEOUT=${ON_BATTERY_TIMEOUT:-}
SHUTDOWN_METHOD=""

# Variables to track UPS state
ON_BATTERY_START_TIME=""
LAST_STATUS=""

echo "Starting UPS monitor for ${UPS_NAME}@${UPS_SERVER}:${UPS_PORT}"
echo "Checking every ${CHECK_INTERVAL} seconds"
if [[ -n "$BATTERY_LEVEL_SHUTDOWN" ]]; then
    echo "Battery level shutdown threshold: ${BATTERY_LEVEL_SHUTDOWN}%"
else
    echo "Battery level shutdown: DISABLED"
fi
if [[ -n "$ON_BATTERY_TIMEOUT" ]]; then
    echo "On-battery timeout: ${ON_BATTERY_TIMEOUT} seconds"
else
    echo "On-battery timeout: DISABLED"
fi

# Note: upsc typically doesn't require authentication for read-only access
# Authentication is mainly for administrative commands (upscmd, upsrw)
# If your NUT server requires authentication even for reads, you may need
# to configure network-level security (firewall, VPN, etc.)

# Test if we can actually shut down the host
echo "Testing host shutdown capability..."
if nsenter -t 1 -m -p /bin/true 2>/dev/null; then
    echo "✓ Host namespace access confirmed via nsenter"
    SHUTDOWN_METHOD="nsenter"
else
    echo "✗ nsenter blocked - testing alternative methods"
    
    # Check what we can access
    if [ -r /proc/1/comm ]; then
        INIT_PROCESS=$(cat /proc/1/comm 2>/dev/null)
        echo "ℹ Host init process: $INIT_PROCESS"
    fi
    
    # Test systemctl availability (best alternative for systemd systems)
    if command -v systemctl >/dev/null 2>&1; then
        echo "ℹ systemctl available - will use systemd method"
        SHUTDOWN_METHOD="systemctl"
    # For systemd systems without systemctl command, use systemd-specific signaling
    elif [[ "$INIT_PROCESS" == "systemd" ]]; then
        echo "ℹ systemd detected - will use systemd signaling method"
        SHUTDOWN_METHOD="systemd_signal"
    # Test sysrq availability (kernel method)
    elif [ -w /proc/sys/kernel/sysrq ]; then
        echo "ℹ sysrq available - will use kernel method"
        SHUTDOWN_METHOD="sysrq"
    # Fallback to direct init signaling
    else
        echo "ℹ Will attempt direct init signaling method"
        SHUTDOWN_METHOD="signal"
    fi
    
    echo "✓ Alternative shutdown method available: $SHUTDOWN_METHOD"
fi

echo "Summary:"
echo "  Shutdown method: $SHUTDOWN_METHOD"
echo "  Host init: $([ -r /proc/1/comm ] && cat /proc/1/comm 2>/dev/null || echo "Unknown")"

# Test initial connection
echo "Testing initial UPS connection..."
INITIAL_STATUS=$(upsc ${UPS_NAME}@${UPS_SERVER}:${UPS_PORT} ups.status 2>/dev/null)
if [[ -n "$INITIAL_STATUS" ]]; then
    echo "✓ Successfully connected to UPS"
    echo "  Initial Status: $INITIAL_STATUS"
else
    echo "✗ WARNING: Cannot connect to UPS server - will keep trying"
fi

while true; do
    # Check UPS status
    STATUS=$(upsc ${UPS_NAME}@${UPS_SERVER}:${UPS_PORT} ups.status 2>/dev/null)
    BATTERY=$(upsc ${UPS_NAME}@${UPS_SERVER}:${UPS_PORT} battery.charge 2>/dev/null)
    
    if [[ -n "$STATUS" ]]; then
        echo "$(date): UPS Status: $STATUS, Battery: $BATTERY%"
    else
        echo "$(date): WARNING: Cannot connect to UPS server"
        sleep $CHECK_INTERVAL
        continue
    fi
    
    # Track when UPS goes on battery
    if [[ "$STATUS" == *"OB"* ]] && [[ "$LAST_STATUS" != *"OB"* ]]; then
        ON_BATTERY_START_TIME=$(date +%s)
        echo "$(date): UPS switched to battery power - starting timer"
    elif [[ "$STATUS" != *"OB"* ]] && [[ "$LAST_STATUS" == *"OB"* ]]; then
        ON_BATTERY_START_TIME=""
        echo "$(date): UPS restored to mains power - timer reset"
    fi
    
    # Update last status for next iteration
    LAST_STATUS="$STATUS"
    
    # Check for shutdown conditions
    SHUTDOWN_REASON=""
    
    if [[ "$STATUS" == *"OB"* ]]; then
        # 1. Critical emergency: On Battery + Low Battery (original condition)
        if [[ "$STATUS" == *"LB"* ]]; then
            SHUTDOWN_REASON="EMERGENCY: UPS on battery with low battery warning"
        
        # 2. Battery level threshold (only if enabled)
        elif [[ -n "$BATTERY_LEVEL_SHUTDOWN" ]] && [[ "$BATTERY" =~ ^[0-9]+$ ]] && [[ "$BATTERY" -le "$BATTERY_LEVEL_SHUTDOWN" ]]; then
            SHUTDOWN_REASON="Battery level ($BATTERY%) at or below threshold ($BATTERY_LEVEL_SHUTDOWN%)"
        
        # 3. On-battery timeout (only if enabled)
        elif [[ -n "$ON_BATTERY_TIMEOUT" ]] && [[ -n "$ON_BATTERY_START_TIME" ]]; then
            CURRENT_TIME=$(date +%s)
            ON_BATTERY_DURATION=$((CURRENT_TIME - ON_BATTERY_START_TIME))
            
            if [[ "$ON_BATTERY_DURATION" -ge "$ON_BATTERY_TIMEOUT" ]]; then
                SHUTDOWN_REASON="On-battery timeout reached (${ON_BATTERY_DURATION}s >= ${ON_BATTERY_TIMEOUT}s)"
            else
                echo "$(date): On battery for ${ON_BATTERY_DURATION}s (timeout: ${ON_BATTERY_TIMEOUT}s)"
            fi
        fi
    fi
    # Execute shutdown if any condition is met
    if [[ -n "$SHUTDOWN_REASON" ]]; then
        echo "$(date): SHUTDOWN TRIGGERED - $SHUTDOWN_REASON"
        echo "$(date): Initiating host shutdown..."
        
        # Optional: Send notification before shutdown
        # curl -X POST "your-webhook-url" -d "UPS Critical: $(hostname) shutting down" || true
        
        # Shutdown the HOST system using the best available method
        echo "$(date): Shutting down HOST system using method: $SHUTDOWN_METHOD"
        
        case "$SHUTDOWN_METHOD" in
            "nsenter")
                nsenter -t 1 -m -p shutdown -h now
                ;;
            "systemctl")
                systemctl poweroff
                ;;
            "systemd_signal")
                # Send SIGRTMIN+3 to systemd for controlled shutdown
                echo "$(date): Sending systemd shutdown signal..."
                kill -RTMIN+3 1 2>/dev/null || kill -TERM 1 2>/dev/null || true
                ;;
            "sysrq")
                echo 1 > /proc/sys/kernel/sysrq 2>/dev/null || true
                echo o > /proc/sysrq-trigger 2>/dev/null || true
                ;;
            "signal"|*)
                # Signal init process directly
                echo "$(date): Signaling init process for shutdown..."
                kill -TERM 1 2>/dev/null || true
                sleep 5
                kill -KILL 1 2>/dev/null || true
                ;;
        esac
        
        # If we get here, shutdown may have failed
        echo "$(date): WARNING: Host shutdown command executed - waiting for system halt..."
        sleep 30
        echo "$(date): ERROR: Host shutdown may have failed!"
        exit 1
    fi
    
    sleep $CHECK_INTERVAL
done
