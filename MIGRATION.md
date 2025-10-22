# Migration de NetBox vers un nouveau serveur

Ce guide explique comment migrer une instance NetBox existante vers un nouveau serveur Ubuntu 24.04.3.

## Vue d'ensemble

La migration de NetBox implique :
1. Sauvegarde de la base de données PostgreSQL
2. Sauvegarde des fichiers média (uploads)
3. Sauvegarde de la configuration
4. Installation de NetBox sur le nouveau serveur
5. Restauration des données
6. Vérification et tests

## Prérequis

- Accès SSH au serveur source (ancien)
- Accès SSH au serveur destination (nouveau)
- Droits root/sudo sur les deux serveurs
- Espace disque suffisant pour les sauvegardes

## Étape 1 : Sauvegarde sur le serveur source

### 1.1 Créer un dossier de sauvegarde

```bash
# Sur le serveur source
export BACKUP_DIR="/tmp/netbox-migration-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
cd "$BACKUP_DIR"
```

### 1.2 Sauvegarder la base de données PostgreSQL

```bash
# Sauvegarder la base de données
sudo -u postgres pg_dump netbox > netbox-database.sql

# Vérifier la sauvegarde
ls -lh netbox-database.sql
```

### 1.3 Sauvegarder les fichiers média

```bash
# Sauvegarder les fichiers uploadés par les utilisateurs
sudo tar -czf netbox-media.tar.gz -C /opt/netbox/netbox media/

# Vérifier
ls -lh netbox-media.tar.gz
```

### 1.4 Sauvegarder la configuration

```bash
# Sauvegarder le fichier de configuration
sudo cp /opt/netbox/netbox/netbox/configuration.py netbox-configuration.py

# Sauvegarder les informations de version
cd /opt/netbox
NETBOX_VERSION=$(cat /opt/netbox/netbox/netbox/settings.py | grep "^VERSION = " | cut -d"'" -f2)
echo "$NETBOX_VERSION" > "$BACKUP_DIR/netbox-version.txt"

# Sauvegarder les credentials (si existant)
if [ -f ~/netbox-credentials.md ]; then
    cp ~/netbox-credentials.md "$BACKUP_DIR/"
fi
```

### 1.5 Créer une archive complète

```bash
cd "$BACKUP_DIR"
tar -czf netbox-backup-complete.tar.gz *.sql *.tar.gz *.py *.txt *.md 2>/dev/null

echo "Sauvegarde créée dans: $BACKUP_DIR"
ls -lh netbox-backup-complete.tar.gz
```

### 1.6 Transférer la sauvegarde

**Option A : Via SCP (recommandé)**

```bash
# Depuis le serveur source, envoyer vers le nouveau serveur
scp netbox-backup-complete.tar.gz user@NEW_SERVER_IP:/tmp/

# Ou depuis votre machine locale
scp root@OLD_SERVER_IP:$BACKUP_DIR/netbox-backup-complete.tar.gz /tmp/
scp /tmp/netbox-backup-complete.tar.gz user@NEW_SERVER_IP:/tmp/
```

**Option B : Via un serveur intermédiaire**

```bash
# Si vous avez un serveur de stockage
scp netbox-backup-complete.tar.gz user@storage-server:/backups/
```

## Étape 2 : Installation sur le nouveau serveur

### 2.1 Installer NetBox (version identique)

```bash
# Sur le nouveau serveur
# Récupérer la version depuis votre sauvegarde ou utiliser la même version

# Installation automatique
curl -fsSL https://raw.githubusercontent.com/tiagomatiastm-prog/netbox-installer/master/install-netbox.sh | sudo bash
```

**OU** si vous avez besoin d'une version spécifique, modifier le script temporairement.

### 2.2 Arrêter les services NetBox

```bash
# Sur le nouveau serveur
sudo supervisorctl stop netbox netbox-rq
```

## Étape 3 : Restauration des données

### 3.1 Extraire la sauvegarde

```bash
# Sur le nouveau serveur
cd /tmp
tar -xzf netbox-backup-complete.tar.gz
```

### 3.2 Restaurer la base de données

```bash
# Supprimer la base de données actuelle et la recréer
sudo -u postgres psql << EOF
DROP DATABASE IF EXISTS netbox;
CREATE DATABASE netbox;
GRANT ALL PRIVILEGES ON DATABASE netbox TO netbox;
\c netbox
GRANT CREATE ON SCHEMA public TO netbox;
EOF

# Restaurer les données
sudo -u postgres psql netbox < /tmp/netbox-database.sql

# Vérifier
sudo -u postgres psql -d netbox -c "SELECT COUNT(*) FROM django_migrations;"
```

### 3.3 Restaurer les fichiers média

```bash
# Restaurer les fichiers uploadés
cd /opt/netbox/netbox
sudo rm -rf media/*
sudo tar -xzf /tmp/netbox-media.tar.gz -C /opt/netbox/netbox/

# Corriger les permissions
sudo chown -R netbox:netbox /opt/netbox/netbox/media/
```

### 3.4 Restaurer/Vérifier la configuration

```bash
# Comparer les configurations
sudo diff /tmp/netbox-configuration.py /opt/netbox/netbox/netbox/configuration.py

# Si nécessaire, copier certains paramètres manuellement
# ATTENTION: Ne pas tout écraser, vérifier les mots de passe DB/Redis du nouveau serveur
```

**Important** : Vous devrez probablement ajuster :
- `DATABASE['PASSWORD']` (utiliser le nouveau mot de passe PostgreSQL)
- `REDIS['tasks']['PASSWORD']` et `REDIS['caching']['PASSWORD']` (utiliser le nouveau mot de passe Redis)
- `SECRET_KEY` peut être conservé de l'ancien serveur pour préserver les sessions

### 3.5 Appliquer les migrations (si versions différentes)

```bash
cd /opt/netbox
source venv/bin/activate
python3 netbox/manage.py migrate
python3 netbox/manage.py collectstatic --noinput
deactivate
```

## Étape 4 : Redémarrage et vérification

### 4.1 Redémarrer les services

```bash
# Redémarrer NetBox
sudo supervisorctl restart netbox netbox-rq

# Vérifier le statut
sudo supervisorctl status netbox netbox-rq

# Vérifier les logs
sudo tail -f /var/log/netbox/netbox.log
```

### 4.2 Vérifier l'accès web

```bash
# Tester l'accès local
curl -I http://localhost:8080

# Depuis votre navigateur
http://<NEW_SERVER_IP>:8080
```

### 4.3 Vérifier les données

Connectez-vous à l'interface web et vérifiez :
- [ ] Les utilisateurs existent
- [ ] Les données IPAM sont présentes
- [ ] Les équipements sont visibles
- [ ] Les fichiers uploadés sont accessibles
- [ ] Les recherches fonctionnent

## Étape 5 : Migration de l'adresse IP (optionnel)

Si vous voulez que le nouveau serveur utilise l'IP de l'ancien :

### Option A : Changer l'IP du nouveau serveur

```bash
# Sur le nouveau serveur
sudo nano /etc/netplan/01-netcfg.yaml

# Modifier avec l'ancienne IP
network:
  version: 2
  ethernets:
    ens18:  # Adapter le nom de l'interface
      addresses:
        - OLD_SERVER_IP/24
      gateway4: YOUR_GATEWAY
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]

# Appliquer
sudo netplan apply
```

### Option B : Utiliser un reverse proxy ou load balancer

Configurez votre reverse proxy pour pointer vers le nouveau serveur.

## Étape 6 : Nettoyage

### 6.1 Vérifier que tout fonctionne

Attendez quelques heures/jours pour vous assurer que tout fonctionne correctement.

### 6.2 Nettoyer les sauvegardes temporaires

```bash
# Sur le nouveau serveur
sudo rm -rf /tmp/netbox-*.sql /tmp/netbox-*.tar.gz /tmp/netbox-*.py

# Sur l'ancien serveur (APRÈS confirmation que tout fonctionne)
# ATTENTION: Ne pas supprimer avant d'être SÛR !
# rm -rf $BACKUP_DIR
```

### 6.3 Sauvegarder l'archive de migration

```bash
# Conserver une copie de l'archive de migration
sudo mkdir -p /root/backups
sudo mv /tmp/netbox-backup-complete.tar.gz /root/backups/
```

## Scénarios spéciaux

### Migration avec changement de domaine

Si vous changez de nom de domaine :

```bash
# Modifier la configuration
sudo nano /opt/netbox/netbox/netbox/configuration.py

# Ajuster ALLOWED_HOSTS
ALLOWED_HOSTS = ['new-domain.com', 'old-domain.com', 'IP']

# Si reverse proxy HTTPS
CSRF_TRUSTED_ORIGINS = ['https://new-domain.com']

# Redémarrer
sudo supervisorctl restart netbox netbox-rq
```

### Migration vers une version plus récente de NetBox

**IMPORTANT** : Si les versions source et destination sont différentes, cela peut poser des problèmes de compatibilité de base de données.

**Approche recommandée** :

1. **Mettre à jour le serveur source** vers la version cible AVANT la migration
2. **Valider** que la mise à jour fonctionne correctement
3. **Ensuite** faire la migration vers le nouveau serveur

Pour la procédure complète de mise à jour, consultez **[UPGRADE.md](UPGRADE.md)**.

**Résumé rapide** :

```bash
# Sur le serveur SOURCE, mettre à jour NetBox d'abord
sudo /usr/local/bin/netbox-upgrade.sh 4.2.0  # Version cible

# Valider pendant quelques jours

# Puis faire la migration normale vers le nouveau serveur
# avec la MÊME version installée sur les deux serveurs
```

**Alternative** (nouvelle installation avec version différente) :

```bash
# Sur le nouveau serveur, installer la version CIBLE
# puis appliquer les migrations lors de la restauration
cd /opt/netbox
source venv/bin/activate
python3 netbox/manage.py migrate
python3 netbox/manage.py collectstatic --noinput
sudo supervisorctl restart netbox netbox-rq
```

Voir **[UPGRADE.md](UPGRADE.md)** pour tous les détails.

### Migration avec plusieurs serveurs (HA)

Pour une architecture haute disponibilité :

1. Installer NetBox sur plusieurs serveurs
2. Utiliser une base de données PostgreSQL externe partagée
3. Utiliser Redis externe ou Redis Sentinel
4. Configurer un load balancer (HAProxy, Nginx)

## Dépannage

### La base de données ne se restaure pas

```bash
# Vérifier la version de PostgreSQL
psql --version

# Si différence de version majeure, utiliser pg_upgrade ou exporter en SQL pur
sudo -u postgres pg_dump --no-owner --no-acl netbox > netbox-clean.sql
```

### Erreurs de permissions

```bash
# Corriger les permissions
sudo chown -R netbox:netbox /opt/netbox/netbox/media/
sudo chmod -R 755 /opt/netbox/netbox/media/
```

### Les sessions utilisateurs ne fonctionnent pas

```bash
# Vérifier que le SECRET_KEY est identique à l'ancien serveur
# Sinon, tous les utilisateurs devront se reconnecter
```

### Redis connection error

```bash
# Vérifier que les mots de passe Redis sont corrects dans configuration.py
sudo nano /opt/netbox/netbox/netbox/configuration.py

# Tester la connexion Redis
redis-cli -a "YOUR_REDIS_PASSWORD" ping
```

## Checklist complète de migration

- [ ] Sauvegarde de la base de données PostgreSQL
- [ ] Sauvegarde des fichiers média
- [ ] Sauvegarde de la configuration
- [ ] Note de la version de NetBox
- [ ] Transfert de la sauvegarde vers le nouveau serveur
- [ ] Installation de NetBox sur le nouveau serveur
- [ ] Arrêt des services NetBox
- [ ] Restauration de la base de données
- [ ] Restauration des fichiers média
- [ ] Vérification/ajustement de la configuration
- [ ] Application des migrations
- [ ] Redémarrage des services
- [ ] Test de l'interface web
- [ ] Vérification des données
- [ ] Vérification des fichiers uploadés
- [ ] Test de connexion utilisateurs
- [ ] Mise à jour DNS/reverse proxy (si applicable)
- [ ] Surveillance pendant 24-48h
- [ ] Désactivation de l'ancien serveur
- [ ] Nettoyage des fichiers temporaires

## Script automatisé de sauvegarde

Pour faciliter les sauvegardes régulières, créez ce script :

```bash
sudo tee /usr/local/bin/netbox-backup.sh > /dev/null << 'EOF'
#!/bin/bash

BACKUP_DIR="/var/backups/netbox/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Base de données
sudo -u postgres pg_dump netbox > "$BACKUP_DIR/netbox-db.sql"

# Fichiers média
tar -czf "$BACKUP_DIR/netbox-media.tar.gz" -C /opt/netbox/netbox media/

# Configuration
cp /opt/netbox/netbox/netbox/configuration.py "$BACKUP_DIR/"

# Archive complète
cd "$BACKUP_DIR/.."
DIRNAME=$(basename "$BACKUP_DIR")
tar -czf "$DIRNAME.tar.gz" "$DIRNAME"
rm -rf "$DIRNAME"

# Nettoyer les anciennes sauvegardes (garder 7 jours)
find /var/backups/netbox/ -name "*.tar.gz" -mtime +7 -delete

echo "Sauvegarde créée: /var/backups/netbox/$DIRNAME.tar.gz"
EOF

sudo chmod +x /usr/local/bin/netbox-backup.sh
```

### Automatiser avec cron

```bash
# Sauvegarde quotidienne à 2h du matin
sudo crontab -e

# Ajouter :
0 2 * * * /usr/local/bin/netbox-backup.sh >> /var/log/netbox-backup.log 2>&1
```

## Ressources

- [Documentation officielle NetBox - Migration](https://docs.netbox.dev/)
- [PostgreSQL Backup and Restore](https://www.postgresql.org/docs/current/backup.html)
- [NetBox GitHub - Issues](https://github.com/netbox-community/netbox/issues)

## Support

En cas de problème durant la migration :
1. Vérifier les logs : `/var/log/netbox/netbox.log`
2. Vérifier PostgreSQL : `sudo -u postgres psql -d netbox -c "SELECT version();"`
3. Vérifier Redis : `redis-cli ping`
4. Consulter la documentation officielle NetBox
