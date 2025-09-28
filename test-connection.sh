#!/bin/bash

UPS_SERVER=${1:-localhost}
UPS_PORT=${2:-3493}
UPS_NAME=${3:-servers}  # Default matches instantlinux/nut-upsd default

echo "Testing connection to UPS: ${UPS_NAME}@${UPS_SERVER}:${UPS_PORT}"

# Test basic connection
if command -v upsc >/dev/null 2>&1; then
    echo "✓ NUT client tools found"
    
    # Test UPS connection
    echo "Attempting to connect..."
    STATUS=$(upsc ${UPS_NAME}@${UPS_SERVER}:${UPS_PORT} ups.status 2>/dev/null)
    
    if [[ -n "$STATUS" ]]; then
        echo "✓ Successfully connected to UPS"
        echo "  Status: $STATUS"
        
        # Get more details
        BATTERY=$(upsc ${UPS_NAME}@${UPS_SERVER}:${UPS_PORT} battery.charge 2>/dev/null)
        MODEL=$(upsc ${UPS_NAME}@${UPS_SERVER}:${UPS_PORT} device.model 2>/dev/null)
        
        echo "  Battery: ${BATTERY}%"
        echo "  Model: $MODEL"
        
        # List all available variables
        echo ""
        echo "All available UPS variables:"
        upsc ${UPS_NAME}@${UPS_SERVER}:${UPS_PORT} 2>/dev/null | head -10
        echo "  ... (showing first 10 variables)"
    else
        echo "✗ Failed to connect to UPS"
        echo "  Check that:"
        echo "  - NUT server is running on ${UPS_SERVER}:${UPS_PORT}"
        echo "  - UPS name '${UPS_NAME}' is correct (should match NAME env var from server)"
        echo "  - Network connectivity is working"
        echo "  - If you get 'access denied', your server may require network-level security"
        echo "  - Try: upsc ${UPS_NAME}@${UPS_SERVER}:${UPS_PORT}"
        exit 1
    fi
else
    echo "✗ NUT client tools not found"
    echo "  Install with: apt install nut-client (Debian/Ubuntu)"
    echo "  Or test with: docker run --rm -it alpine sh -c 'apk add nut && upsc ${UPS_NAME}@${UPS_SERVER}:${UPS_PORT} ups.status'"
    exit 1
fi

echo "✓ Connection test completed successfully"
