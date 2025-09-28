#!/bin/bash

UPS_SERVER=${UPS_SERVER:-localhost}
UPS_PORT=${UPS_PORT:-3493}
UPS_NAME=${UPS_NAME:-ups}
CHECK_INTERVAL=${CHECK_INTERVAL:-30}
SHUTDOWN_METHOD=""

echo "Starting UPS monitor for ${UPS_NAME}@${UPS_SERVER}:${UPS_PORT}"
echo "Checking every ${CHECK_INTERVAL} seconds"

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
    
    # Test systemctl availability (best alternative)
    if command -v systemctl >/dev/null 2>&1; then
        echo "ℹ systemctl available - will use systemd method"
        SHUTDOWN_METHOD="systemctl"
    # Test sysrq availability (second best)
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

# Test Docker socket access
if [ -w /var/run/docker.sock ]; then
    echo "✓ Docker socket access confirmed"
else
    echo "✗ Cannot access Docker socket - container cleanup may not work"
fi

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
    
    # Check for critical conditions:
    # OB = On Battery, LB = Low Battery
    if [[ "$STATUS" == *"OB"* ]] && [[ "$STATUS" == *"LB"* ]]; then
        echo "$(date): CRITICAL - UPS is on battery and low battery detected!"
        echo "$(date): Initiating emergency shutdown sequence..."
        
        # Optional: Send notification before shutdown
        # curl -X POST "your-webhook-url" -d "UPS Critical: $(hostname) shutting down" || true
        
        # Stop all Docker containers gracefully first
        echo "$(date): Stopping all Docker containers..."
        docker stop $(docker ps -q) 2>/dev/null || true
        
        # Wait for containers to stop
        sleep 10
        
        # Shutdown the HOST system using the best available method
        echo "$(date): Shutting down HOST system using method: $SHUTDOWN_METHOD"
        
        case "$SHUTDOWN_METHOD" in
            "nsenter")
                nsenter -t 1 -m -p shutdown -h now
                ;;
            "systemctl")
                systemctl poweroff
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
        
        # If we get here, something went wrong
        echo "$(date): ERROR: All shutdown attempts failed!"
        exit 1
    fi
    
    sleep $CHECK_INTERVAL
done
