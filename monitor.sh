#!/bin/bash

UPS_SERVER=${UPS_SERVER:-localhost}
UPS_PORT=${UPS_PORT:-3493}
UPS_NAME=${UPS_NAME:-ups}
CHECK_INTERVAL=${CHECK_INTERVAL:-30}

echo "Starting UPS monitor for ${UPS_NAME}@${UPS_SERVER}:${UPS_PORT}"
echo "Checking every ${CHECK_INTERVAL} seconds"

# Note: upsc typically doesn't require authentication for read-only access
# Authentication is mainly for administrative commands (upscmd, upsrw)
# If your NUT server requires authentication even for reads, you may need
# to configure network-level security (firewall, VPN, etc.)

# Test if we can actually shut down the host
echo "Testing host shutdown capability..."
if nsenter -t 1 -m -p /bin/true 2>/dev/null; then
    echo "✓ Host namespace access confirmed"
else
    echo "✗ WARNING: Cannot access host namespace - shutdown may not work!"
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
        
        # Shutdown the HOST system using nsenter
        echo "$(date): Shutting down HOST system via nsenter..."
        nsenter -t 1 -m -p shutdown -h now
        
        # If that fails, try alternative methods
        sleep 5
        echo "$(date): Trying alternative shutdown method..."
        nsenter -t 1 -m -p systemctl poweroff
        
        # Last resort
        sleep 5
        echo "$(date): Using poweroff as last resort..."
        nsenter -t 1 -m -p poweroff
        
        # If we get here, something went wrong
        echo "$(date): ERROR: All shutdown attempts failed!"
        exit 1
    fi
    
    sleep $CHECK_INTERVAL
done
