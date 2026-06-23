# dropservice

A rudimentary, lightweight, file send service for your internet server.

## Architecture

Mermaid diagram showing the architecture:

```mermaid
%%{init: {"theme": "dark"}}%%

graph LR
    subgraph Internet
        Client[Client]
        DNS["drop.mydomain.com"]
    end

    subgraph Server
        nginx["nginx<br>Reverse Proxy"]
        DropService["<code>dropservice:8080</code><br>Python Flask API"]
        DropFolder["<code>/srv/drops</code><br/>filesystem"]
    end

    Client -->|HTTP Upload/Download| DNS
    DNS -->|DNS| Server
    nginx --> DropService
    DropService -->|Read/Write| DropFolder
```

## Installation

This project uses `uv` for dependency management.

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

To install the dependencies, run the following command:

```bash
uv sync
```

## Configuration

Copy `.env.example` to `.env` and adjust as needed:

```bash
cp .env.example .env
```

| Variable      | Default       | Description                        |
|---------------|---------------|------------------------------------|
| `UPLOAD_PATH` | `/srv/drops`  | Directory where uploads are stored |
| `PORT`        | `8080`        | Port the Flask server listens on   |

## Deploying

### Filesystem

Create the upload directory and set ownership to match the service user:

```bash
mkdir -p /srv/drops
chown www-data:www-data /srv/drops
```

### systemd

Place the project at `/opt/dropservice` (or adjust `WorkingDirectory` below):

```service
# /etc/systemd/system/drop.service
[Unit]
Description=File drop service
After=network.target

[Service]
WorkingDirectory=/opt/dropservice
EnvironmentFile=/opt/dropservice/.env
ExecStart=/opt/dropservice/.venv/bin/python main.py
Restart=always
User=www-data

[Install]
WantedBy=multi-user.target
```

```bash
systemctl enable --now drop
```

### nginx

```nginx
server {
    server_name drop.mydomain.com;

    client_max_body_size 0;
    proxy_read_timeout 600;
    proxy_request_buffering off;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
    }
}
```

> If you change `PORT` in `.env`, update the `proxy_pass` port here too.
