# Mise à jour de NetBox

Ce guide explique comment mettre à jour NetBox vers une version plus récente de manière sûre.

## Pourquoi les versions différentes posent problème ?

### Problèmes potentiels lors de migrations entre versions différentes :

1. **Schéma de base de données incompatible** :
   - Django génère des migrations entre versions
   - Une restauration de DB sur une version différente peut échouer
   - Les migrations doivent être appliquées dans l'ordre

2. **Dépendances Python incompatibles** :
   - Les requirements.txt changent entre versions
   - Risque de conflits de dépendances

3. **Changements de configuration** :
   - Nouveaux paramètres requis
   - Anciens paramètres dépréciés
   - Structure de configuration modifiée

4. **API et fonctionnalités** :
   - Changements breaking dans l'API REST
   - Fonctionnalités supprimées ou modifiées

## Stratégies de mise à jour

### Option 1 : Mise à jour sur place (Upgrade in-place)

**Recommandé pour** : Sauts de version mineurs (ex: 3.6.0 → 3.7.5)

### Option 2 : Migration avec mise à jour (Backup → Upgrade → Restore)

**Recommandé pour** : Sauts de version majeurs (ex: 3.6.0 → 4.2.0) ou migration de serveur

### Option 3 : Installation parallèle

**Recommandé pour** : Production critique, permet de tester avant de basculer

## Vérifier la compatibilité des versions

Avant toute mise à jour, consultez :

```bash
# Version actuelle
cd /opt/netbox
cat /opt/netbox/netbox/netbox/settings.py | grep "^VERSION = "

# Versions disponibles
curl -s https://api.github.com/repos/netbox-community/netbox/releases | grep "tag_name" | head -10
```

**Notes de version** : https://github.com/netbox-community/netbox/releases

### Tableau de compatibilité

| Version NetBox | Django | Python | PostgreSQL | Redis |
|----------------|--------|--------|------------|-------|
| 4.0+           | 4.2+   | 3.10+  | 12+        | 6.2+  |
| 3.7+           | 4.2+   | 3.10+  | 12+        | 4.0+  |
| 3.6+           | 4.1+   | 3.8+   | 11+        | 4.0+  |
| 3.5+           | 4.0+   | 3.8+   | 11+        | 4.0+  |

## Procédure de mise à jour sur place

### Étape 1 : Sauvegarde complète

**CRITIQUE** : Toujours sauvegarder avant une mise à jour !

```bash
# Créer un dossier de sauvegarde
BACKUP_DIR="/var/backups/netbox-before-upgrade-$(date +%Y%m%d-%H%M%S)"
sudo mkdir -p "$BACKUP_DIR"

# Sauvegarder la base de données
sudo -u postgres pg_dump netbox > "$BACKUP_DIR/netbox-db.sql"

# Sauvegarder les fichiers média
sudo tar -czf "$BACKUP_DIR/netbox-media.tar.gz" -C /opt/netbox/netbox media/

# Sauvegarder la configuration
sudo cp /opt/netbox/netbox/netbox/configuration.py "$BACKUP_DIR/"

# Sauvegarder le répertoire complet (optionnel mais recommandé)
sudo tar -czf "$BACKUP_DIR/netbox-full.tar.gz" --exclude='/opt/netbox/netbox/media' /opt/netbox/

echo "Sauvegarde créée dans: $BACKUP_DIR"
ls -lh "$BACKUP_DIR"
```

### Étape 2 : Vérifier les prérequis

```bash
# Python version
python3 --version  # Doit être 3.10+ pour NetBox 4.0+

# PostgreSQL version
sudo -u postgres psql --version

# Redis version
redis-server --version

# Espace disque disponible
df -h /opt
```

### Étape 3 : Arrêter les services NetBox

```bash
# Arrêter NetBox
sudo supervisorctl stop netbox netbox-rq

# Vérifier qu'ils sont bien arrêtés
sudo supervisorctl status
```

### Étape 4 : Télécharger la nouvelle version

```bash
cd /opt/netbox

# Définir la version cible
NEW_VERSION="4.2.0"  # Modifier selon votre besoin

# Télécharger
sudo wget "https://github.com/netbox-community/netbox/archive/refs/tags/v${NEW_VERSION}.tar.gz" -O "netbox-v${NEW_VERSION}.tar.gz"

# Extraire
sudo tar -xzf "netbox-v${NEW_VERSION}.tar.gz"

# Vérifier
ls -la netbox-${NEW_VERSION}/
```

### Étape 5 : Copier la configuration et les médias

```bash
# Copier la configuration existante
sudo cp /opt/netbox/netbox/netbox/configuration.py "/opt/netbox/netbox-${NEW_VERSION}/netbox/netbox/"

# Copier les fichiers média
sudo cp -r /opt/netbox/netbox/media/* "/opt/netbox/netbox-${NEW_VERSION}/netbox/media/" 2>/dev/null || true

# Copier les scripts personnalisés (si existants)
if [ -d /opt/netbox/netbox/scripts ]; then
    sudo cp -r /opt/netbox/netbox/scripts/* "/opt/netbox/netbox-${NEW_VERSION}/netbox/scripts/" 2>/dev/null || true
fi

# Copier les rapports personnalisés (si existants)
if [ -d /opt/netbox/netbox/reports ]; then
    sudo cp -r /opt/netbox/netbox/reports/* "/opt/netbox/netbox-${NEW_VERSION}/netbox/reports/" 2>/dev/null || true
fi
```

### Étape 6 : Mise à jour du lien symbolique

```bash
cd /opt/netbox

# Supprimer l'ancien lien symbolique
sudo rm netbox

# Créer le nouveau lien
sudo ln -s "netbox-${NEW_VERSION}" netbox

# Vérifier
ls -la netbox
```

### Étape 7 : Mettre à jour l'environnement virtuel

```bash
cd /opt/netbox

# Supprimer l'ancien virtualenv
sudo rm -rf venv/

# Créer un nouveau virtualenv
sudo python3 -m venv venv

# Activer le virtualenv
source venv/bin/activate

# Mettre à jour pip
pip install --upgrade pip

# Installer les dépendances
pip install -r requirements.txt

# Désactiver le virtualenv
deactivate
```

### Étape 8 : Vérifier et mettre à jour la configuration

```bash
# Comparer avec la configuration exemple
sudo diff /opt/netbox/netbox/netbox/configuration_example.py /opt/netbox/netbox/netbox/configuration.py

# Vérifier s'il y a de nouveaux paramètres requis
# Consulter les release notes pour les changements de configuration
```

**Paramètres importants à vérifier** :

```python
# NetBox 4.0+ requiert ces paramètres
ALLOWED_HOSTS = ['*']  # ou votre domaine
DATABASE = {...}
REDIS = {...}
SECRET_KEY = '...'

# Nouveaux paramètres dans NetBox 4.0+
CSRF_TRUSTED_ORIGINS = ['https://your-domain.com']  # Si reverse proxy
```

### Étape 9 : Appliquer les migrations de base de données

**IMPORTANT** : Cette étape applique les changements de schéma à la base de données.

```bash
cd /opt/netbox
source venv/bin/activate

# Vérifier les migrations en attente
python3 netbox/manage.py showmigrations | grep "\[ \]"

# Appliquer les migrations
python3 netbox/manage.py migrate

# Collecter les fichiers statiques
python3 netbox/manage.py collectstatic --noinput

# Supprimer les sessions expirées
python3 netbox/manage.py clearsessions

# Supprimer le cache
python3 netbox/manage.py invalidate all

deactivate
```

### Étape 10 : Corriger les permissions

```bash
# Assurer les bonnes permissions
sudo chown -R netbox:netbox /opt/netbox/netbox/media/
sudo chown -R netbox:netbox /opt/netbox/netbox/static/
```

### Étape 11 : Redémarrer les services

```bash
# Redémarrer NetBox
sudo supervisorctl restart netbox netbox-rq

# Vérifier le statut
sudo supervisorctl status

# Surveiller les logs
sudo tail -f /var/log/netbox/netbox.log
```

### Étape 12 : Vérification

```bash
# Test HTTP
curl -I http://localhost:8080

# Vérifier la version
cd /opt/netbox
source venv/bin/activate
python3 netbox/manage.py nbshell
# Dans le shell Python :
# from netbox.settings import VERSION
# print(VERSION)
# exit()
deactivate
```

**Tests dans l'interface web** :
- [ ] Connexion utilisateur fonctionne
- [ ] Données IPAM visibles
- [ ] Recherche fonctionne
- [ ] API REST répond : `http://your-server/api/`
- [ ] Fichiers uploadés sont accessibles

### Étape 13 : Nettoyage (après validation)

```bash
# Attendre quelques jours pour s'assurer que tout fonctionne
# Puis supprimer l'ancienne version

cd /opt/netbox
OLD_VERSION="3.6.0"  # Remplacer par votre ancienne version

sudo rm -rf "netbox-${OLD_VERSION}"
sudo rm "netbox-v${OLD_VERSION}.tar.gz"
```

## Migration de serveur avec versions différentes

Si vous migrez vers un nouveau serveur ET que vous voulez upgrader :

### Approche recommandée

```bash
# Sur le SERVEUR SOURCE (ancien)
# 1. Mettre à jour NetBox vers la version cible
# (Suivre les étapes 1-12 ci-dessus)

# 2. Une fois la mise à jour validée, faire la sauvegarde
sudo -u postgres pg_dump netbox > /tmp/netbox-db-upgraded.sql
sudo tar -czf /tmp/netbox-media.tar.gz -C /opt/netbox/netbox media/
sudo cp /opt/netbox/netbox/netbox/configuration.py /tmp/

# 3. Transférer vers le nouveau serveur
scp /tmp/netbox-db-upgraded.sql user@new-server:/tmp/
scp /tmp/netbox-media.tar.gz user@new-server:/tmp/
scp /tmp/configuration.py user@new-server:/tmp/

# Sur le NOUVEAU SERVEUR
# 4. Installer la MÊME version que celle du serveur source (après upgrade)
# 5. Restaurer les données
# (Voir MIGRATION.md)
```

## Rollback en cas de problème

Si la mise à jour échoue, vous pouvez revenir en arrière :

```bash
# Arrêter les services
sudo supervisorctl stop netbox netbox-rq

cd /opt/netbox

# Revenir au lien symbolique précédent
OLD_VERSION="3.6.0"  # Votre ancienne version
sudo rm netbox
sudo ln -s "netbox-${OLD_VERSION}" netbox

# Restaurer la base de données
BACKUP_DIR="/var/backups/netbox-before-upgrade-XXXXXXXX"  # Votre dossier de sauvegarde
sudo -u postgres psql << EOF
DROP DATABASE netbox;
CREATE DATABASE netbox;
GRANT ALL PRIVILEGES ON DATABASE netbox TO netbox;
EOF

sudo -u postgres psql netbox < "$BACKUP_DIR/netbox-db.sql"

# Restaurer la configuration
sudo cp "$BACKUP_DIR/configuration.py" /opt/netbox/netbox/netbox/

# Recréer l'environnement virtuel
sudo rm -rf venv/
sudo python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
deactivate

# Redémarrer
sudo supervisorctl restart netbox netbox-rq
```

## Automatisation de la mise à jour

Script pour automatiser la mise à jour :

```bash
sudo tee /usr/local/bin/netbox-upgrade.sh > /dev/null << 'UPGRADE_SCRIPT'
#!/bin/bash

set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Vérifier les arguments
if [ -z "$1" ]; then
    echo "Usage: $0 <version>"
    echo "Exemple: $0 4.2.0"
    exit 1
fi

NEW_VERSION="$1"
BACKUP_DIR="/var/backups/netbox-before-upgrade-$(date +%Y%m%d-%H%M%S)"

echo -e "${GREEN}=== Mise à jour de NetBox vers v${NEW_VERSION} ===${NC}"

# 1. Sauvegarde
echo -e "${YELLOW}[1/12] Création de la sauvegarde...${NC}"
mkdir -p "$BACKUP_DIR"
sudo -u postgres pg_dump netbox > "$BACKUP_DIR/netbox-db.sql"
tar -czf "$BACKUP_DIR/netbox-media.tar.gz" -C /opt/netbox/netbox media/
cp /opt/netbox/netbox/netbox/configuration.py "$BACKUP_DIR/"
echo -e "${GREEN}✓ Sauvegarde créée: $BACKUP_DIR${NC}"

# 2. Arrêt des services
echo -e "${YELLOW}[2/12] Arrêt des services NetBox...${NC}"
sudo supervisorctl stop netbox netbox-rq

# 3. Téléchargement
echo -e "${YELLOW}[3/12] Téléchargement de NetBox v${NEW_VERSION}...${NC}"
cd /opt/netbox
wget -q "https://github.com/netbox-community/netbox/archive/refs/tags/v${NEW_VERSION}.tar.gz" -O "netbox-v${NEW_VERSION}.tar.gz"
tar -xzf "netbox-v${NEW_VERSION}.tar.gz"

# 4. Copie de la configuration
echo -e "${YELLOW}[4/12] Copie de la configuration...${NC}"
cp /opt/netbox/netbox/netbox/configuration.py "/opt/netbox/netbox-${NEW_VERSION}/netbox/netbox/"
cp -r /opt/netbox/netbox/media/* "/opt/netbox/netbox-${NEW_VERSION}/netbox/media/" 2>/dev/null || true

# 5. Mise à jour du lien symbolique
echo -e "${YELLOW}[5/12] Mise à jour du lien symbolique...${NC}"
rm netbox
ln -s "netbox-${NEW_VERSION}" netbox

# 6. Environnement virtuel
echo -e "${YELLOW}[6/12] Création de l'environnement virtuel...${NC}"
rm -rf venv/
python3 -m venv venv
source venv/bin/activate
pip install --quiet --upgrade pip
pip install --quiet -r requirements.txt

# 7. Migrations
echo -e "${YELLOW}[7/12] Application des migrations...${NC}"
python3 netbox/manage.py migrate

# 8. Collecte des fichiers statiques
echo -e "${YELLOW}[8/12] Collecte des fichiers statiques...${NC}"
python3 netbox/manage.py collectstatic --noinput

# 9. Nettoyage
echo -e "${YELLOW}[9/12] Nettoyage des sessions...${NC}"
python3 netbox/manage.py clearsessions

deactivate

# 10. Permissions
echo -e "${YELLOW}[10/12] Correction des permissions...${NC}"
sudo chown -R netbox:netbox /opt/netbox/netbox/media/
sudo chown -R netbox:netbox /opt/netbox/netbox/static/

# 11. Redémarrage
echo -e "${YELLOW}[11/12] Redémarrage des services...${NC}"
sudo supervisorctl restart netbox netbox-rq
sleep 5

# 12. Vérification
echo -e "${YELLOW}[12/12] Vérification...${NC}"
if curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 | grep -q "200\|302"; then
    echo -e "${GREEN}✓ NetBox est opérationnel !${NC}"
    echo -e "${GREEN}✓ Mise à jour terminée avec succès vers v${NEW_VERSION}${NC}"
    echo -e "${GREEN}✓ Sauvegarde disponible: $BACKUP_DIR${NC}"
else
    echo -e "${RED}✗ Erreur: NetBox ne répond pas correctement${NC}"
    echo -e "${RED}Vérifiez les logs: tail -f /var/log/netbox/netbox.log${NC}"
    exit 1
fi
UPGRADE_SCRIPT

sudo chmod +x /usr/local/bin/netbox-upgrade.sh
```

**Utilisation** :

```bash
# Mettre à jour vers la version 4.2.0
sudo /usr/local/bin/netbox-upgrade.sh 4.2.0
```

## Cas particuliers

### Mise à jour majeure (ex: 3.x → 4.x)

Consultez TOUJOURS les release notes :
- https://github.com/netbox-community/netbox/releases

**NetBox 3.x → 4.x nécessite** :
- Python 3.10+
- PostgreSQL 12+
- Vérification des plugins (compatibilité)
- Modifications possibles de configuration

### Mise à jour avec plugins

```bash
# Avant la mise à jour
cd /opt/netbox
source venv/bin/activate
pip list | grep netbox

# Noter les versions des plugins installés
# Vérifier leur compatibilité avec la nouvelle version NetBox

# Après la mise à jour
pip install --upgrade netbox-plugin-name
```

### Mise à jour de PostgreSQL en même temps

**NON RECOMMANDÉ** - Faites une chose à la fois !

Si nécessaire :
1. Mettre à jour PostgreSQL d'abord
2. Vérifier que NetBox fonctionne
3. Puis mettre à jour NetBox

## Bonnes pratiques

1. **Lisez les release notes** avant chaque mise à jour
2. **Testez en pré-production** si possible
3. **Sauvegardez TOUJOURS** avant une mise à jour
4. **Planifiez une fenêtre de maintenance**
5. **Préparez un plan de rollback**
6. **Vérifiez les dépendances** (Python, PostgreSQL, plugins)
7. **Documentez** les modifications de configuration
8. **Surveillez les logs** après la mise à jour

## Ressources

- [NetBox Release Notes](https://github.com/netbox-community/netbox/releases)
- [NetBox Upgrade Guide Officiel](https://docs.netbox.dev/en/stable/installation/upgrading/)
- [NetBox Documentation](https://docs.netbox.dev/)
- [Community Discussions](https://github.com/netbox-community/netbox/discussions)

## Support

En cas de problème :
1. Vérifier les logs : `tail -f /var/log/netbox/netbox.log`
2. Vérifier les migrations : `python3 netbox/manage.py showmigrations`
3. Consulter les GitHub Issues : https://github.com/netbox-community/netbox/issues
4. Rollback si nécessaire (voir section ci-dessus)
