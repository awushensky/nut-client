# NUT Client Monitor Docker Container

A Docker container that monitors a Network UPS Tools (NUT) server and automatically shuts down the host machine when the UPS battery becomes critically low.

## Features

- 🔋 Monitors UPS status via NUT protocol
- 🚨 Automatic host shutdown on critical battery conditions
- 🐳 Containerized for easy deployment
- 🔄 Graceful Docker container shutdown before host shutdown
- 📊 Continuous status logging
- 🏥 Built-in health checks
- 🔧 Configurable check intervals and UPS parameters

## Quick Start

### Prerequisites

- Docker and Docker Compose installed
- A running NUT server (like `instantlinux/nut-upsd`)
- Host machine that needs automatic shutdown protection

### Basic Usage

```yaml
version: '3.8'
services:
  ups-monitor:
    image: awushensky/nut-client:latest
    container_name: ups-monitor
    restart: unless-stopped
    environment:
      UPS_SERVER: 192.168.1.100  # Your NUT server IP
      UPS_PORT: 3493
      UPS_NAME: ups
      CHECK_INTERVAL: 30
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /proc:/host/proc:ro
    privileged: true
    pid: host
    network_mode: host
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `UPS_SERVER` | `localhost` | IP address of your NUT server |
| `UPS_PORT` | `3493` | Port of your NUT server |
| `UPS_NAME` | `ups` | Name of the UPS as configured in NUT |
| `CHECK_INTERVAL` | `30` | How often to check UPS status (seconds) |

### Authentication Notes

This container uses the `upsc` command for read-only UPS status queries. In standard NUT configurations, upsd always provides read-only access to anonymous clients. The user authentication feature is there only for granting access to control actions (e.g. upsrw changing UPS parameters, or upscmd triggering calibration, or upsmon setting 'forced shutdown').

If your NUT server requires authentication even for read access, you may need to:
- Configure network-level security (VPN, firewall rules)
- Use TLS certificates with `CERTREQUEST REQUIRE` in upsd.conf
- Contact the container maintainer for authentication support

### Required Docker Settings

- `privileged: true` - Required for host shutdown capability
- `pid: host` - Required for accessing host processes
- `network_mode: host` - Recommended for network access
- `/var/run/docker.sock` volume - Required to stop containers before shutdown

## NUT Server Setup

The `instantlinux/nut-upsd` container is configured entirely through environment variables - no config files needed!

### NUT Server Configuration

```yaml
services:
  nut-server:
    image: instantlinux/nut-upsd:latest
    container_name: nut-server
    restart: unless-stopped
    environment:
      NAME: "ups"                       # UPS name (what clients connect to)
      SERIAL: YOUR_UPS_SERIAL_HERE      # Your UPS serial number  
      API_USER: ${NUT_UPS_USER}         # Username for API access
      API_PASSWORD: ${NUT_UPS_PASSWORD} # Password for API access
      DRIVER: usbhid-ups                # UPS driver (optional)
    ports:
      - "3493:3493"
    privileged: true
    devices:
      - /dev/bus/usb:/dev/bus/usb
```

### Environment Variables (.env file)

```bash
# .env file
NUT_UPS_USER=admin
NUT_UPS_PASSWORD=your_secure_password
```

> **Note**: The container automatically configures all NUT settings based on these environment variables. The `API_USER` and `API_PASSWORD` are used for administrative access to the NUT server, but standard read-only queries (like this monitor uses) typically don't require authentication in NUT.

## How It Works

1. **Monitoring**: Container continuously polls the NUT server for UPS status
2. **Detection**: Watches for `OB` (On Battery) + `LB` (Low Battery) conditions
3. **Shutdown Sequence**:
   - Logs critical condition
   - Stops all Docker containers gracefully
   - Waits 10 seconds for cleanup
   - Shuts down the host using `nsenter` to break out of container namespace

## Status Codes

The monitor looks for these UPS status combinations:
- `OL` - Online (normal operation)
- `OB` - On Battery (power outage)
- `LB` - Low Battery (critical - triggers shutdown)
- `OB LB` - On Battery + Low Battery (immediate shutdown)

## Safety Features

- **Test Mode**: Container tests host shutdown capability on startup
- **Graceful Shutdown**: Stops all containers before host shutdown
- **Multiple Fallbacks**: Uses multiple shutdown methods if primary fails
- **Connection Monitoring**: Warns if unable to connect to UPS server

## Logs

Monitor the container logs to see UPS status:

```bash
docker logs -f ups-monitor
```

Example output:
```
Starting UPS monitor for ups@192.168.1.100:3493
✓ Host namespace access confirmed
2024-01-15 10:30:00: UPS Status: OL, Battery: 100%
2024-01-15 10:30:30: UPS Status: OB, Battery: 95%
2024-01-15 10:35:00: CRITICAL - UPS is on battery and low battery detected!
2024-01-15 10:35:00: Initiating emergency shutdown sequence...
```

## Building from Source

```bash
git clone https://github.com/your-username/ups-monitor.git
cd ups-monitor
docker build -t ups-monitor .
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Disclaimer

⚠️ **Important**: This container can shut down your host machine. Test thoroughly in a safe environment before deploying to production systems.

## Support

- Create an issue for bugs or feature requests
- Check the [NUT documentation](https://networkupstools.org/docs/) for UPS compatibility
- Ensure your UPS is properly configured with NUT before using this monitor
