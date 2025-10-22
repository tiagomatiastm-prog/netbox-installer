#!/bin/bash

#######################################################
# Script d'installation automatique de NetBox
# Système supporté: Ubuntu 24.04.3 LTS
# Version NetBox: 4.1.x (dernière stable)
#######################################################

set -e

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Variables
NETBOX_VERSION="4.1"
NETBOX_PORT="8080"
INSTALL_DIR="/opt/netbox"
LOG_FILE="/var/log/netbox-installation.log"

# Détecter le vrai utilisateur (même si exécuté avec sudo)
if [ -n "$SUDO_USER" ]; then
    REAL_USER="$SUDO_USER"
    REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    REAL_USER="$USER"
    REAL_HOME="$HOME"
fi

CREDENTIALS_FILE="$REAL_HOME/netbox-credentials.md"

# Fonction de logging
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

# Fonction pour générer un mot de passe aléatoire (alphanumérique uniquement pour éviter les problèmes avec sed)
generate_password() {
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 25
}

# Vérifications préliminaires
check_requirements() {
    log "Vérification des prérequis..."

    # Vérifier si Ubuntu 24.04
    if ! grep -q "Ubuntu 24.04" /etc/os-release 2>/dev/null; then
        warning "Ce script est optimisé pour Ubuntu 24.04.3 LTS"
    fi

    # Vérifier si root
    if [[ $EUID -ne 0 ]]; then
        error "Ce script doit être exécuté en tant que root (sudo)"
    fi

    log "Prérequis vérifiés avec succès"
}

# Génération des mots de passe
generate_credentials() {
    log "Génération des identifiants sécurisés..."

    DB_PASSWORD=$(generate_password)
    REDIS_PASSWORD=$(generate_password)
    SECRET_KEY=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 50)
    SUPERUSER_PASSWORD=$(generate_password)

    log "Identifiants générés avec succès"
}

# Installation des dépendances système
install_dependencies() {
    log "Mise à jour du système et installation des dépendances..."

    export DEBIAN_FRONTEND=noninteractive

    apt-get update -qq
    apt-get upgrade -y -qq

    # Installation des paquets requis
    apt-get install -y -qq \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev \
        build-essential \
        libxml2-dev \
        libxslt1-dev \
        libffi-dev \
        libpq-dev \
        libssl-dev \
        zlib1g-dev \
        postgresql \
        postgresql-contrib \
        redis-server \
        git \
        nginx \
        supervisor \
        curl \
        wget

    log "Dépendances installées avec succès"
}

# Configuration de PostgreSQL
setup_postgresql() {
    log "Configuration de PostgreSQL..."

    # Démarrer PostgreSQL
    systemctl start postgresql
    systemctl enable postgresql

    # Créer la base de données et l'utilisateur
    sudo -u postgres psql -c "CREATE DATABASE netbox;"
    sudo -u postgres psql -c "CREATE USER netbox WITH PASSWORD '$DB_PASSWORD';"
    sudo -u postgres psql -c "ALTER DATABASE netbox OWNER TO netbox;"
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE netbox TO netbox;"

    log "PostgreSQL configuré avec succès"
}

# Configuration de Redis
setup_redis() {
    log "Configuration de Redis..."

    # Configurer Redis avec mot de passe
    sed -i "s/# requirepass foobared/requirepass $REDIS_PASSWORD/" /etc/redis/redis.conf

    # Démarrer Redis
    systemctl restart redis-server
    systemctl enable redis-server

    log "Redis configuré avec succès"
}

# Installation de NetBox
install_netbox() {
    log "Installation de NetBox..."

    # Télécharger NetBox
    cd /opt

    # Récupérer la dernière version stable
    LATEST_VERSION=$(curl -s https://api.github.com/repos/netbox-community/netbox/releases | grep -oP '"tag_name": "v\K[0-9.]+' | head -1)

    if [ -z "$LATEST_VERSION" ]; then
        LATEST_VERSION="4.1.6"
        warning "Impossible de détecter la dernière version, utilisation de v$LATEST_VERSION"
    fi

    log "Téléchargement de NetBox v$LATEST_VERSION..."
    wget -q "https://github.com/netbox-community/netbox/archive/refs/tags/v${LATEST_VERSION}.tar.gz" -O netbox.tar.gz
    tar -xzf netbox.tar.gz
    ln -s "netbox-${LATEST_VERSION}" netbox
    rm netbox.tar.gz

    log "NetBox téléchargé avec succès"
}

# Configuration de NetBox
configure_netbox() {
    log "Configuration de NetBox..."

    cd "$INSTALL_DIR"

    # Copier le fichier de configuration
    cp netbox/netbox/configuration_example.py netbox/netbox/configuration.py

    # Configurer la base de données avec protection des variables
    cat > netbox/netbox/configuration.py << 'CONFIGEOF'
# NetBox Configuration
import os

ALLOWED_HOSTS = ['*']

DATABASE = {
    'NAME': 'netbox',
    'USER': 'netbox',
    'PASSWORD': 'DB_PASSWORD_PLACEHOLDER',
    'HOST': 'localhost',
    'PORT': '',
    'CONN_MAX_AGE': 300,
}

REDIS = {
    'tasks': {
        'HOST': 'localhost',
        'PORT': 6379,
        'PASSWORD': 'REDIS_PASSWORD_PLACEHOLDER',
        'DATABASE': 0,
        'SSL': False,
    },
    'caching': {
        'HOST': 'localhost',
        'PORT': 6379,
        'PASSWORD': 'REDIS_PASSWORD_PLACEHOLDER',
        'DATABASE': 1,
        'SSL': False,
    }
}

SECRET_KEY = 'SECRET_KEY_PLACEHOLDER'

# Désactiver le mode debug en production
DEBUG = False

# Configuration des médias
MEDIA_ROOT = os.path.join(os.path.dirname(__file__), 'media')

CONFIGEOF

    # Remplacer les placeholders par les vraies valeurs
    sed -i "s/DB_PASSWORD_PLACEHOLDER/$DB_PASSWORD/g" netbox/netbox/configuration.py
    sed -i "s/REDIS_PASSWORD_PLACEHOLDER/$REDIS_PASSWORD/g" netbox/netbox/configuration.py
    sed -i "s/SECRET_KEY_PLACEHOLDER/$SECRET_KEY/g" netbox/netbox/configuration.py

    log "Fichier de configuration créé"
}

# Installation des dépendances Python
install_python_dependencies() {
    log "Installation des dépendances Python..."

    cd "$INSTALL_DIR"

    # Créer l'environnement virtuel Python
    python3 -m venv venv
    source venv/bin/activate

    # Mettre à jour pip
    pip install --upgrade pip

    # Installer NetBox
    pip install -r requirements.txt

    log "Dépendances Python installées"
}

# Initialisation de la base de données
initialize_database() {
    log "Initialisation de la base de données NetBox..."

    cd "$INSTALL_DIR"
    source venv/bin/activate

    # Migrations de la base de données
    python3 netbox/manage.py migrate

    # Créer le superutilisateur
    log "Création du superutilisateur admin..."
    DJANGO_SUPERUSER_PASSWORD="$SUPERUSER_PASSWORD" python3 netbox/manage.py createsuperuser \
        --username admin \
        --email admin@localhost \
        --noinput

    # Collecter les fichiers statiques
    python3 netbox/manage.py collectstatic --noinput

    log "Base de données initialisée avec succès"
}

# Configuration de Gunicorn
setup_gunicorn() {
    log "Configuration de Gunicorn..."

    # Copier le fichier de configuration
    cp "$INSTALL_DIR/contrib/gunicorn.py" "$INSTALL_DIR/gunicorn.py"

    # Modifier le port
    sed -i "s/bind = '127.0.0.1:8001'/bind = '127.0.0.1:$NETBOX_PORT'/" "$INSTALL_DIR/gunicorn.py"

    log "Gunicorn configuré"
}

# Configuration de Supervisor
setup_supervisor() {
    log "Configuration de Supervisor..."

    cat > /etc/supervisor/conf.d/netbox.conf << EOF
[program:netbox]
command=$INSTALL_DIR/venv/bin/gunicorn --config $INSTALL_DIR/gunicorn.py netbox.wsgi
directory=$INSTALL_DIR/netbox
user=www-data
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/log/netbox/netbox.log

[program:netbox-rq]
command=$INSTALL_DIR/venv/bin/python $INSTALL_DIR/netbox/manage.py rqworker
directory=$INSTALL_DIR/netbox
user=www-data
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/log/netbox/netbox-rq.log
EOF

    # Créer le répertoire de logs
    mkdir -p /var/log/netbox
    chown www-data:www-data /var/log/netbox

    # Permissions sur le répertoire NetBox
    chown -R www-data:www-data "$INSTALL_DIR"

    # Recharger Supervisor
    supervisorctl reread
    supervisorctl update
    supervisorctl start netbox netbox-rq

    log "Supervisor configuré et services démarrés"
}

# Configuration de Nginx (optionnel, pour accès direct)
setup_nginx() {
    log "Configuration de Nginx..."

    cat > /etc/nginx/sites-available/netbox << EOF
server {
    listen 80;
    server_name _;

    client_max_body_size 25m;

    location / {
        proxy_pass http://127.0.0.1:$NETBOX_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /static/ {
        alias $INSTALL_DIR/netbox/static/;
    }
}
EOF

    # Activer le site
    ln -sf /etc/nginx/sites-available/netbox /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default

    # Tester et redémarrer Nginx
    nginx -t
    systemctl restart nginx
    systemctl enable nginx

    log "Nginx configuré avec succès"
}

# Sauvegarde des credentials
save_credentials() {
    log "Sauvegarde des identifiants dans $CREDENTIALS_FILE..."

    cat > "$CREDENTIALS_FILE" << EOF
# NetBox - Informations d'installation

**Date d'installation:** $(date '+%Y-%m-%d %H:%M:%S')
**Serveur:** $(hostname)
**IP:** $(hostname -I | awk '{print $1}')

---

## Accès NetBox

- **URL:** http://$(hostname -I | awk '{print $1}')
- **Port direct:** http://$(hostname -I | awk '{print $1}'):$NETBOX_PORT
- **Utilisateur:** admin
- **Mot de passe:** $SUPERUSER_PASSWORD

---

## Base de données PostgreSQL

- **Base de données:** netbox
- **Utilisateur:** netbox
- **Mot de passe:** $DB_PASSWORD
- **Host:** localhost
- **Port:** 5432

---

## Redis

- **Mot de passe:** $REDIS_PASSWORD
- **Port:** 6379

---

## Configuration

- **Répertoire d'installation:** $INSTALL_DIR
- **Fichier de configuration:** $INSTALL_DIR/netbox/netbox/configuration.py
- **Secret Key:** $SECRET_KEY
- **Logs:** /var/log/netbox/

---

## Commandes utiles

### Gérer les services
\`\`\`bash
# Statut des services NetBox
sudo supervisorctl status netbox netbox-rq

# Redémarrer NetBox
sudo supervisorctl restart netbox netbox-rq

# Logs
sudo tail -f /var/log/netbox/netbox.log
\`\`\`

### Gérer Nginx
\`\`\`bash
sudo systemctl status nginx
sudo systemctl restart nginx
\`\`\`

### Accéder à la console Django
\`\`\`bash
cd $INSTALL_DIR
source venv/bin/activate
python3 netbox/manage.py shell
\`\`\`

---

**IMPORTANT:** Conservez ce fichier en lieu sûr !
EOF

    chmod 600 "$CREDENTIALS_FILE"

    # Si exécuté avec sudo, changer le propriétaire du fichier pour l'utilisateur réel
    if [ -n "$SUDO_USER" ]; then
        chown "$SUDO_USER:$SUDO_USER" "$CREDENTIALS_FILE"
    fi

    log "Identifiants sauvegardés dans $CREDENTIALS_FILE"
}

# Affichage du résumé
display_summary() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Installation de NetBox terminée !${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "URL d'accès: ${YELLOW}http://$(hostname -I | awk '{print $1}')${NC}"
    echo -e "Port direct: ${YELLOW}http://$(hostname -I | awk '{print $1}'):$NETBOX_PORT${NC}"
    echo ""
    echo -e "Utilisateur: ${YELLOW}admin${NC}"
    echo -e "Mot de passe: ${YELLOW}$SUPERUSER_PASSWORD${NC}"
    echo ""
    echo -e "Fichier avec tous les identifiants: ${YELLOW}$CREDENTIALS_FILE${NC}"
    echo ""
    echo -e "${GREEN}========================================${NC}"
}

# Programme principal
main() {
    log "Début de l'installation de NetBox..."

    check_requirements
    generate_credentials
    install_dependencies
    setup_postgresql
    setup_redis
    install_netbox
    configure_netbox
    install_python_dependencies
    initialize_database
    setup_gunicorn
    setup_supervisor
    setup_nginx
    save_credentials
    display_summary

    log "Installation terminée avec succès !"
}

# Lancer l'installation
main
