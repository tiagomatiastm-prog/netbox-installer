# Guide de déploiement Ansible - NetBox

Ce guide explique comment déployer NetBox sur un ou plusieurs serveurs Ubuntu 24.04.3 en utilisant Ansible.

## Prérequis

### Sur la machine de contrôle (votre ordinateur)

- **Ansible** installé (version 2.10 ou supérieure)
- **Python 3** et **pip**
- Accès SSH aux serveurs cibles
- Collection Ansible PostgreSQL

### Sur les serveurs cibles

- **Ubuntu 24.04.3 LTS** fraîchement installé
- **Accès SSH** configuré avec clé publique
- **Utilisateur sudo** configuré
- **Python 3** installé (généralement présent par défaut)

## Installation d'Ansible

### Sur Ubuntu/Debian

```bash
sudo apt update
sudo apt install -y ansible python3-pip
```

### Sur macOS

```bash
brew install ansible
```

### Sur Windows (WSL)

```bash
# Installer WSL2 avec Ubuntu
wsl --install

# Dans WSL
sudo apt update
sudo apt install -y ansible python3-pip
```

### Installer la collection PostgreSQL

```bash
ansible-galaxy collection install community.postgresql
pip3 install psycopg2-binary
```

## Configuration de l'inventaire

### 1. Éditer le fichier inventory.ini

```bash
nano inventory.ini
```

### 2. Ajouter vos serveurs

#### Exemple pour un serveur unique

```ini
[netbox_servers]
netbox-prod ansible_host=172.16.25.47 ansible_user=tiago ansible_become=yes

[netbox_servers:vars]
ansible_python_interpreter=/usr/bin/python3
```

#### Exemple pour plusieurs serveurs

```ini
[netbox_servers]
netbox-prod ansible_host=192.168.1.100 ansible_user=admin ansible_become=yes
netbox-dev ansible_host=192.168.1.101 ansible_user=admin ansible_become=yes
netbox-test ansible_host=192.168.1.102 ansible_user=admin ansible_become=yes

[netbox_servers:vars]
ansible_python_interpreter=/usr/bin/python3
```

#### Avec clé SSH personnalisée

```ini
[netbox_servers]
netbox-prod ansible_host=192.168.1.100 ansible_user=admin ansible_become=yes ansible_ssh_private_key_file=~/.ssh/id_rsa_netbox

[netbox_servers:vars]
ansible_python_interpreter=/usr/bin/python3
```

## Préparation de la connexion SSH

### 1. Générer une paire de clés SSH (si nécessaire)

```bash
ssh-keygen -t rsa -b 4096 -C "netbox-deployment"
```

### 2. Copier la clé publique sur le serveur

```bash
ssh-copy-id tiago@172.16.25.47
```

### 3. Tester la connexion SSH

```bash
ssh tiago@172.16.25.47
```

### 4. Vérifier la connexion Ansible

```bash
ansible -i inventory.ini netbox_servers -m ping
```

Résultat attendu :
```
netbox-prod | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

## Déploiement

### 1. Vérifier la syntaxe du playbook

```bash
ansible-playbook -i inventory.ini deploy-netbox.yml --syntax-check
```

### 2. Mode "Dry-run" (simulation)

```bash
ansible-playbook -i inventory.ini deploy-netbox.yml --check
```

### 3. Lancer le déploiement

```bash
ansible-playbook -i inventory.ini deploy-netbox.yml
```

### 4. Déploiement avec verbosité (pour debug)

```bash
ansible-playbook -i inventory.ini deploy-netbox.yml -v
# ou
ansible-playbook -i inventory.ini deploy-netbox.yml -vvv  # très verbeux
```

### 5. Déployer uniquement sur un serveur spécifique

```bash
ansible-playbook -i inventory.ini deploy-netbox.yml --limit netbox-prod
```

## Personnalisation des variables

### Variables disponibles dans le playbook

Vous pouvez personnaliser ces variables directement dans `deploy-netbox.yml` :

```yaml
vars:
  netbox_version: "4.1"           # Version de NetBox
  netbox_port: 8080               # Port Gunicorn
  install_dir: "/opt/netbox"      # Répertoire d'installation
  log_file: "/var/log/netbox-installation.log"
  credentials_file: "{{ ansible_env.HOME }}/netbox-credentials.md"
```

### Utiliser un fichier de variables externe

Créer un fichier `vars/netbox.yml` :

```yaml
---
netbox_version: "4.1"
netbox_port: 8080
install_dir: "/opt/netbox"
```

Puis modifier le playbook pour inclure ce fichier :

```yaml
- name: Déploiement automatique de NetBox
  hosts: netbox_servers
  become: yes
  vars_files:
    - vars/netbox.yml
  tasks:
    # ...
```

## Vérification post-déploiement

### 1. Vérifier le statut des services

```bash
ansible -i inventory.ini netbox_servers -m shell -a "supervisorctl status" --become
```

### 2. Vérifier que NetBox répond

```bash
ansible -i inventory.ini netbox_servers -m shell -a "curl -I http://localhost:8080"
```

### 3. Récupérer le fichier de credentials

```bash
ansible -i inventory.ini netbox_servers -m fetch -a "src=~/netbox-credentials.md dest=./ flat=yes"
```

## Déploiements avancés

### Déploiement sur plusieurs environnements

Créer plusieurs fichiers d'inventaire :

**inventory-prod.ini**
```ini
[netbox_servers]
netbox-prod ansible_host=192.168.1.100 ansible_user=admin
```

**inventory-dev.ini**
```ini
[netbox_servers]
netbox-dev ansible_host=192.168.1.101 ansible_user=admin
```

Déployer sur l'environnement spécifique :
```bash
ansible-playbook -i inventory-prod.ini deploy-netbox.yml
ansible-playbook -i inventory-dev.ini deploy-netbox.yml
```

### Utiliser Ansible Vault pour les secrets

Bien que les mots de passe soient générés automatiquement, vous pouvez chiffrer l'inventaire :

```bash
# Créer un fichier chiffré
ansible-vault create inventory-vault.ini

# Éditer un fichier chiffré
ansible-vault edit inventory-vault.ini

# Déployer avec un fichier chiffré
ansible-playbook -i inventory-vault.ini deploy-netbox.yml --ask-vault-pass
```

### Déploiement avec tags

Ajouter des tags aux tâches dans le playbook :

```yaml
- name: Installation des dépendances système
  tags: dependencies
  ansible.builtin.apt:
    name: [...]
```

Exécuter uniquement certaines parties :

```bash
# Uniquement l'installation des dépendances
ansible-playbook -i inventory.ini deploy-netbox.yml --tags dependencies

# Tout sauf les dépendances
ansible-playbook -i inventory.ini deploy-netbox.yml --skip-tags dependencies
```

## Dépannage

### Erreur de connexion SSH

```bash
# Vérifier la connectivité
ansible -i inventory.ini netbox_servers -m ping

# Si échec, vérifier manuellement
ssh -vvv tiago@172.16.25.47
```

### Erreur "Module not found: psycopg2"

```bash
# Sur la machine de contrôle
pip3 install psycopg2-binary

# Sur les serveurs cibles
ansible -i inventory.ini netbox_servers -m apt -a "name=python3-psycopg2 state=present" --become
```

### Erreur de permissions

```bash
# Vérifier que l'utilisateur a les droits sudo
ansible -i inventory.ini netbox_servers -m shell -a "sudo whoami" --become
```

### Le playbook s'arrête sur une tâche

```bash
# Relancer à partir de la dernière tâche réussie
ansible-playbook -i inventory.ini deploy-netbox.yml --start-at-task="nom_de_la_tache"
```

### Réinitialiser complètement l'installation

```bash
# Se connecter au serveur
ssh tiago@172.16.25.47

# Arrêter les services
sudo supervisorctl stop netbox netbox-rq
sudo systemctl stop nginx postgresql redis-server

# Supprimer NetBox
sudo rm -rf /opt/netbox*

# Supprimer la base de données
sudo -u postgres psql -c "DROP DATABASE netbox;"
sudo -u postgres psql -c "DROP USER netbox;"

# Relancer le déploiement
exit
ansible-playbook -i inventory.ini deploy-netbox.yml
```

## Maintenance

### Mise à jour de NetBox via Ansible

Créer un playbook `update-netbox.yml` :

```yaml
---
- name: Mise à jour de NetBox
  hosts: netbox_servers
  become: yes
  tasks:
    - name: Arrêter les services
      ansible.builtin.supervisorctl:
        name: "{{ item }}"
        state: stopped
      loop:
        - netbox
        - netbox-rq

    - name: Mettre à jour les dépendances
      ansible.builtin.pip:
        requirements: /opt/netbox/requirements.txt
        virtualenv: /opt/netbox/venv

    - name: Exécuter les migrations
      ansible.builtin.command:
        cmd: /opt/netbox/venv/bin/python /opt/netbox/netbox/manage.py migrate

    - name: Collecter les fichiers statiques
      ansible.builtin.command:
        cmd: /opt/netbox/venv/bin/python /opt/netbox/netbox/manage.py collectstatic --noinput

    - name: Redémarrer les services
      ansible.builtin.supervisorctl:
        name: "{{ item }}"
        state: started
      loop:
        - netbox
        - netbox-rq
```

### Sauvegarde automatisée via Ansible

Créer un playbook `backup-netbox.yml` :

```yaml
---
- name: Sauvegarde de NetBox
  hosts: netbox_servers
  become: yes
  tasks:
    - name: Créer un répertoire de sauvegarde
      ansible.builtin.file:
        path: /backup/netbox
        state: directory
        mode: '0700'

    - name: Sauvegarder la base de données
      become_user: postgres
      ansible.builtin.shell:
        cmd: pg_dump netbox > /backup/netbox/netbox_{{ ansible_date_time.date }}.sql

    - name: Récupérer la sauvegarde
      ansible.builtin.fetch:
        src: "/backup/netbox/netbox_{{ ansible_date_time.date }}.sql"
        dest: "./backups/"
        flat: yes
```

## Bonnes pratiques

1. **Toujours tester sur un environnement de développement** avant la production
2. **Utiliser des inventaires séparés** pour dev, test et prod
3. **Versionner vos playbooks** dans Git
4. **Chiffrer les données sensibles** avec Ansible Vault
5. **Documenter les modifications** dans les commits Git
6. **Sauvegarder régulièrement** la base de données
7. **Tester les restaurations** de sauvegarde périodiquement

## Ressources

- [Documentation Ansible](https://docs.ansible.com/)
- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)
- [NetBox Documentation](https://docs.netbox.dev/)

## Support

Pour toute question concernant le déploiement Ansible :
1. Vérifiez les logs Ansible
2. Utilisez le mode verbeux (`-vvv`)
3. Consultez la documentation Ansible
4. Vérifiez la connectivité SSH
