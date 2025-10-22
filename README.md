# NetBox Installer - Installation automatisée

Installation automatique de **NetBox** (IPAM et DCIM) sur **Ubuntu 24.04.3 LTS**.

NetBox est une solution open-source de gestion d'infrastructure réseau développée par DigitalOcean, permettant de gérer :
- IPAM (IP Address Management)
- DCIM (Data Center Infrastructure Management)
- Inventaire réseau
- Documentation réseau

## Caractéristiques

- Installation native (non-Docker) avec Python 3, PostgreSQL et Redis
- Génération automatique de tous les mots de passe
- Configuration de Gunicorn, Supervisor et Nginx
- Interface web accessible sur le port 8080
- Déploiement via script Bash ou Ansible
- Sauvegarde automatique des credentials dans `~/netbox-credentials.md`

## Prérequis

- **Système d'exploitation**: Ubuntu 24.04.3 LTS (64-bit)
- **RAM**: Minimum 2 GB (4 GB recommandé)
- **Disque**: Minimum 10 GB d'espace libre
- **Réseau**: Accès Internet pour télécharger les dépendances
- **Droits**: Accès root (sudo)

## Installation rapide (Script Bash)

### Méthode 1: Installation directe via curl

```bash
# Installation standard
curl -fsSL https://raw.githubusercontent.com/tiagomatiastm-prog/netbox-installer/master/install-netbox.sh | sudo bash
```

### Méthode 2: Installation derrière un reverse proxy

```bash
# Installation avec support reverse proxy HTTPS
BEHIND_REVERSE_PROXY=true \
DOMAIN_NAME=netbox.example.com \
USE_HTTPS=true \
curl -fsSL https://raw.githubusercontent.com/tiagomatiastm-prog/netbox-installer/master/install-netbox.sh | sudo bash
```

**Voir [REVERSE_PROXY.md](REVERSE_PROXY.md) pour plus de détails**

### Méthode 3: Téléchargement et exécution manuelle

```bash
# Télécharger le script
wget https://raw.githubusercontent.com/tiagomatiastm-prog/netbox-installer/master/install-netbox.sh

# Rendre exécutable
chmod +x install-netbox.sh

# Lancer l'installation
sudo ./install-netbox.sh
```

## Installation via Ansible

Voir le fichier [DEPLOYMENT.md](DEPLOYMENT.md) pour les instructions détaillées.

## Migration vers un autre serveur

Pour migrer une instance NetBox existante vers un nouveau serveur, consultez le guide complet [MIGRATION.md](MIGRATION.md).

### Résumé rapide

1. **Préparer l'inventaire**
```bash
# Éditer inventory.ini
nano inventory.ini
```

2. **Lancer le déploiement**
```bash
ansible-playbook -i inventory.ini deploy-netbox.yml
```

## Après l'installation

### Accès à l'interface web

L'interface NetBox sera accessible via :
- **URL principale**: `http://<IP-SERVEUR>` (port 80 via Nginx)
- **URL directe**: `http://<IP-SERVEUR>:8080` (Gunicorn direct)

### Identifiants par défaut

- **Utilisateur**: `admin`
- **Mot de passe**: Généré automatiquement et sauvegardé dans `~/netbox-credentials.md`

### Fichier de credentials

Tous les mots de passe et informations de connexion sont sauvegardés dans :
```
~/netbox-credentials.md
```

Ce fichier contient :
- Identifiants de connexion NetBox (admin)
- Mot de passe PostgreSQL
- Mot de passe Redis
- Secret key Django
- Commandes utiles pour gérer l'installation

## Structure du projet

```
netbox-installer/
├── install-netbox.sh          # Script d'installation Bash
├── deploy-netbox.yml          # Playbook Ansible
├── inventory.ini              # Inventaire Ansible
├── templates/
│   └── configuration.py.j2    # Template de configuration NetBox
├── README.md                  # Ce fichier
├── DEPLOYMENT.md              # Guide de déploiement Ansible
├── REVERSE_PROXY.md           # Guide de configuration reverse proxy
├── MIGRATION.md               # Guide de migration vers un autre serveur
└── UPGRADE.md                 # Guide de mise à jour de NetBox
```

## Gestion des services

### Vérifier le statut

```bash
# Services NetBox (via Supervisor)
sudo supervisorctl status netbox netbox-rq

# Nginx
sudo systemctl status nginx

# PostgreSQL
sudo systemctl status postgresql

# Redis
sudo systemctl status redis-server
```

### Redémarrer NetBox

```bash
sudo supervisorctl restart netbox netbox-rq
```

### Consulter les logs

```bash
# Logs NetBox
sudo tail -f /var/log/netbox/netbox.log

# Logs worker RQ
sudo tail -f /var/log/netbox/netbox-rq.log

# Logs Nginx
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

## Gestion de NetBox

### Accéder à la console Django

```bash
cd /opt/netbox
source venv/bin/activate
python3 netbox/manage.py shell
```

### Créer un nouvel utilisateur

```bash
cd /opt/netbox
source venv/bin/activate
python3 netbox/manage.py createsuperuser
```

### Sauvegarder la base de données

```bash
sudo -u postgres pg_dump netbox > netbox_backup_$(date +%Y%m%d).sql
```

### Restaurer la base de données

```bash
sudo -u postgres psql netbox < netbox_backup_20250101.sql
```

## Mise à jour de NetBox

Pour mettre à jour NetBox vers une version plus récente, consultez le guide complet [UPGRADE.md](UPGRADE.md).

### Script automatisé de mise à jour

```bash
# Installer le script de mise à jour
curl -fsSL https://raw.githubusercontent.com/tiagomatiastm-prog/netbox-installer/master/UPGRADE.md | grep -A 999 "sudo tee /usr/local/bin/netbox-upgrade.sh" | head -n 100 > /tmp/install-upgrade.sh
bash /tmp/install-upgrade.sh

# Utilisation
sudo /usr/local/bin/netbox-upgrade.sh 4.2.0  # Remplacer par la version désirée
```

### Mise à jour manuelle (résumé)

```bash
# 1. Sauvegarde complète
sudo -u postgres pg_dump netbox > /tmp/netbox-backup.sql

# 2. Télécharger et installer la nouvelle version
cd /opt/netbox
sudo wget https://github.com/netbox-community/netbox/archive/refs/tags/vX.X.X.tar.gz
# ... (voir UPGRADE.md pour la procédure complète)

# 3. Appliquer les migrations
python3 netbox/manage.py migrate

# 4. Redémarrer
sudo supervisorctl restart netbox netbox-rq
```

**Voir [UPGRADE.md](UPGRADE.md) pour tous les détails**

## Dépannage

### NetBox ne démarre pas

```bash
# Vérifier les logs
sudo tail -f /var/log/netbox/netbox.log

# Vérifier que PostgreSQL fonctionne
sudo systemctl status postgresql

# Vérifier que Redis fonctionne
sudo systemctl status redis-server

# Redémarrer manuellement
sudo supervisorctl restart netbox netbox-rq
```

### Erreur de connexion à la base de données

```bash
# Tester la connexion PostgreSQL
sudo -u postgres psql -d netbox -U netbox

# Vérifier le mot de passe dans la configuration
cat /opt/netbox/netbox/netbox/configuration.py | grep PASSWORD
```

### Impossible d'accéder à l'interface web

```bash
# Vérifier que Nginx est démarré
sudo systemctl status nginx

# Vérifier la configuration Nginx
sudo nginx -t

# Vérifier les logs Nginx
sudo tail -f /var/log/nginx/error.log
```

## Sécurité

### Recommandations post-installation

1. **Changer le mot de passe admin** dès la première connexion
2. **Configurer HTTPS** avec Let's Encrypt ou un certificat SSL
3. **Configurer un pare-feu** (UFW ou iptables)
4. **Activer les sauvegardes automatiques** de la base de données
5. **Limiter l'accès** à l'interface web par IP si possible

### Configurer le pare-feu UFW

```bash
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS (si configuré)
sudo ufw enable
```

## Documentation officielle

- [NetBox Documentation](https://docs.netbox.dev/)
- [NetBox GitHub](https://github.com/netbox-community/netbox)
- [NetBox Community](https://github.com/netbox-community)

## Support

Pour toute question ou problème :
1. Consultez les logs: `/var/log/netbox/netbox.log`
2. Vérifiez le fichier de credentials: `~/netbox-credentials.md`
3. Consultez la documentation officielle NetBox

## Licence

Ce script d'installation est fourni "tel quel", sans garantie d'aucune sorte.

NetBox est distribué sous licence Apache 2.0.

## Auteur

Tiago Matias

## Changelog

### v1.0.0 (2025-10-22)
- Installation initiale automatisée
- Support Ubuntu 24.04.3 LTS
- Génération automatique des mots de passe
- Configuration Nginx + Gunicorn + Supervisor
- Support PostgreSQL et Redis
