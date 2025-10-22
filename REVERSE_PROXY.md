# NetBox derrière un Reverse Proxy

Ce guide explique comment configurer NetBox pour fonctionner derrière un reverse proxy (Nginx, HAProxy, Traefik, etc.).

## Installation avec support Reverse Proxy

### Méthode 1: Variables d'environnement

```bash
# Installation avec reverse proxy HTTPS
BEHIND_REVERSE_PROXY=true \
DOMAIN_NAME=netbox.example.com \
USE_HTTPS=true \
REVERSE_PROXY_NETWORK="10.0.0.0/8,172.16.0.0/12" \
curl -fsSL https://raw.githubusercontent.com/tiagomatiastm-prog/netbox-installer/master/install-netbox.sh | sudo bash
```

### Méthode 2: Export puis installation

```bash
# Définir les variables
export BEHIND_REVERSE_PROXY=true
export DOMAIN_NAME=netbox.example.com
export USE_HTTPS=true
export REVERSE_PROXY_NETWORK="192.168.1.0/24"

# Lancer l'installation
curl -fsSL https://raw.githubusercontent.com/tiagomatiastm-prog/netbox-installer/master/install-netbox.sh | sudo -E bash
```

## Variables disponibles

| Variable | Valeur par défaut | Description |
|----------|-------------------|-------------|
| `BEHIND_REVERSE_PROXY` | `false` | Activer le mode reverse proxy |
| `DOMAIN_NAME` | (vide) | Nom de domaine pour NetBox |
| `USE_HTTPS` | `false` | Le reverse proxy utilise HTTPS |
| `REVERSE_PROXY_NETWORK` | `10.0.0.0/8,172.16.0.0/12,192.168.0.0/16` | Réseaux du reverse proxy (séparés par virgule) |

## Configuration du Reverse Proxy

### Nginx (recommandé)

#### Configuration basique HTTP

```nginx
server {
    listen 80;
    server_name netbox.example.com;

    client_max_body_size 25m;

    location / {
        proxy_pass http://172.16.25.47:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
    }
}
```

#### Configuration HTTPS avec Let's Encrypt

```nginx
server {
    listen 443 ssl http2;
    server_name netbox.example.com;

    # Certificats SSL (Let's Encrypt)
    ssl_certificate /etc/letsencrypt/live/netbox.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/netbox.example.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # Headers de sécurité
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    client_max_body_size 25m;

    location / {
        proxy_pass http://172.16.25.47:8080;

        # Headers requis
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host $host;

        # Support WebSocket
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        # Timeouts
        proxy_connect_timeout 600;
        proxy_send_timeout 600;
        proxy_read_timeout 600;
    }
}

# Redirection HTTP vers HTTPS
server {
    listen 80;
    server_name netbox.example.com;
    return 301 https://$server_name$request_uri;
}
```

### HAProxy

```haproxy
frontend netbox_frontend
    bind *:443 ssl crt /etc/haproxy/certs/netbox.pem
    mode http

    # Headers pour NetBox
    option forwardfor
    http-request add-header X-Forwarded-Proto https
    http-request set-header X-Forwarded-Host %[req.hdr(Host)]
    http-request set-header X-Forwarded-Port %[dst_port]

    default_backend netbox_backend

backend netbox_backend
    mode http
    balance roundrobin

    # Health check
    option httpchk GET /login/
    http-check expect status 200

    # Serveur NetBox
    server netbox1 172.16.25.47:8080 check
```

### Traefik (Docker)

#### docker-compose.yml

```yaml
version: '3.8'

services:
  traefik:
    image: traefik:v2.10
    command:
      - "--providers.docker=true"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencrypt.acme.email=admin@example.com"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
      - "--certificatesresolvers.letsencrypt.acme.tlschallenge=true"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./letsencrypt:/letsencrypt
    labels:
      # Redirection HTTP vers HTTPS
      - "traefik.http.routers.http-catchall.rule=hostregexp(`{host:.+}`)"
      - "traefik.http.routers.http-catchall.entrypoints=web"
      - "traefik.http.routers.http-catchall.middlewares=redirect-to-https"
      - "traefik.http.middlewares.redirect-to-https.redirectscheme.scheme=https"

  netbox-proxy:
    image: nginx:alpine
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.netbox.rule=Host(`netbox.example.com`)"
      - "traefik.http.routers.netbox.entrypoints=websecure"
      - "traefik.http.routers.netbox.tls.certresolver=letsencrypt"
      - "traefik.http.services.netbox.loadbalancer.server.port=80"
    environment:
      - NETBOX_SERVER=172.16.25.47:8080
    command: >
      sh -c "echo 'server {
        listen 80;
        location / {
          proxy_pass http://172.16.25.47:8080;
          proxy_set_header Host \$$host;
          proxy_set_header X-Real-IP \$$remote_addr;
          proxy_set_header X-Forwarded-For \$$proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto \$$scheme;
        }
      }' > /etc/nginx/conf.d/default.conf && nginx -g 'daemon off;'"
```

### Caddy

```caddy
netbox.example.com {
    reverse_proxy 172.16.25.47:8080 {
        header_up Host {host}
        header_up X-Real-IP {remote}
        header_up X-Forwarded-For {remote}
        header_up X-Forwarded-Proto {scheme}
        header_up X-Forwarded-Host {host}
    }
}
```

## Configuration manuelle post-installation

Si vous avez déjà installé NetBox sans reverse proxy, vous pouvez le configurer manuellement :

### 1. Modifier la configuration NetBox

```bash
sudo nano /opt/netbox/netbox/netbox/configuration.py
```

Ajouter/modifier ces lignes :

```python
# ALLOWED_HOSTS
ALLOWED_HOSTS = ['netbox.example.com', '172.16.25.47', 'localhost']

# Pour HTTPS via reverse proxy
SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')

# Configuration reverse proxy
USE_X_FORWARDED_HOST = True
USE_X_FORWARDED_PORT = True
```

### 2. Modifier la configuration Nginx sur le serveur NetBox

```bash
sudo nano /etc/nginx/sites-available/netbox
```

Ajouter la section `real_ip` :

```nginx
server {
    listen 80;
    server_name _;

    # Configuration pour reverse proxy
    real_ip_header X-Forwarded-For;
    set_real_ip_from 10.0.0.0/8;
    set_real_ip_from 172.16.0.0/12;
    set_real_ip_from 192.168.0.0/16;

    client_max_body_size 25m;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $server_name;
    }

    location /static/ {
        alias /opt/netbox/netbox/static/;
    }
}
```

### 3. Redémarrer les services

```bash
# Redémarrer NetBox
sudo supervisorctl restart netbox netbox-rq

# Redémarrer Nginx
sudo systemctl restart nginx
```

## Vérification

### Tester la configuration

```bash
# Depuis le serveur NetBox
curl -I http://localhost:8080

# Depuis le reverse proxy
curl -I http://172.16.25.47:8080

# Depuis l'extérieur
curl -I https://netbox.example.com
```

### Vérifier les logs

```bash
# Logs NetBox
sudo tail -f /var/log/netbox/netbox.log

# Logs Nginx (serveur NetBox)
sudo tail -f /var/log/nginx/error.log

# Logs du reverse proxy
sudo tail -f /var/log/nginx/error.log  # Nginx
sudo tail -f /var/log/haproxy.log      # HAProxy
```

## Problèmes courants

### ERR 1: NetBox affiche "Forbidden (403)"

**Cause**: `ALLOWED_HOSTS` ne contient pas le nom de domaine

**Solution**:
```bash
sudo nano /opt/netbox/netbox/netbox/configuration.py
# Ajouter votre domaine dans ALLOWED_HOSTS
sudo supervisorctl restart netbox
```

### ERR 2: Les redirections HTTPS ne fonctionnent pas

**Cause**: `SECURE_PROXY_SSL_HEADER` non configuré

**Solution**:
```python
# Dans configuration.py
SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')
```

### ERR 3: Les adresses IP des clients sont incorrectes

**Cause**: Configuration `real_ip` manquante

**Solution**: Ajouter les directives `set_real_ip_from` dans Nginx (voir ci-dessus)

### ERR 4: Les fichiers statiques (CSS/JS) ne se chargent pas

**Cause**: Headers ou chemins incorrects

**Solution**:
```bash
# Régénérer les fichiers statiques
cd /opt/netbox
source venv/bin/activate
python3 netbox/manage.py collectstatic --noinput
```

## Exemples complets

### Scénario 1: NetBox derrière Nginx avec HTTPS

```bash
# Sur le serveur reverse proxy (ex: 192.168.1.10)
# Installer Certbot
sudo apt install certbot python3-certbot-nginx

# Obtenir un certificat
sudo certbot --nginx -d netbox.example.com

# Configuration générée automatiquement par Certbot
```

```bash
# Sur le serveur NetBox (172.16.25.47)
BEHIND_REVERSE_PROXY=true \
DOMAIN_NAME=netbox.example.com \
USE_HTTPS=true \
REVERSE_PROXY_NETWORK="192.168.1.0/24" \
curl -fsSL https://raw.githubusercontent.com/tiagomatiastm-prog/netbox-installer/master/install-netbox.sh | sudo bash
```

### Scénario 2: NetBox avec HAProxy en load balancing

```bash
# Installation sur les serveurs NetBox
for server in 172.16.25.47 172.16.25.48; do
    ssh admin@$server "BEHIND_REVERSE_PROXY=true \
    DOMAIN_NAME=netbox.example.com \
    USE_HTTPS=true \
    REVERSE_PROXY_NETWORK='10.0.0.0/8' \
    curl -fsSL https://raw.githubusercontent.com/tiagomatiastm-prog/netbox-installer/master/install-netbox.sh | sudo bash"
done
```

## Ressources

- [Documentation NetBox](https://docs.netbox.dev/)
- [Nginx Documentation](https://nginx.org/en/docs/)
- [HAProxy Documentation](https://www.haproxy.org/#docs)
- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [Let's Encrypt](https://letsencrypt.org/)
