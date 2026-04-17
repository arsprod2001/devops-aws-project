# NetPulse — Guide Complet du Projet DevOps
## Kubernetes · Cilium · Hubble · Prometheus · Grafana · AWS · Terraform · Ansible

> **À qui s'adresse ce guide ?**  
> À quelqu'un qui n'a jamais touché à Kubernetes, Terraform, Ansible, Cilium ou Prometheus.  
> Chaque concept est expliqué depuis zéro, chaque ligne de code est commentée.

---

## Table des matières

1. [Vue d'ensemble — Comprendre le projet](#1-vue-densemble--comprendre-le-projet)
2. [Les concepts fondamentaux expliqués simplement](#2-les-concepts-fondamentaux-expliqués-simplement)
3. [Structure du projet](#3-structure-du-projet)
4. [Étape 1 — Infrastructure AWS avec Terraform](#4-étape-1--infrastructure-aws-avec-terraform)
5. [Étape 2 — Configuration du cluster avec Ansible](#5-étape-2--configuration-du-cluster-avec-ansible)
6. [Étape 3 — Cilium : le réseau eBPF](#6-étape-3--cilium--le-réseau-ebpf)
7. [Étape 4 — L'application NetPulse](#7-étape-4--lapplication-netpulse)
8. [Étape 5 — Manifests Kubernetes](#8-étape-5--manifests-kubernetes)
9. [Étape 6 — NetworkPolicies Cilium](#9-étape-6--networkpolicies-cilium)
10. [Étape 7 — Prometheus & Grafana](#10-étape-7--prometheus--grafana)
11. [Déploiement complet — Commandes pas à pas](#11-déploiement-complet--commandes-pas-à-pas)
12. [Problèmes rencontrés et solutions](#12-problèmes-rencontrés-et-solutions)
13. [URLs et vérifications finales](#13-urls-et-vérifications-finales)
14. [Glossaire](#14-glossaire)

---

## 1. Vue d'ensemble — Comprendre le projet

### Qu'est-ce que NetPulse ?

NetPulse est une application web qui **surveille les flux réseau entre les services** d'un cluster Kubernetes. Elle répond à une question concrète : *"Quels pods communiquent avec quels pods, et est-ce autorisé ou bloqué ?"*

### Analogie simple

Imagine un bâtiment d'entreprise avec des bureaux (les pods), des couloirs (le réseau), et un système de badges (les NetworkPolicies). NetPulse est la caméra de sécurité qui filme tous les mouvements et t'affiche en temps réel qui passe où, et si c'est autorisé ou non.

### La chaîne de déploiement

```
Ta machine locale
       │
       ▼
  Terraform ──────── crée ──────► AWS EC2 (2 serveurs virtuels)
       │
       ▼
   Ansible ──────── configure ──► Docker + Kubernetes + Cilium + Prometheus + Grafana
       │
       ▼
   kubectl ──────── déploie ───► NetPulse (frontend + backend + postgres)
       │
       ▼
  Ton navigateur ──► http://IP:30000  (dashboard NetPulse)
                 ──► http://IP:31000  (Grafana)
                 ──► http://IP:31001  (Prometheus)
```

### Ce que fait chaque outil

| Outil | Rôle dans ce projet | Analogie |
|-------|---------------------|----------|
| **Terraform** | Crée les serveurs AWS | Architecte qui construit les murs |
| **Ansible** | Installe les logiciels sur les serveurs | Électricien qui installe le câblage |
| **Kubernetes** | Orchestre les containers | Chef d'orchestre qui dirige les musiciens |
| **Cilium** | Gère le réseau entre pods (via eBPF) | Réseau routier avec panneaux de sens interdit |
| **Hubble** | Visualise les flux Cilium | Caméra de surveillance du réseau routier |
| **Prometheus** | Collecte les métriques (chiffres) | Compteur qui mesure tout |
| **Grafana** | Affiche les métriques en graphiques | Tableau de bord de voiture |
| **Docker** | Empaquette les applications | Boîtes standardisées pour le transport |

---

## 2. Les concepts fondamentaux expliqués simplement

### 2.1 Qu'est-ce qu'un container Docker ?

Un container est une **boîte isolée** qui contient une application avec tout ce dont elle a besoin pour fonctionner (code, bibliothèques, configuration). C'est comme une capsule autonome.

```
┌─────────────────────────────────┐
│  Container "backend"            │
│  ┌─────────────────────────┐    │
│  │  Node.js 18             │    │
│  │  Express.js             │    │
│  │  server.js (ton code)   │    │
│  └─────────────────────────┘    │
│  Port 3000 exposé               │
└─────────────────────────────────┘
```

**Dockerfile** = recette pour créer l'image (le modèle) du container.

```dockerfile
# On part d'une image de base légère (Alpine Linux + Node.js 18)
FROM node:18-alpine

# On crée un dossier de travail dans le container
WORKDIR /app

# On copie les fichiers de dépendances EN PREMIER
# (optimisation : si package.json ne change pas, Docker réutilise le cache)
COPY package.json package-lock.json* ./

# On installe seulement les dépendances de production
RUN npm install --only=production

# On copie le reste du code
COPY . .

# On crée un utilisateur non-root (sécurité : jamais root dans un container)
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

# On documente que l'app écoute sur le port 3000
EXPOSE 3000

# Commande lancée au démarrage du container
CMD ["node", "server.js"]
```

### 2.2 Qu'est-ce que Kubernetes ?

Kubernetes (K8s) est un système qui **gère automatiquement des groupes de containers**. Il répond aux questions :
- Comment démarrer 2 copies de mon application ?
- Que faire si une copie plante ?
- Comment permettre aux containers de se parler ?

**Les objets Kubernetes principaux :**

```
Deployment  ──► "Je veux 2 copies du backend, toujours"
    │
    ▼
ReplicaSet  ──► Surveille qu'il y a bien 2 pods
    │
    ▼
  Pod  ──► 1 instance du container backend
  Pod  ──► 1 autre instance du container backend

Service     ──► Adresse fixe pour accéder aux pods (même si les pods changent)
```

**Analogie :** Kubernetes est comme un gestionnaire RH automatique. Tu lui dis "j'ai besoin de 2 serveurs backend". Si l'un part en vacances (crash), il en recrute un autre immédiatement.

### 2.3 Qu'est-ce qu'un CNI et pourquoi Cilium ?

**CNI** = Container Network Interface. C'est le plugin qui gère **comment les pods se parlent**.

Sans CNI, les pods ne peuvent pas communiquer. C'est comme un immeuble sans réseau téléphonique interne.

**Flannel** (l'ancien CNI) = réseau basique, comme des tuyaux sans robinet. Les pods peuvent tous se parler, pas de contrôle.

**Cilium** (le nouveau CNI) = réseau intelligent basé sur **eBPF**. Il peut :
- Contrôler qui parle à qui (NetworkPolicies L4 et L7)
- Enregistrer chaque flux (Hubble)
- Remplacer kube-proxy (plus performant)

**eBPF** = Extended Berkeley Packet Filter. C'est une technologie Linux qui permet d'exécuter du code directement dans le noyau du système d'exploitation, sans modifier le kernel. Cilium l'utilise pour intercepter et analyser chaque paquet réseau à la vitesse matérielle.

### 2.4 Qu'est-ce que Prometheus ?

Prometheus est une base de données de métriques (chiffres dans le temps). Il **interroge régulièrement** les applications et stocke les résultats.

```
Toutes les 15 secondes :
Prometheus ──► GET http://backend:3000/metrics
             ◄── "netpulse_network_events_total{verdict="ALLOW"} 84"

Stocké dans Prometheus :
  timestamp=14:30:00  → 84 flux ALLOW
  timestamp=14:30:15  → 87 flux ALLOW
  timestamp=14:30:30  → 91 flux ALLOW
```

Grafana lit ensuite ces données et les affiche en graphiques.

### 2.5 Qu'est-ce qu'Ansible ?

Ansible est un outil d'**automatisation de configuration**. Tu décris dans un fichier YAML ce que tu veux faire, et Ansible l'exécute sur autant de serveurs que tu veux via SSH.

```yaml
# "Je veux que Docker soit installé sur tous les serveurs"
- name: Installer Docker
  apt:
    name: docker-ce
    state: present
```

Ansible se connecte en SSH → exécute les commandes → vérifie que c'est fait. **Idempotent** = si tu le relances, il ne refait pas ce qui est déjà fait.

---

## 3. Structure du projet

```
netpulse/
├── deploy.sh                    # Script maître : lance tout en une commande
│
├── terraform/                   # Étape 1 : Infrastructure AWS
│   ├── main.tf                  # Création des serveurs EC2
│   ├── vpc.tf                   # Réseau AWS (VPC, subnets)
│   ├── security_groups.tf       # Règles de pare-feu
│   ├── variables.tf             # Variables configurables
│   └── outputs.tf               # Valeurs exportées (IPs publiques)
│
├── ansible/                     # Étape 2 : Configuration des serveurs
│   ├── inventory.ini            # Liste des serveurs (IPs)
│   └── playbook.yml             # Instructions de configuration (5 plays)
│
├── app/                         # L'application NetPulse
│   ├── docker-compose.yml       # Pour tester en local
│   ├── backend/
│   │   ├── server.js            # API Node.js (le cerveau de l'app)
│   │   ├── package.json         # Dépendances Node.js
│   │   └── Dockerfile           # Recette de l'image Docker
│   └── frontend/
│       ├── index.html           # Dashboard web (HTML + CSS + JS)
│       ├── nginx.conf           # Configuration du serveur web Nginx
│       └── Dockerfile           # Recette de l'image Docker
│
└── k8s/                         # Étape 3 : Déploiement Kubernetes
    ├── 01-namespace.yaml        # Espace de noms isolé
    ├── 02-postgres.yaml         # Base de données PostgreSQL
    ├── 03-backend.yaml          # API Node.js
    ├── 04-frontend.yaml         # Interface web Nginx
    ├── 05-cilium-policies.yaml  # Règles réseau Cilium
    └── 06-grafana-dashboard.yaml# Dashboard Grafana auto-configuré
```

---

## 4. Étape 1 — Infrastructure AWS avec Terraform

### 4.1 C'est quoi Terraform ?

Terraform permet de décrire ton infrastructure dans des fichiers texte et de la créer/modifier/supprimer automatiquement. C'est l'"Infrastructure as Code" (IaC).

**Sans Terraform :** Tu vas sur la console AWS, tu cliques partout, tu crées manuellement chaque ressource. Si tu fais une erreur ou veux recommencer, c'est long.

**Avec Terraform :** Tu écris des fichiers `.tf`, tu lances `terraform apply`, tout est créé automatiquement en 2 minutes.

### 4.2 `terraform/variables.tf` — Les paramètres configurables

```hcl
# Ce fichier définit toutes les valeurs modifiables
# C'est le seul fichier que tu touches pour adapter le projet

variable "aws_region" {
  description = "Région AWS où déployer"
  type        = string
  default     = "us-east-1"   # Virginie du Nord (serveurs AWS proches du Canada)
}

variable "project_name" {
  description = "Préfixe pour nommer toutes les ressources"
  type        = string
  default     = "netpulse"
  # Toutes les ressources s'appelleront "netpulse-quelquechose"
}

variable "instance_type" {
  description = "Taille des serveurs EC2"
  type        = string
  default     = "t2.medium"
  # t2.medium = 2 vCPU + 4 Go RAM
  # IMPORTANT : t2.micro (gratuit) est trop petit pour Cilium + Prometheus
  # Il faut au minimum t2.medium pour ce projet
}

variable "ami_id" {
  description = "Image du système d'exploitation (Ubuntu 22.04)"
  type        = string
  default     = "ami-0fc5d935ebf8bc3bc"
  # AMI = Amazon Machine Image = snapshot d'un OS prêt à l'emploi
  # Ce code correspond à Ubuntu 22.04 LTS dans us-east-1
}

variable "key_pair_name" {
  description = "Nom de la clé SSH pour se connecter"
  type        = string
  default     = "devops-aws-key"
  # Tu dois créer cette clé SSH dans AWS et la télécharger sur ta machine
}
```

### 4.3 `terraform/vpc.tf` — Le réseau AWS

```hcl
# VPC = Virtual Private Cloud
# C'est ton réseau privé isolé dans AWS
# Comme si AWS te louait une section d'internet rien que pour toi

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"   # Plage d'IPs disponibles : 65 534 adresses
  enable_dns_hostnames = true             # Les serveurs ont des noms DNS internes
  enable_dns_support   = true

  tags = { Name = "netpulse-vpc" }
}

# Subnet public = sous-réseau accessible depuis internet
# Tes serveurs EC2 seront ici
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"     # 254 adresses disponibles
  availability_zone       = "us-east-1a"       # Datacenter AWS spécifique
  map_public_ip_on_launch = true               # Les serveurs reçoivent une IP publique automatiquement

  tags = { Name = "netpulse-public-subnet" }
}

# Internet Gateway = porte d'entrée/sortie vers internet
# Sans ça, ton VPC est isolé du monde extérieur
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "netpulse-igw" }
}

# Table de routage = instructions de navigation
# "Tout trafic vers internet (0.0.0.0/0) passe par l'Internet Gateway"
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"                    # Toute destination...
    gateway_id = aws_internet_gateway.main.id   # ...passe par l'IGW
  }
}

# Associer la table de routage au subnet public
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
```

### 4.4 `terraform/security_groups.tf` — Le pare-feu

```hcl
# Security Group = pare-feu virtuel AWS
# Il définit quels ports sont ouverts (ingress = entrant, egress = sortant)

resource "aws_security_group" "k8s_master" {
  name   = "netpulse-k8s-master-sg"
  vpc_id = aws_vpc.main.id

  # SSH : pour se connecter au serveur depuis ta machine
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]   # De n'importe quelle IP (à restreindre en production)
  }

  # API Kubernetes : kubectl utilise ce port pour envoyer des commandes au cluster
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # NodePorts : plage de ports réservée aux services Kubernetes exposés externement
  # 30000 = frontend NetPulse
  # 30001 = backend API
  # 31000 = Grafana
  # 31001 = Prometheus
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Cilium health check : les agents Cilium se vérifient mutuellement
  ingress {
    from_port   = 4240
    to_port     = 4240
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]   # Seulement depuis l'intérieur du VPC
  }

  # Cilium VXLAN : tunnel réseau entre les nœuds
  # VXLAN encapsule le trafic des pods dans des paquets UDP
  ingress {
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # Hubble Relay gRPC : communication avec Hubble pour observer les flux
  ingress {
    from_port   = 4245
    to_port     = 4245
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # Tout le trafic interne au VPC est autorisé (entre master et worker)
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"            # -1 = tous les protocoles
    cidr_blocks = ["10.0.0.0/16"]
  }

  # Tout le trafic sortant est autorisé (pour télécharger des packages, etc.)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

> **⚠️ Erreur rencontrée :** Les descriptions AWS Security Groups n'acceptent que des caractères ASCII. Les accents français (`œ`, `é`) et les tirets em (`—`) causent une erreur Terraform. Toujours écrire les descriptions en ASCII pur.

### 4.5 `terraform/main.tf` — Les serveurs EC2

```hcl
# EC2 = Elastic Compute Cloud = serveur virtuel AWS

# SERVEUR MASTER : contrôle le cluster Kubernetes
resource "aws_instance" "k8s_master" {
  ami                    = var.ami_id          # Ubuntu 22.04
  instance_type          = var.instance_type   # t2.medium
  key_name               = var.key_pair_name   # Ta clé SSH
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.k8s_master.id]

  root_block_device {
    volume_type           = "gp2"   # SSD General Purpose
    volume_size           = 20      # 20 Go de stockage
    delete_on_termination = true
  }

  # Script exécuté au premier démarrage (user_data)
  # Prépare le serveur pour Kubernetes avant qu'Ansible arrive
  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y

    # Désactiver le swap : Kubernetes l'exige (problèmes de performance sinon)
    swapoff -a
    sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

    # Charger les modules kernel nécessaires à Kubernetes
    modprobe overlay      # Pour les systèmes de fichiers des containers
    modprobe br_netfilter  # Pour le filtrage réseau des pods

    # Activer le routage IP (indispensable pour que les pods se parlent)
    cat <<EOT > /etc/sysctl.d/k8s.conf
    net.bridge.bridge-nf-call-iptables  = 1
    net.bridge.bridge-nf-call-ip6tables = 1
    net.ipv4.ip_forward                 = 1
    EOT
    sysctl --system
  EOF

  tags = {
    Name = "netpulse-k8s-master"
    Role = "master"
  }
}

# SERVEUR WORKER : exécute les pods de l'application
resource "aws_instance" "k8s_worker" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_pair_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.k8s_worker.id]

  root_block_device {
    volume_type = "gp2"
    volume_size = 20
  }

  # Même préparation que le master
  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    swapoff -a
    sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
    modprobe overlay
    modprobe br_netfilter
    cat <<EOT > /etc/sysctl.d/k8s.conf
    net.bridge.bridge-nf-call-iptables  = 1
    net.ipv4.ip_forward                 = 1
    EOT
    sysctl --system
  EOF

  tags = {
    Name = "netpulse-k8s-worker"
    Role = "worker"
  }
}

# Elastic IP : IP publique FIXE pour le master
# Sans ça, l'IP change à chaque redémarrage du serveur
resource "aws_eip" "master" {
  instance = aws_instance.k8s_master.id
  domain   = "vpc"
}
```

### 4.6 Commandes Terraform

```bash
# 1. Initialiser : télécharge les plugins AWS
terraform init

# 2. Planifier : montre ce qui va être créé (sans créer)
terraform plan -out=netpulse.tfplan

# 3. Appliquer : crée vraiment les ressources
terraform apply netpulse.tfplan

# 4. Voir les résultats
terraform output
# Affiche :
# master_public_ip = "3.234.179.176"
# worker_public_ip = "54.166.132.5"
# ssh_master = "ssh -i ~/.ssh/devops-aws-key ubuntu@3.234.179.176"

# 5. Détruire (à la fin, pour ne pas payer inutilement)
terraform destroy
```

---

## 5. Étape 2 — Configuration du cluster avec Ansible

### 5.1 C'est quoi un Ansible Playbook ?

Un playbook Ansible est un fichier YAML qui décrit des **"plays"** (groupes de tâches). Chaque tâche fait une action sur les serveurs.

```yaml
- name: Nom du play
  hosts: master          # Sur quel(s) serveur(s) ?
  become: true           # Avec les droits root (sudo) ?
  tasks:
    - name: Description de la tâche
      ansible.builtin.apt:   # Module Ansible pour apt (gestionnaire de paquets)
        name: docker-ce
        state: present       # "present" = installé, "absent" = supprimé
```

### 5.2 `ansible/inventory.ini` — La liste des serveurs

```ini
# Ce fichier dit à Ansible où se trouvent tes serveurs

[master]
# Nom local      IP publique AWS           Utilisateur SSH    Clé SSH
k8s-master ansible_host=3.234.179.176 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/devops-aws-key

[workers]
k8s-worker ansible_host=54.166.132.5 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/devops-aws-key

# Groupe qui contient master ET workers
[k8s_nodes:children]
master
workers

# Options communes à tous les nœuds
[k8s_nodes:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no'   # Ne pas demander confirmation SSH
ansible_python_interpreter=/usr/bin/python3             # Python 3 obligatoire pour Ansible
```

### 5.3 `ansible/playbook.yml` — Le playbook complet (5 plays)

#### Play 1 : Configuration de base (master + worker)

```yaml
- name: Configuration de base de tous les noeuds Kubernetes
  hosts: k8s_nodes    # S'exécute SUR LES DEUX serveurs en parallèle
  become: true         # root requis pour installer des packages

  tasks:
    # Nettoyer les verrous apt (problème fréquent sur Ubuntu fresh)
    - name: Tuer tous les processus apt/dpkg en cours
      ansible.builtin.shell: |
        killall -9 apt apt-get dpkg 2>/dev/null || true
        rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock 2>/dev/null || true
        dpkg --configure -a 2>/dev/null || true
      changed_when: false
      failed_when: false

    # Mettre à jour la liste des packages disponibles
    - name: Mettre a jour la liste des packages
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600   # Ne re-télécharge pas si fait il y a moins d'1h
      retries: 3                  # Réessaie 3 fois si ça échoue (réseau instable)
      delay: 10

    # Installer les outils de base
    - name: Installer les paquets essentiels
      ansible.builtin.apt:
        name:
          - curl          # Pour télécharger des fichiers
          - gnupg         # Pour vérifier les signatures des packages
          - git           # Pour cloner des dépôts
          - jq            # Pour parser du JSON en ligne de commande
        state: present

    # ── DOCKER ────────────────────────────────────────────────────────
    # Docker n'est pas dans les dépôts Ubuntu par défaut.
    # On ajoute le dépôt officiel Docker.

    - name: Ajouter la cle GPG de Docker
      ansible.builtin.apt_key:
        url: https://download.docker.com/linux/ubuntu/gpg
        keyring: /etc/apt/keyrings/docker.gpg   # Stockage sécurisé de la clé

    - name: Ajouter le depot Docker
      ansible.builtin.apt_repository:
        repo: "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu jammy stable"

    - name: Installer Docker
      ansible.builtin.apt:
        name:
          - docker-ce          # Docker Engine (le moteur principal)
          - docker-ce-cli      # Outil en ligne de commande Docker
          - containerd.io      # Runtime de containers (requis par K8s)
        update_cache: true

    # containerd doit utiliser systemd comme gestionnaire de cgroups
    # (cgroups = mécanisme Linux qui limite les ressources des containers)
    - name: Supprimer la config containerd par defaut
      ansible.builtin.file:
        path: /etc/containerd/config.toml
        state: absent

    - name: Generer une config containerd propre
      ansible.builtin.shell: containerd config default > /etc/containerd/config.toml

    - name: Activer SystemdCgroup dans containerd
      ansible.builtin.replace:
        path: /etc/containerd/config.toml
        regexp: "SystemdCgroup = false"
        replace: "SystemdCgroup = true"
        # CRITIQUE : sans ça, les pods Kubernetes ne démarrent pas correctement

    - name: Redemarrer containerd
      ansible.builtin.systemd:
        name: containerd
        state: restarted
        daemon_reload: true   # Recharge la config systemd

    # ── KUBERNETES ────────────────────────────────────────────────────
    # Même principe : ajouter le dépôt officiel K8s

    - name: Ajouter la cle GPG Kubernetes
      ansible.builtin.apt_key:
        url: https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key
        keyring: /etc/apt/keyrings/kubernetes-apt-keyring.gpg

    - name: Ajouter le depot Kubernetes
      ansible.builtin.apt_repository:
        repo: "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /"

    - name: Installer kubeadm, kubelet, kubectl
      ansible.builtin.apt:
        name:
          - kubelet    # Agent K8s qui tourne sur chaque nœud
          - kubeadm    # Outil pour initialiser/joindre un cluster
          - kubectl    # Outil CLI pour contrôler le cluster
        update_cache: true

    # Bloquer les versions : empêche les mises à jour automatiques
    # qui pourraient casser la compatibilité
    - name: Bloquer les versions K8s
      ansible.builtin.dpkg_selections:
        name: "{{ item }}"
        selection: hold
      loop:
        - kubelet
        - kubeadm
        - kubectl

    # ── HELM ─────────────────────────────────────────────────────────
    # Helm = gestionnaire de paquets Kubernetes (comme apt pour Ubuntu)
    # On s'en sert pour installer Cilium et Prometheus
    - name: Installer Helm
      ansible.builtin.shell: |
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
      args:
        creates: /usr/local/bin/helm   # Ne réinstalle pas si déjà présent
```

#### Play 2 : Initialisation du Master

```yaml
- name: Initialisation du noeud Master Kubernetes
  hosts: master
  become: true

  tasks:
    # Vérifier si le cluster existe déjà (pour éviter de réinitialiser)
    - name: Verifier si le cluster est deja initialise
      ansible.builtin.stat:
        path: /etc/kubernetes/admin.conf   # Ce fichier n'existe que si K8s est initialisé
      register: k8s_admin_conf             # Stocke le résultat dans une variable

    # kubeadm init = crée le cluster Kubernetes
    # --skip-phases=addon/kube-proxy : on n'installe PAS kube-proxy
    #   car Cilium va le remplacer (mode eBPF pur, plus performant)
    # --pod-network-cidr : plage d'IPs pour les pods
    - name: Initialiser le cluster sans kube-proxy
      ansible.builtin.shell: |
        kubeadm init \
          --pod-network-cidr=10.244.0.0/16 \
          --apiserver-advertise-address={{ ansible_default_ipv4.address }} \
          --skip-phases=addon/kube-proxy \
          --ignore-preflight-errors=NumCPU,Mem
      when: not k8s_admin_conf.stat.exists   # Seulement si pas déjà initialisé

    # Copier le fichier de config kubectl pour l'utilisateur ubuntu
    # Sans ça, ubuntu ne peut pas utiliser kubectl
    - name: Copier le kubeconfig
      ansible.builtin.copy:
        src: /etc/kubernetes/admin.conf
        dest: /home/ubuntu/.kube/config
        remote_src: true   # Le fichier source est sur le serveur distant
        owner: ubuntu
        mode: "0644"

    # ── CILIUM CLI ────────────────────────────────────────────────────
    - name: Installer Cilium CLI
      ansible.builtin.shell: |
        # Récupérer la dernière version stable
        CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
        curl -L --fail \
          https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz \
          -o /tmp/cilium.tar.gz
        tar xzvf /tmp/cilium.tar.gz -C /usr/local/bin
        chmod +x /usr/local/bin/cilium
      args:
        creates: /usr/local/bin/cilium   # Idempotent

    # ── HUBBLE CLI ────────────────────────────────────────────────────
    - name: Installer Hubble CLI
      ansible.builtin.shell: |
        HUBBLE_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/hubble/master/stable.txt)
        curl -L --fail \
          https://github.com/cilium/hubble/releases/download/${HUBBLE_VERSION}/hubble-linux-amd64.tar.gz \
          -o /tmp/hubble.tar.gz
        tar xzvf /tmp/hubble.tar.gz -C /usr/local/bin
        chmod +x /usr/local/bin/hubble
      args:
        creates: /usr/local/bin/hubble

    # ── INSTALLATION CILIUM via Helm ──────────────────────────────────
    - name: Ajouter le repo Helm Cilium
      ansible.builtin.shell: helm repo add cilium https://helm.cilium.io/ && helm repo update
      become_user: ubuntu
      environment:
        KUBECONFIG: /home/ubuntu/.kube/config

    - name: Installer Cilium avec Hubble active
      # ATTENTION aux options :
      # - routingMode=tunnel + tunnelProtocol=vxlan : mode tunnel VXLAN
      #   (l'option "tunnel=vxlan" a été SUPPRIMÉE dans Cilium v1.15, erreur fatale sinon)
      # - kubeProxyReplacement=true : Cilium remplace kube-proxy
      # - hubble.metrics : métriques réseau exposées à Prometheus
      # - hostFirewall=true : NE PAS METTRE sur instances AWS t2 (kernel incompatible)
      ansible.builtin.shell: |
        helm upgrade --install cilium cilium/cilium \
          --namespace kube-system \
          --set kubeProxyReplacement=true \
          --set k8sServiceHost={{ ansible_default_ipv4.address }} \
          --set k8sServicePort=6443 \
          --set hubble.relay.enabled=true \
          --set hubble.ui.enabled=true \
          --set hubble.metrics.enabled="{dns,drop,tcp,flow,icmp,http}" \
          --set prometheus.enabled=true \
          --set operator.prometheus.enabled=true \
          --set ipam.mode=cluster-pool \
          --set ipam.operator.clusterPoolIPv4PodCIDRList="10.244.0.0/16" \
          --set routingMode=tunnel \
          --set tunnelProtocol=vxlan \
          --wait \
          --timeout=10m
      become_user: ubuntu
      environment:
        KUBECONFIG: /home/ubuntu/.kube/config
      when: not k8s_admin_conf.stat.exists

    # Attendre que Cilium soit prêt (peut prendre 2-3 minutes)
    - name: Attendre que les pods Cilium existent
      ansible.builtin.shell: |
        for i in $(seq 1 20); do
          COUNT=$(kubectl get pods -n kube-system -l k8s-app=cilium --no-headers 2>/dev/null | wc -l)
          if [ "$COUNT" -gt "0" ]; then
            echo "Cilium pods detectes: $COUNT"
            exit 0
          fi
          sleep 15
        done
        exit 1
      become_user: ubuntu
      environment:
        KUBECONFIG: /home/ubuntu/.kube/config

    # Générer la commande pour que le worker rejoigne le cluster
    - name: Generer la commande join
      ansible.builtin.shell: kubeadm token create --print-join-command
      register: join_command

    - name: Sauvegarder la commande join localement
      ansible.builtin.copy:
        content: "{{ join_command.stdout }}"
        dest: /tmp/k8s_join_command.sh
      delegate_to: localhost   # Exécuté sur TA machine, pas le serveur
      become: false
```

#### Play 3 : Joindre le Worker

```yaml
- name: Joindre les noeuds Workers
  hosts: workers
  become: true

  tasks:
    - name: Verifier si le worker a deja rejoint
      ansible.builtin.stat:
        path: /etc/kubernetes/kubelet.conf
      register: kubelet_conf

    - name: Lire la commande join
      ansible.builtin.set_fact:
        join_cmd: "{{ lookup('file', '/tmp/k8s_join_command.sh') }}"
      when: not kubelet_conf.stat.exists

    # Cette commande est générée par kubeadm sur le master
    # Elle contient un token temporaire et le hash du certificat
    - name: Rejoindre le cluster
      ansible.builtin.shell: "{{ join_cmd }} --ignore-preflight-errors=NumCPU,Mem"
      when: not kubelet_conf.stat.exists
```

#### Play 4 : Prometheus + Grafana

```yaml
- name: Deploiement du stack Prometheus + Grafana
  hosts: master
  become_user: ubuntu

  tasks:
    - name: Creer les namespaces
      ansible.builtin.shell: |
        kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
        kubectl create namespace netpulse --dry-run=client -o yaml | kubectl apply -f -
      # --dry-run=client -o yaml | kubectl apply -f - = crée seulement si n'existe pas

    - name: Ajouter le repo prometheus-community
      ansible.builtin.shell: |
        helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
        helm repo update

    # kube-prometheus-stack = chart Helm qui installe en une commande :
    # Prometheus + Grafana + AlertManager + Node Exporter + Prometheus Operator
    - name: Installer kube-prometheus-stack
      ansible.builtin.shell: |
        helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
          --namespace monitoring \
          --set grafana.adminPassword=netpulse2025 \
          --set grafana.service.type=NodePort \
          --set grafana.service.nodePort=31000 \
          --set prometheus.service.type=NodePort \
          --set prometheus.service.nodePort=31001 \
          --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
          --wait \
          --timeout=10m
```

---

## 6. Étape 3 — Cilium : le réseau eBPF

### 6.1 Comment Cilium fonctionne

Quand Cilium est installé, il déploie un **agent** (pod Cilium) sur **chaque nœud**. Cet agent :

1. Se connecte au noyau Linux via eBPF
2. Intercepte chaque paquet réseau entrant/sortant des pods
3. Vérifie si le paquet est autorisé par les NetworkPolicies
4. ALLOW → le paquet continue / DROP → le paquet est bloqué
5. Enregistre l'événement dans Hubble

```
Pod frontend (10.244.0.218)
    │
    │  Envoie une requête HTTP vers backend:3000
    │
    ▼
Cilium eBPF Hook (dans le kernel)
    │
    │  Vérifie : "Est-ce que frontend peut parler à backend sur le port 3000 ?"
    │  → Oui (CiliumNetworkPolicy allow-frontend-to-backend)
    │
    ▼
Pod backend (10.244.0.116:3000)
    │
    │  Répond avec les données
    │
    ▼
Hubble enregistre : "frontend→backend TCP:3000 ALLOW 12ms"
```

### 6.2 Remplacer kube-proxy par Cilium eBPF

**kube-proxy** (classique) utilise des règles **iptables**. Chaque nouveau service ajoute des règles, et quand il y en a des milliers, la recherche d'une règle devient lente (O(n)).

**Cilium eBPF** utilise des **hash maps** dans le kernel. La recherche est O(1) (temps constant), peu importe le nombre de services.

C'est pourquoi on initialise le cluster avec `--skip-phases=addon/kube-proxy` : on ne crée pas kube-proxy du tout, Cilium le remplace dès le départ.

---

## 7. Étape 4 — L'application NetPulse

### 7.1 `app/backend/server.js` — L'API Node.js

```javascript
// server.js — API REST NetPulse
const express = require('express');
const { Pool } = require('pg');    // Client PostgreSQL
const cors = require('cors');      // Autoriser les requêtes cross-origin

const app = express();
app.use(express.json());           // Lire le JSON des requêtes POST
app.use(cors());                   // Frontend peut appeler le backend

// ── Connexion PostgreSQL ──────────────────────────────────────
// Les credentials viennent des variables d'environnement
// (injectées par le Secret Kubernetes, jamais en dur dans le code)
const pool = new Pool({
  host:     process.env.DB_HOST     || 'localhost',
  port:     process.env.DB_PORT     || 5432,
  database: process.env.DB_NAME     || 'netpulsedb',
  user:     process.env.DB_USER     || 'postgres',
  password: process.env.DB_PASSWORD || 'password',
});

// ── Initialisation de la base de données ─────────────────────
async function initDB() {
  // Crée les tables si elles n'existent pas
  await pool.query(`
    CREATE TABLE IF NOT EXISTS network_events (
      id        SERIAL PRIMARY KEY,          -- ID auto-incrémenté
      pod_src   VARCHAR(128),               -- Pod source du flux
      pod_dst   VARCHAR(128),               -- Pod destination
      namespace VARCHAR(64),               -- Namespace Kubernetes
      protocol  VARCHAR(16),              -- HTTP, TCP, UDP...
      verdict   VARCHAR(16),              -- ALLOW ou DROP
      bytes     INTEGER DEFAULT 0,        -- Taille du trafic
      latency   FLOAT DEFAULT 0,          -- Latence en ms
      created_at TIMESTAMP DEFAULT NOW()  -- Horodatage automatique
    );

    CREATE TABLE IF NOT EXISTS alerts (
      id         SERIAL PRIMARY KEY,
      severity   VARCHAR(16),   -- critical, warning, info
      title      VARCHAR(255),
      message    TEXT,
      pod        VARCHAR(128),
      resolved   BOOLEAN DEFAULT FALSE,
      created_at TIMESTAMP DEFAULT NOW()
    );
  `);
}

// ── Route de santé ────────────────────────────────────────────
// Kubernetes appelle cette route pour savoir si le pod est vivant
// Si elle renvoie autre chose que 200, K8s redémarre le pod
app.get('/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// ── Métriques Prometheus ──────────────────────────────────────
// Prometheus appelle /metrics toutes les 15 secondes
// Le format est strict : "nom_metrique{labels} valeur"
app.get('/metrics', async (_req, res) => {
  const events = await pool.query(
    `SELECT verdict, COUNT(*) as count
     FROM network_events
     WHERE created_at > NOW() - INTERVAL '5 minutes'
     GROUP BY verdict`
  );

  // Format texte Prometheus (OpenMetrics)
  let output = `# HELP netpulse_network_events_total Total network events by verdict\n`;
  output += `# TYPE netpulse_network_events_total counter\n`;
  for (const row of events.rows) {
    // Exemple : netpulse_network_events_total{verdict="ALLOW"} 84
    output += `netpulse_network_events_total{verdict="${row.verdict}"} ${row.count}\n`;
  }

  res.set('Content-Type', 'text/plain; version=0.0.4');
  res.send(output);
});

// ── API : statistiques ────────────────────────────────────────
app.get('/api/stats', async (_req, res) => {
  // Promise.all = lance plusieurs requêtes SQL en parallèle
  const [totals, topFlows, verdicts, protocols] = await Promise.all([
    pool.query(`
      SELECT
        COUNT(*)                                       AS total_flows,
        SUM(bytes)                                     AS total_bytes,
        ROUND(AVG(latency)::numeric, 2)                AS avg_latency,
        COUNT(*) FILTER (WHERE verdict='DROP')          AS dropped,
        COUNT(*) FILTER (WHERE verdict='ALLOW')         AS allowed
      FROM network_events
      WHERE created_at > NOW() - INTERVAL '1 hour'
    `),
    pool.query(`
      SELECT pod_src, pod_dst, COUNT(*) AS count
      FROM network_events
      GROUP BY pod_src, pod_dst
      ORDER BY count DESC LIMIT 6
    `),
    pool.query(`SELECT verdict, COUNT(*) AS count FROM network_events GROUP BY verdict`),
    pool.query(`SELECT protocol, COUNT(*) AS count FROM network_events GROUP BY protocol ORDER BY count DESC`),
  ]);

  res.json({
    totals:    totals.rows[0],
    top_flows: topFlows.rows,
    verdicts:  verdicts.rows,
    protocols: protocols.rows,
  });
});

// ── Simulation de flux réseau ─────────────────────────────────
// En production, ces données viendraient de l'API Hubble.
// Ici, on simule pour la démonstration.
function simulateNetworkFlow() {
  const flows = [
    ['frontend', 'backend',  'netpulse',  'HTTP', 'ALLOW'],
    ['backend',  'postgres', 'netpulse',  'TCP',  'ALLOW'],
    ['unknown',  'backend',  'netpulse',  'TCP',  'DROP'],   // DROP intentionnel
    ['frontend', 'postgres', 'netpulse',  'TCP',  'DROP'],   // Bloqué par NetworkPolicy
  ];
  const [src, dst, ns, proto, verdict] = flows[Math.floor(Math.random() * flows.length)];
  pool.query(
    `INSERT INTO network_events (pod_src,pod_dst,namespace,protocol,verdict,bytes,latency)
     VALUES ($1,$2,$3,$4,$5,$6,$7)`,
    [src, dst, ns, proto, verdict,
      Math.floor(Math.random() * 50000),
      Math.random() * 60]
  ).catch(() => {});
}

// Démarrer le serveur
const PORT = process.env.PORT || 3000;
initDB().then(() => {
  app.listen(PORT, () => {
    console.log(`NetPulse Backend démarré sur le port ${PORT}`);
    // Simuler un nouveau flux toutes les 15 secondes
    setInterval(simulateNetworkFlow, 15000);
  });
});
```

### 7.2 `app/frontend/nginx.conf` — Configuration Nginx critique

```nginx
server {
    listen 80;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;

    # Servir les fichiers statiques (HTML, CSS, JS)
    location / {
        try_files $uri $uri/ /index.html;
    }

    # Proxy vers le backend Kubernetes
    # CRITIQUE : proxy_http_version 1.1 et Connection ""
    # Sans ça, Node.js renvoie HTTP 426 (Upgrade Required)
    # car il reçoit des headers Upgrade inattendus depuis HTTP/1.0
    location /api/ {
        proxy_pass http://backend-service:3000;
        proxy_http_version 1.1;           # Forcer HTTP/1.1 (pas HTTP/1.0)
        proxy_set_header Connection "";   # Vider le header Connection
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    # Proxy pour les métriques Prometheus
    location /metrics {
        proxy_pass http://backend-service:3000/metrics;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
    }
}
```

> **Pourquoi `proxy_http_version 1.1` ?**  
> Par défaut, Nginx utilise HTTP/1.0 pour les connexions en amont (proxy). En HTTP/1.0, Nginx ajoute un header `Connection: close`. Node.js interprète ça comme une demande d'upgrade de protocole et répond 426. En forçant HTTP/1.1 et en vidant le header Connection, Nginx établit une connexion propre.

---

## 8. Étape 5 — Manifests Kubernetes

### 8.1 `k8s/01-namespace.yaml` — L'espace de noms

```yaml
# Un namespace isole des ressources dans le cluster
# C'est comme un dossier : les ressources du namespace "netpulse"
# sont séparées de celles de "monitoring" ou "kube-system"
apiVersion: v1
kind: Namespace
metadata:
  name: netpulse
  labels:
    name: netpulse
```

### 8.2 `k8s/02-postgres.yaml` — La base de données

```yaml
# ── Secret : identifiants encodés en Base64 ──────────────────
# JAMAIS mettre les mots de passe en clair dans le code !
# On encode en base64 : echo -n "password" | base64 → cGFzc3dvcmQ=
apiVersion: v1
kind: Secret
metadata:
  name: postgres-secret
  namespace: netpulse
type: Opaque
data:
  postgres-password: cGFzc3dvcmQ=   # "password" en base64
  postgres-user:     cG9zdGdyZXM=   # "postgres" en base64
  postgres-db:       bmV0cHVsc2VkYg== # "netpulsedb" en base64
---
# ── PersistentVolumeClaim : demande de stockage persistant ───
# Sans ça, les données disparaissent quand le pod redémarre
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
  namespace: netpulse
spec:
  accessModes:
    - ReadWriteOnce       # Un seul pod peut écrire à la fois
  resources:
    requests:
      storage: 2Gi        # 2 Go de stockage demandé
---
# ── Deployment : le pod PostgreSQL ───────────────────────────
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
  namespace: netpulse
spec:
  replicas: 1             # Une seule instance (pas de réplication DB ici)
  selector:
    matchLabels:
      app: postgres       # Ce Deployment gère les pods avec ce label
  template:
    metadata:
      labels:
        app: postgres     # Label appliqué au pod
    spec:
      containers:
        - name: postgres
          image: postgres:15-alpine   # Image officielle PostgreSQL légère
          ports:
            - containerPort: 5432
          env:
            # Les valeurs viennent du Secret (jamais en dur ici)
            - name: POSTGRES_DB
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: postgres-db
            - name: POSTGRES_USER
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: postgres-user
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: postgres-password
          volumeMounts:
            - name: postgres-storage
              mountPath: /var/lib/postgresql/data   # Où PostgreSQL stocke ses données
          resources:
            requests:
              memory: "128Mi"   # Minimum garanti
              cpu: "100m"       # 100 millicores = 0.1 CPU
            limits:
              memory: "256Mi"   # Maximum autorisé
              cpu: "250m"
          # Readiness Probe : K8s n'envoie du trafic que si cette commande réussit
          readinessProbe:
            exec:
              command: ["pg_isready", "-U", "postgres"]
            initialDelaySeconds: 10
            periodSeconds: 5
      volumes:
        - name: postgres-storage
          persistentVolumeClaim:
            claimName: postgres-pvc   # Utilise le PVC créé ci-dessus
---
# ── Service : accès interne au pod PostgreSQL ────────────────
apiVersion: v1
kind: Service
metadata:
  name: postgres-service
  namespace: netpulse
spec:
  selector:
    app: postgres         # Cible les pods avec ce label
  ports:
    - port: 5432
      targetPort: 5432
  type: ClusterIP         # Accessible seulement depuis l'intérieur du cluster
                          # Le backend s'y connecte via "postgres-service:5432"
```

### 8.3 `k8s/03-backend.yaml` — L'API Node.js

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: netpulse
spec:
  replicas: 2             # 2 copies pour la haute disponibilité
  selector:
    matchLabels:
      app: backend
  strategy:
    type: RollingUpdate   # Mise à jour sans interruption
    rollingUpdate:
      maxUnavailable: 1   # Maximum 1 pod indisponible pendant la MAJ
      maxSurge: 1         # Maximum 1 pod supplémentaire créé pendant la MAJ
  template:
    metadata:
      labels:
        app: backend
      annotations:
        # Ces annotations indiquent à Prometheus de scraper ce pod
        prometheus.io/scrape: "true"
        prometheus.io/path: "/metrics"
        prometheus.io/port: "3000"
    spec:
      containers:
        - name: backend
          image: arsprod01/netpulse-backend:v2.0   # Ton image Docker Hub
          imagePullPolicy: Always                   # Toujours récupérer la dernière version
          ports:
            - containerPort: 3000
          env:
            - name: DB_HOST
              value: "postgres-service"   # K8s résout ce nom en IP du pod postgres
            - name: DB_PORT
              value: "5432"
            - name: DB_NAME
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: postgres-db
            - name: DB_USER
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: postgres-user
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: postgres-password
          # Liveness Probe : si ça échoue 3 fois, K8s redémarre le pod
          livenessProbe:
            httpGet:
              path: /health
              port: 3000
            initialDelaySeconds: 30   # Attendre 30s avant le premier check
            periodSeconds: 10         # Vérifier toutes les 10s
            failureThreshold: 3
          # Readiness Probe : si ça échoue, K8s arrête d'envoyer du trafic
          readinessProbe:
            httpGet:
              path: /health
              port: 3000
            initialDelaySeconds: 15
            periodSeconds: 5
          resources:
            requests:
              memory: "128Mi"
              cpu: "100m"
            limits:
              memory: "256Mi"
              cpu: "500m"
---
apiVersion: v1
kind: Service
metadata:
  name: backend-service
  namespace: netpulse
spec:
  selector:
    app: backend
  ports:
    - name: http
      port: 3000
      targetPort: 3000
      nodePort: 30001     # Port accessible depuis internet : http://IP:30001
  type: NodePort          # NodePort = accessible depuis l'extérieur du cluster
---
# ServiceMonitor : dit à Prometheus "scrape ce service"
# Géré par le Prometheus Operator (installé avec kube-prometheus-stack)
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: netpulse-backend
  namespace: monitoring   # Dans le namespace monitoring, pas netpulse
  labels:
    release: kube-prometheus-stack   # Doit correspondre au label du chart Helm
spec:
  selector:
    matchLabels:
      app: backend
  namespaceSelector:
    matchNames:
      - netpulse
  endpoints:
    - port: http
      path: /metrics
      interval: 15s   # Scraping toutes les 15 secondes
```

### 8.4 `k8s/04-frontend.yaml` — L'interface web

```yaml
# ConfigMap : stocke la configuration Nginx
# Monté dans le container comme un fichier
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
  namespace: netpulse
data:
  default.conf: |
    server {
        listen 80;
        server_name _;
        root /usr/share/nginx/html;
        index index.html;

        location / {
            try_files $uri $uri/ /index.html;
        }

        location /api/ {
            proxy_pass http://backend-service:3000;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_set_header Host $host;
        }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: netpulse
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
        - name: frontend
          image: arsprod01/netpulse-frontend:v2.0
          ports:
            - containerPort: 80
          volumeMounts:
            - name: nginx-config
              mountPath: /etc/nginx/conf.d/default.conf
              subPath: default.conf   # Monter seulement ce fichier, pas tout le ConfigMap
      volumes:
        - name: nginx-config
          configMap:
            name: nginx-config
---
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
  namespace: netpulse
spec:
  selector:
    app: frontend
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30000   # http://IP:30000 = accès au dashboard NetPulse
  type: NodePort
```

---

## 9. Étape 6 — NetworkPolicies Cilium

### 9.1 Principe du Zero Trust

Sans NetworkPolicy, **tous les pods peuvent se parler**. C'est comme un bureau sans portes : tout le monde peut aller partout.

Avec le principe **Zero Trust** :
1. On commence par **tout bloquer** (`default-deny-all`)
2. On autorise **uniquement les flux nécessaires**
3. Tout le reste reste bloqué → visible dans Hubble comme DROP

### 9.2 `k8s/05-cilium-policies.yaml`

```yaml
# ── RÈGLE 1 : Tout bloquer par défaut ───────────────────────
# endpointSelector: {} = s'applique à TOUS les pods du namespace
# ingress: [] = aucune connexion entrante autorisée
# egress: []  = aucune connexion sortante autorisée
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: default-deny-all
  namespace: netpulse
spec:
  endpointSelector: {}
  ingress: []
  egress: []

---
# ── RÈGLE 2 : frontend → backend AUTORISÉ ────────────────────
# endpointSelector : s'applique AU backend (c'est lui qui reçoit)
# ingress.fromEndpoints : autorise les requêtes VENANT du frontend
# toPorts : seulement sur le port 3000 en TCP
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: netpulse
spec:
  endpointSelector:
    matchLabels:
      app: backend          # Cette règle protège le backend
  ingress:
    - fromEndpoints:
        - matchLabels:
            app: frontend   # Autorise les pods ayant le label "app: frontend"
      toPorts:
        - ports:
            - port: "3000"
              protocol: TCP

---
# ── RÈGLE 3 : backend → postgres AUTORISÉ ────────────────────
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: allow-backend-to-postgres
  namespace: netpulse
spec:
  endpointSelector:
    matchLabels:
      app: postgres
  ingress:
    - fromEndpoints:
        - matchLabels:
            app: backend
      toPorts:
        - ports:
            - port: "5432"
              protocol: TCP

# NOTE : frontend → postgres N'EST PAS AUTORISÉ
# La règle default-deny-all bloque ces tentatives.
# Dans Hubble : "frontend → postgres TCP DROP POLICY_DENIED"
# Dans Prometheus : hubble_drop_total{reason="POLICY_DENIED"} monte

---
# ── RÈGLE 4 : Prometheus → backend (scraping) AUTORISÉ ──────
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: allow-prometheus-scrape-backend
  namespace: netpulse
spec:
  endpointSelector:
    matchLabels:
      app: backend
  ingress:
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: prometheus
      toPorts:
        - ports:
            - port: "3000"
              protocol: TCP

---
# ── RÈGLE 5 : DNS egress (résolution de noms interne) ────────
# Sans ça, les pods ne peuvent pas résoudre "postgres-service" en IP
# kube-dns = le DNS interne de Kubernetes
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: allow-dns-egress
  namespace: netpulse
spec:
  endpointSelector: {}    # Tous les pods
  egress:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: netpulse

---
# ── RÈGLE 6 : NodePorts accessibles depuis internet ──────────
# CiliumClusterwideNetworkPolicy = s'applique à tout le cluster
# reserved:world = trafic venant de l'extérieur (internet)
apiVersion: "cilium.io/v2"
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: allow-nodeport-ingress
spec:
  endpointSelector:
    matchLabels:
      reserved:world: "true"
  ingress:
    - toPorts:
        - ports:
            - port: "30000"   # Frontend
              protocol: TCP
            - port: "30001"   # Backend API
              protocol: TCP
            - port: "31000"   # Grafana
              protocol: TCP
            - port: "31001"   # Prometheus
              protocol: TCP
```

> **Pourquoi des règles L4 seulement (pas L7) ?**  
> On a essayé d'ajouter des règles L7 HTTP (vérifier la méthode GET/POST et le chemin `/api/*`). Ça n'a pas fonctionné car Cilium inspecte les headers HTTP bruts, et Nginx ajoute des headers proxy (`X-Real-IP`, `X-Forwarded-For`) que Cilium rejetait. Les règles L4 TCP sont plus robustes et suffisent pour la démonstration.

---

## 10. Étape 7 — Prometheus & Grafana

### 10.1 Comment Prometheus découvre les cibles

Prometheus ne fait pas de découverte magique. Il faut lui dire **quoi scraper**. Dans kube-prometheus-stack, on utilise des ressources Kubernetes personnalisées.

**ServiceMonitor** (pour les Services K8s) :
```yaml
# "Scrape le Service backend-service dans le namespace netpulse
# toutes les 15s sur le port http au chemin /metrics"
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: netpulse-backend
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: backend         # Trouve le Service avec ce label
  namespaceSelector:
    matchNames: [netpulse]
  endpoints:
    - port: http
      path: /metrics
      interval: 15s
```

**PodMonitor** (pour les Pods K8s) :
```yaml
# "Scrape les pods Cilium dans kube-system sur le port 'prometheus'"
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: cilium-agent
  namespace: monitoring
spec:
  selector:
    matchLabels:
      k8s-app: cilium
  namespaceSelector:
    matchNames: [kube-system]
  podMetricsEndpoints:
    - port: prometheus
      interval: 15s
      path: /metrics
```

### 10.2 Métriques Cilium dans Prometheus

Quand Hubble est activé avec `hubble.metrics.enabled="{dns,drop,tcp,flow,icmp,http}"`, Cilium expose automatiquement ces métriques :

```
# Flux traités par Cilium (ALLOW + DROP)
hubble_flows_processed_total{direction="INGRESS",verdict="ALLOW"} 84
hubble_flows_processed_total{direction="INGRESS",verdict="DROPPED"} 19

# Flux bloqués avec raison
hubble_drop_total{reason="POLICY_DENIED",direction="INGRESS"} 19

# Requêtes DNS
hubble_dns_queries_total{rcode="NOERROR"} 342
hubble_dns_queries_total{rcode="NXDOMAIN"} 5

# Connexions TCP
hubble_tcp_flags_total{flag="SYN"} 203
hubble_tcp_flags_total{flag="RST"} 2
```

### 10.3 Requêtes PromQL utiles

PromQL est le langage de requêtes de Prometheus. Voici les requêtes les plus utiles pour ce projet :

```promql
# Nombre total de drops dans la dernière heure
sum(increase(hubble_drop_total[1h]))

# Taux de violation de policy (% de flux bloqués)
rate(hubble_drop_total[5m]) / rate(hubble_flows_processed_total[5m]) * 100

# CPU moyen des nœuds Kubernetes
100 - (avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Mémoire utilisée en %
(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100

# Alertes actives NetPulse
netpulse_active_alerts

# Flux réseau par verdict (NetPulse app)
netpulse_network_events_total
```

### 10.4 Dashboard Grafana provisionné

Le fichier `k8s/06-grafana-dashboard.yaml` contient deux ConfigMaps :

```yaml
# ConfigMap 1 : Dashboard JSON
# Grafana détecte les ConfigMaps avec le label "grafana_dashboard: 1"
# et les charge automatiquement au démarrage
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-netpulse
  namespace: monitoring
  labels:
    grafana_dashboard: "1"   # Label magique pour l'auto-provisioning
data:
  netpulse.json: |
    {
      "title": "NetPulse — Surveillance Réseau Kubernetes",
      "panels": [
        # ... définition JSON des graphiques
      ]
    }
---
# ConfigMap 2 : Source de données Prometheus
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasource-prometheus
  namespace: monitoring
  labels:
    grafana_datasource: "1"   # Label pour l'auto-provisioning des datasources
data:
  datasource.yaml: |
    apiVersion: 1
    datasources:
      - name: Prometheus
        type: prometheus
        url: http://kube-prometheus-stack-prometheus:9090
        isDefault: true
```

---

## 11. Déploiement complet — Commandes pas à pas

### Prérequis sur ta machine

```bash
# Outils à installer localement
terraform --version    # >= 1.0
ansible --version      # >= 2.14
docker --version       # >= 20.10
aws configure          # Configurer tes credentials AWS

# Vérifier AWS
aws sts get-caller-identity
# Doit afficher ton compte AWS
```

### Option A — Déploiement automatique (une commande)

```bash
# Clone le projet
git clone <ton-repo> netpulse
cd netpulse

# Rendre le script exécutable
chmod +x deploy.sh

# Déployer TOUT en une commande
./deploy.sh all
# Durée totale : environ 20-30 minutes
```

### Option B — Déploiement manuel étape par étape

#### Étape 1 : Build et push des images Docker

```bash
# Se connecter à Docker Hub
docker login

# Construire les images
docker build -t arsprod01/netpulse-backend:v2.0  ./app/backend/
docker build -t arsprod01/netpulse-frontend:v2.0 ./app/frontend/

# Pousser sur Docker Hub
docker push arsprod01/netpulse-backend:v2.0
docker push arsprod01/netpulse-frontend:v2.0
```

#### Étape 2 : Créer l'infrastructure AWS

```bash
cd terraform/

# Initialiser Terraform
terraform init

# Voir ce qui va être créé (lecture seule, sans risque)
terraform plan

# Créer les ressources
terraform apply
# Confirmer avec "yes"
# Durée : 2-3 minutes

# Récupérer les IPs
terraform output
# master_public_ip = "3.234.179.176"
# worker_public_ip = "54.166.132.5"

# Mettre à jour l'inventaire Ansible avec les vraies IPs
cd ..
nano ansible/inventory.ini
```

#### Étape 3 : Configurer le cluster

```bash
# Attendre 60 secondes que les serveurs AWS démarrent
sleep 60

# Lancer le playbook Ansible
ansible-playbook \
  -i ansible/inventory.ini \
  ansible/playbook.yml \
  --timeout=600 \
  -v
# Durée : 10-15 minutes
# -v : mode verbose (voir ce qui se passe)
```

#### Étape 4 : Déployer l'application

```bash
# Se connecter au master
ssh -i ~/.ssh/devops-aws-key ubuntu@3.234.179.176

# Sur le master : créer le dossier des manifests
mkdir -p /home/ubuntu/k8s-manifests
exit

# Copier les manifests sur le master
scp -i ~/.ssh/devops-aws-key k8s/*.yaml ubuntu@3.234.179.176:/home/ubuntu/k8s-manifests/

# Appliquer les manifests
ssh -i ~/.ssh/devops-aws-key ubuntu@3.234.179.176 "
  # Créer le namespace et le PV PostgreSQL
  kubectl create namespace netpulse --dry-run=client -o yaml | kubectl apply -f -
  
  WORKER=$(kubectl get nodes --selector='!node-role.kubernetes.io/control-plane' \
    -o jsonpath='{.items[0].metadata.name}')
  
  kubectl apply -f - <<EOF
  apiVersion: v1
  kind: PersistentVolume
  metadata:
    name: postgres-pv
  spec:
    capacity:
      storage: 2Gi
    accessModes: [ReadWriteOnce]
    hostPath:
      path: /mnt/data/postgres
    nodeAffinity:
      required:
        nodeSelectorTerms:
        - matchExpressions:
          - key: kubernetes.io/hostname
            operator: In
            values: [\${WORKER}]
  EOF
  
  # Appliquer tous les manifests dans l'ordre
  for f in /home/ubuntu/k8s-manifests/*.yaml; do kubectl apply -f \$f; done
  
  # Attendre que les pods démarrent
  kubectl wait --for=condition=ready pod --all -n netpulse --timeout=300s
  
  # Voir le résultat
  kubectl get pods -n netpulse -o wide
  kubectl get svc -n netpulse
"
```

### Test local sans AWS (Docker Compose)

```bash
cd app/

# Démarrer tout en local
docker compose up -d

# Vérifier
docker compose ps

# Tester
curl http://localhost:3000/health
curl http://localhost:3000/api/stats

# Ouvrir le dashboard
open http://localhost

# Arrêter
docker compose down
```

---

## 12. Problèmes rencontrés et solutions

### Problème 1 — `Error: "description" doesn't comply with restrictions`

**Symptôme :**
```
Error: "ingress.5.description" doesn't comply with restrictions
("^[0-9A-Za-z_ .:/()#,@\[\]+=&;{}!$*-]*$"):
"Cilium health check (inter-nœuds)"
```

**Cause :** AWS n'accepte que des caractères ASCII dans les descriptions de Security Groups. Le caractère `œ` (dans "nœuds") est non-ASCII.

**Solution :** Remplacer tous les caractères spéciaux dans `security_groups.tf` :
```hcl
# ❌ Avant
description = "Cilium health check (inter-nœuds)"
description = "Cilium VXLAN / GENEVE (encapsulation réseau pods)"

# ✅ Après
description = "Cilium health check (inter-nodes)"
description = "Cilium VXLAN GENEVE encapsulation"
```

---

### Problème 2 — `Error: tunnel was deprecated in v1.14 and has been removed in v1.15`

**Symptôme :**
```
Error: execution error at (cilium/templates/validate.yaml:41:5):
tunnel was deprecated in v1.14 and has been removed in v1.15.
```

**Cause :** L'option `--set tunnel=vxlan` a été supprimée dans Cilium 1.15. Ce projet utilise Cilium 1.19.3.

**Solution :** Remplacer par les nouvelles options :
```bash
# ❌ Avant (Cilium < 1.15)
--set tunnel=vxlan

# ✅ Après (Cilium >= 1.15)
--set routingMode=tunnel \
--set tunnelProtocol=vxlan
```

---

### Problème 3 — Cilium en `CrashLoopBackOff`

**Symptôme :**
```
cilium-tqk29   0/1   CrashLoopBackOff   10 (39s ago)   27m
```

**Cause :** L'option `hostFirewall=true` requiert le support BPF host firewall dans le kernel Linux. Les instances AWS t2.medium (kernel 6.2.0-aws) ne le supportent pas dans la configuration par défaut d'AWS.

**Solution :** Supprimer `hostFirewall` et `autoDirectNodeRoutes` de la commande Helm :
```bash
# ❌ Ne pas mettre sur instances AWS t2
--set hostFirewall.enabled=true
--set autoDirectNodeRoutes=true

# ✅ Configuration compatible t2.medium
--set routingMode=tunnel
--set tunnelProtocol=vxlan
# (pas de hostFirewall, pas de autoDirectNodeRoutes)
```

---

### Problème 4 — `kube-prometheus-stack` timeout lors de l'installation

**Symptôme :**
```
Error: failed pre-install: 1 error occurred:
* timed out waiting for the condition
```

**Cause :** Les webhooks de validation de kube-prometheus-stack (admission controllers) ont besoin d'une connectivité réseau inter-pods pour fonctionner. Si Cilium est en CrashLoopBackOff, le réseau des pods ne fonctionne pas, et les webhooks ne peuvent pas répondre.

**Solution :** Installer dans le bon ordre :
1. Corriger Cilium (voir problème 3)
2. Attendre que Cilium soit `Running`
3. **Ensuite seulement** installer kube-prometheus-stack

```bash
# Vérifier que Cilium est Running avant d'installer Prometheus
kubectl get pods -n kube-system | grep cilium
# Doit afficher "Running"

# Ensuite
helm install kube-prometheus-stack ...
```

---

### Problème 5 — HTTP 426 (Upgrade Required) sur `/api/stats`

**Symptôme :** Le dashboard affiche "Chargement..." en permanence. Dans les logs Nginx :
```
"GET /api/stats HTTP/1.1" 426
```

**Cause :** Par défaut, Nginx utilise HTTP/1.0 pour ses connexions proxy en amont. En HTTP/1.0, Nginx ajoute automatiquement le header `Connection: close`. Node.js/Express interprète ça comme une demande d'upgrade de protocole et répond avec `426 Upgrade Required`.

**Solution :** Forcer HTTP/1.1 dans `nginx.conf` :
```nginx
location /api/ {
    proxy_pass http://backend-service:3000;
    # ✅ Forcer HTTP/1.1 (pas HTTP/1.0)
    proxy_http_version 1.1;
    # ✅ Vider le header Connection pour éviter le 426
    proxy_set_header Connection "";
    proxy_set_header Host $host;
}
```

---

### Problème 6 — NetworkPolicy L7 bloque le trafic Nginx → backend

**Symptôme :** Après avoir ajouté des règles L7 HTTP dans la CiliumNetworkPolicy (vérification de méthode et chemin), les requêtes du frontend vers le backend sont bloquées.

**Cause :** Cilium inspecte les headers HTTP bruts. Nginx modifie les headers en ajoutant `X-Real-IP`, `X-Forwarded-For`, `Host`, etc. L'inspection L7 de Cilium comparait les headers modifiés aux règles et les rejetait.

**Solution :** Utiliser des règles L4 TCP uniquement (sans inspection HTTP) :
```yaml
# ❌ Règles L7 HTTP (problématiques avec Nginx proxy)
toPorts:
  - ports:
      - port: "3000"
    rules:
      http:
        - method: GET
          path: "/api/.*"

# ✅ Règles L4 TCP uniquement (robustes)
toPorts:
  - ports:
      - port: "3000"
        protocol: TCP
```

---

## 13. URLs et vérifications finales

### URLs du projet déployé

```
NetPulse Dashboard : http://3.234.179.176:30000
Grafana            : http://3.234.179.176:31000  (admin / netpulse2025)
Prometheus         : http://3.234.179.176:31001
Backend API direct : http://3.234.179.176:30001/api/stats
Hubble UI          : kubectl port-forward -n kube-system svc/hubble-ui 12000:80
```

### Commandes de vérification sur le master

```bash
ssh -i ~/.ssh/devops-aws-key ubuntu@3.234.179.176

# État général du cluster
kubectl get nodes -o wide
# NAME            STATUS   ROLES           AGE   VERSION
# ip-10-0-1-245   Ready    control-plane   61m   v1.29.15
# ip-10-0-1-72    Ready    <none>          33m   v1.29.15

# Pods de l'application
kubectl get pods -n netpulse -o wide
# NAME                        READY   STATUS    RESTARTS   AGE
# backend-xxx    1/1     Running   0          10m
# frontend-xxx   1/1     Running   0          10m
# postgres-xxx   1/1     Running   0          10m

# Pods du monitoring
kubectl get pods -n monitoring
# Prometheus, Grafana, AlertManager doivent être Running

# Services (pour voir les ports NodePort)
kubectl get svc -n netpulse
# frontend-service   NodePort   10.107.x.x   30000/TCP
# backend-service    NodePort   10.108.x.x   30001/TCP

# Statut Cilium
cilium status
# ou
kubectl get pods -n kube-system | grep cilium

# NetworkPolicies appliquées
kubectl get ciliumnetworkpolicies -n netpulse
# NAME                             AGE
# default-deny-all                 5m
# allow-frontend-to-backend        5m
# allow-backend-to-postgres        5m
# ...

# Tester le backend depuis l'intérieur du cluster
kubectl run test --image=busybox -n netpulse --rm -it --restart=Never -- \
  wget -qO- http://backend-service:3000/api/stats
# Doit retourner du JSON avec les statistiques

# Observer les flux réseau Hubble (CLI)
cilium hubble port-forward &
sleep 3
hubble observe --namespace netpulse --follow
# Affiche les flux en temps réel

# Voir uniquement les DROP
hubble observe --namespace netpulse --verdict DROPPED --follow
```

### Vérification des métriques Prometheus

```bash
# Ouvrir http://3.234.179.176:31001 dans ton navigateur

# Dans la barre de recherche Prometheus, tester :
hubble_drop_total                           # Flux bloqués par Cilium
hubble_flows_processed_total                # Tous les flux
netpulse_network_events_total               # Métriques NetPulse
netpulse_active_alerts                      # Alertes actives
node_cpu_seconds_total                      # CPU des nœuds
node_memory_MemAvailable_bytes              # RAM disponible
```

---

## 14. Glossaire

| Terme | Définition |
|-------|-----------|
| **AMI** | Amazon Machine Image — snapshot d'un OS prêt à l'emploi sur AWS |
| **Ansible** | Outil d'automatisation qui configure des serveurs via SSH à partir de fichiers YAML |
| **CiliumNetworkPolicy** | Règle réseau Cilium (plus puissante que les NetworkPolicy K8s standard) |
| **ClusterIP** | Type de Service K8s accessible seulement depuis l'intérieur du cluster |
| **CNI** | Container Network Interface — plugin qui gère le réseau entre pods |
| **ConfigMap** | Objet K8s pour stocker des configurations (fichiers de conf, variables) |
| **containerd** | Runtime de containers utilisé par Kubernetes (remplace Docker Engine dans K8s) |
| **CrashLoopBackOff** | État d'un pod qui plante et redémarre en boucle |
| **DaemonSet** | Ressource K8s qui garantit qu'un pod tourne sur CHAQUE nœud |
| **Deployment** | Ressource K8s qui gère un nombre fixe de copies d'un pod |
| **eBPF** | Extended Berkeley Packet Filter — technologie Linux pour exécuter du code dans le kernel |
| **EC2** | Elastic Compute Cloud — serveur virtuel AWS |
| **EIP** | Elastic IP — adresse IP publique fixe AWS |
| **Helm** | Gestionnaire de paquets pour Kubernetes (comme apt pour Ubuntu) |
| **Hubble** | Interface d'observabilité réseau de Cilium (visualise les flux L3/L4/L7) |
| **IGW** | Internet Gateway — porte d'entrée/sortie AWS vers internet |
| **Ingress** (réseau) | Trafic entrant vers un pod |
| **kubeadm** | Outil pour initialiser un cluster Kubernetes |
| **kubectl** | Outil CLI pour contrôler un cluster Kubernetes |
| **kubelet** | Agent Kubernetes qui tourne sur chaque nœud et gère les pods locaux |
| **kube-proxy** | Composant K8s gérant le routage des Services (remplacé par Cilium eBPF ici) |
| **Liveness Probe** | Vérification régulière : si elle échoue, K8s redémarre le pod |
| **Namespace** | Espace de noms isolé dans Kubernetes (comme un dossier) |
| **NodePort** | Type de Service K8s accessible depuis l'extérieur via un port sur chaque nœud |
| **PersistentVolume** | Volume de stockage persistant dans K8s (survit aux redémarrages de pods) |
| **PersistentVolumeClaim** | Demande de stockage persistant faite par un pod |
| **Pod** | Plus petite unité Kubernetes — un ou plusieurs containers qui partagent le réseau |
| **PodMonitor** | Ressource Prometheus Operator pour scraper des pods |
| **PromQL** | Langage de requêtes de Prometheus |
| **Readiness Probe** | Vérification régulière : si elle échoue, K8s arrête d'envoyer du trafic au pod |
| **ReplicaSet** | Ressource K8s qui garantit un nombre fixe de pods identiques |
| **Secret** | Objet K8s pour stocker des données sensibles (mots de passe, tokens) encodées en base64 |
| **Security Group** | Pare-feu virtuel AWS qui contrôle le trafic entrant/sortant |
| **Service** | Ressource K8s qui expose des pods via une adresse IP stable |
| **ServiceMonitor** | Ressource Prometheus Operator pour scraper des Services |
| **Subnet** | Sous-réseau dans un VPC AWS |
| **Terraform** | Outil d'Infrastructure as Code pour créer des ressources cloud via des fichiers HCL |
| **user_data** | Script exécuté au premier démarrage d'une instance EC2 |
| **VXLAN** | Virtual Extensible LAN — protocole de tunnel réseau utilisé par Cilium |
| **VPC** | Virtual Private Cloud — réseau privé isolé dans AWS |
| **Zero Trust** | Principe de sécurité : tout est bloqué par défaut, on autorise explicitement |

---

*Guide rédigé par Amadou — Collège Boréal, Toronto — Avril 2026*  
*Computer Systems Technician — Projet DevOps Final*