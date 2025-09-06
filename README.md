# Tailscale Token Manager

A lightweight Docker container that manages OAuth tokens for Tailscale API access and provides a proxy endpoint for applications like Glance dashboard.

## Features

- 🔄 **Automatic Token Refresh**: Manages OAuth token lifecycle with automatic renewal
- 🔒 **Secure**: Runs as non-root user with minimal attack surface
- 🌐 **Proxy API**: Simple HTTP proxy to Tailscale API with transparent token handling
- 🐳 **Multi-Architecture**: Supports AMD64 and ARM64 architectures
- 📊 **Health Checks**: Built-in container health monitoring

## Quick Start

### Using Docker Compose (Recommended)

```yaml
services:
  tailscale-token-manager:
    image: ghcr.io/5at0ri/tailscale-token-manager:latest
    container_name: tailscale-token-manager
    restart: always
    ports:
      - "1180:1180"
    environment:
      - TAILSCALE_CLIENT_ID=your_client_id_here
      - TAILSCALE_CLIENT_SECRET=your_client_secret_here
      - TZ=America/New_York
    volumes:
      - tailscale-tokens:/tokens
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:1180/devices"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

volumes:
  tailscale-tokens:
```

### Using Docker CLI

```bash
docker run -d \
  --name tailscale-token-manager \
  --restart always \
  -p 1180:1180 \
  -e TAILSCALE_CLIENT_ID=your_client_id_here \
  -e TAILSCALE_CLIENT_SECRET=your_client_secret_here \
  -e TZ=America/New_York \
  -v tailscale-tokens:/tokens \
  ghcr.io/5at0ri/tailscale-token-manager:latest
```

## Configuration

### Environment Variables

| Variable | Required | Description | Default |
|----------|----------|-------------|---------|
| `TAILSCALE_CLIENT_ID` | ✅ | OAuth Client ID from Tailscale Admin Console | - |
| `TAILSCALE_CLIENT_SECRET` | ✅ | OAuth Client Secret from Tailscale Admin Console | - |
| `PROXY_PORT` | ❌ | Port for the proxy server | `1180` |
| `TZ` | ❌ | Timezone for logging | `UTC` |

### Setting up Tailscale OAuth

1. Go to the [Tailscale Admin Console](https://login.tailscale.com/admin/settings/oauth)
2. Generate a new OAuth client
3. Set the scopes to `devices:read` (or whatever permissions you need)
4. Copy the Client ID and Client Secret to your environment variables

## API Endpoints

### GET /devices

Proxies requests to Tailscale's device API with automatic token management.

**Response**: Returns the same JSON structure as [Tailscale's devices API](https://tailscale.com/api#tag/devices/GET/tailnet/%7Btailnet%7D/devices)

**Example**:
```bash
curl http://localhost:1180/devices
```

## Integration Examples

### Glance Dashboard

```yaml
- type: chart
  title: Tailscale Devices
  url: http://tailscale-token-manager:1180/devices
```

### Home Assistant

```yaml
sensor:
  - platform: rest
    name: tailscale_devices
    resource: http://tailscale-token-manager:1180/devices
    json_attributes_path: "$.devices"
```

## Architecture

The container runs two main processes:

1. **Token Manager**: Background process that refreshes OAuth tokens every 55 minutes
2. **HTTP Proxy**: Lightweight Python server that serves API requests using current tokens

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Your App      │───▶│ Token Manager    │───▶│ Tailscale API   │
│ (Glance, etc.)  │    │ (This Container) │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## Building from Source

```bash
git clone https://github.com/5at0ri/tailscale-token-manager.git
cd tailscale-token-manager
docker build -t tailscale-token-manager .
```

## Security Considerations

- Container runs as non-root user (`tokenmanager`)
- Tokens are stored in memory and temporary files only
- No sensitive data is logged
- Uses minimal Alpine base image
- Regular security updates via automated builds

## Troubleshooting

### Check container logs
```bash
docker logs tailscale-token-manager
```

### Verify token refresh
```bash
# Should return Tailscale devices JSON
curl http://localhost:1180/devices
```

### Common issues

1. **"tailscale token unavailable"**: Check your OAuth credentials
2. **Connection refused**: Verify the container is running and port is exposed
3. **401 Unauthorized**: OAuth client may need device:read permissions

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

- 🐛 [Report a bug](https://github.com/suluxan/tailscale-token-manager/issues)
- 💡 [Request a feature](https://github.com/suluxan/tailscale-token-manager/issues)
- 💬 [Discussions](https://github.com/suluxan/tailscale-token-manager/discussions)
