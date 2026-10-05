# OpenQDA Deployment

This guide describes how to deploy OpenQDA to your custom infrastructure.
Currently, there are two options for deployment:

## Backup and Recovery

OpenQDA includes a comprehensive backup script that can be scheduled to run automatically. The backup script creates a complete snapshot of your application data including database, storage files, and configuration. For detailed information on setting up automated backups, see the [Backup & Recovery Guide](./backup.md).


## Via Docker

> Please note, that deployment via Docker is different from the Docker setup,
described in the [docker installation guide for local development!](../installation/docker.md)!

A production-ready container stack lives at the repository root
(`docker-compose.prod.yml`) and in `web/docker/production/`. It builds the
Vue frontend and PHP dependencies, then runs nginx + php-fpm + the Reverb
websocket server + a queue worker inside a single app container,
supervised by `supervisord`. MySQL, Redis and the `convert-to-html`
transform service run as separate containers on the same network.

### Quick start

```bash
# from the repository root
cp web/docker/production/production.env.example web/.env
# edit web/.env: set DB_*, REDIS_PASSWORD, REVERB_* and MAIL_* for your environment

docker compose -f docker-compose.prod.yml build

# generate and store an application key before first boot
docker compose -f docker-compose.prod.yml run --rm app php artisan key:generate --show
# paste the generated value into APP_KEY in web/.env

docker compose -f docker-compose.prod.yml up -d
```

The app container runs database migrations automatically on startup
(`RUN_MIGRATIONS=true` in the env file controls this). Application,
Reverb and queue-worker logs are written to stdout/stderr and are visible
via `docker compose -f docker-compose.prod.yml logs -f app`.

Put a reverse proxy (nginx, Caddy, Traefik) in front of the stack to
terminate TLS and forward both the HTTP port (`APP_PORT`, default `80`)
and the Reverb websocket port (`REVERB_PORT`, default `8080`) to the
`app` service. See the
[SSL Certificate Troubleshooting Guide](../troubleshooting/ssl-certificates.md)
for websocket-specific proxy configuration.

### Updating

```bash
git pull
docker compose -f docker-compose.prod.yml build app
docker compose -f docker-compose.prod.yml up -d app
```

Pending migrations run automatically the next time the `app` container
starts.

## Manual

Manual installation has great overlap with [the manual development installation](../installation/manual.md).
We will soon provide this guide to cover topics, specific to the production installation (webserver, certificates etc.).

### Supervisor Configuration for Production

OpenQDA requires background processes for WebSocket (Reverb) and queue workers. Supervisor is recommended for managing these processes in production.

#### Installing Supervisor

On Ubuntu/Debian:
```bash
sudo apt-get update
sudo apt-get install supervisor
```

#### Configuration Files

Template configuration files are provided in `web/docker/8.3/`:

1. **`supervisor-reverb.conf.example`** - WebSocket server configuration
2. **`supervisor-queue.conf.example`** - Queue worker configuration
3. **`supervisor-docker.conf.example`** - Complete configuration for Docker deployments

#### Setting Up Reverb WebSocket Server

1. Copy the template:
```bash
sudo cp web/docker/8.3/supervisor-reverb.conf.example /etc/supervisor/conf.d/reverb.conf
```

2. Edit the configuration:
```bash
sudo nano /etc/supervisor/conf.d/reverb.conf
```

3. Update these values:
   - Replace `/var/www/html` with your Laravel application path
   - Set `REVERB_HOSTNAME` environment variable (e.g., `your-domain.com`)
   - Change `user` to match your web server user (typically `www-data`, `nginx`, or your app user)

4. Update supervisor and start the service:
```bash
sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl start reverb
```

#### Setting Up Queue Worker

1. Copy the template:
```bash
sudo cp web/docker/8.3/supervisor-queue.conf.example /etc/supervisor/conf.d/queue-worker.conf
```

2. Edit the configuration:
```bash
sudo nano /etc/supervisor/conf.d/queue-worker.conf
```

3. Update these values:
   - Replace `/var/www/html` with your Laravel application path
   - Adjust queue names if different from `conversion,default`
   - Change `user` to match your web server user

4. Update supervisor and start the service:
```bash
sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl start queue-worker
```

#### Managing Supervisor Services

Check status of all services:
```bash
sudo supervisorctl status
```

Restart a specific service:
```bash
sudo supervisorctl restart reverb
sudo supervisorctl restart queue-worker
```

Stop a service:
```bash
sudo supervisorctl stop reverb
```

View logs:
```bash
sudo tail -f /var/log/supervisor/reverb.log
sudo tail -f /var/log/supervisor/queue-worker.log
```

#### Docker Deployment

For Docker deployments, use the `supervisor-docker.conf.example` template:

1. In your Dockerfile, copy the configuration:
```dockerfile
COPY web/docker/8.3/supervisor-docker.conf.example /etc/supervisor/conf.d/supervisord.conf
```

2. Set required environment variables in your `docker-compose.yml`:
```yaml
environment:
  - SUPERVISOR_PHP_COMMAND=/usr/bin/php -d variables_order=EGPCS /var/www/html/artisan serve --host=0.0.0.0 --port=80
  - SUPERVISOR_PHP_USER=sail
  - REVERB_HOSTNAME=localhost
```

3. Ensure supervisor is installed in your Docker image and started as the entrypoint.

### SSL Certificate Configuration

For SSL certificate setup with the WebSocket server, refer to:
- [SSL Certificate Troubleshooting Guide](../troubleshooting/ssl-certificates.md) - Essential reading if your WebSocket server has certificate issues
- [Manual Installation - Real-Time Configuration](../installation/manual.md#real-time-configuration) - Initial SSL setup instructions
