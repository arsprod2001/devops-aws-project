# 📚 Cours Complet : Kubernetes & Terraform
### De zéro à opérationnel — Explications pédagogiques avec exemples concrets

> **Pour qui ?** Débutant complet sur ces deux outils  
> **Niveau :** Collégial avancé → Professionnel  
> **Temps de lecture :** ~2 heures

---

## 📋 Table des matières

### PARTIE 1 — TERRAFORM
1. [C'est quoi Terraform ?](#1-cest-quoi-terraform-)
2. [Comment Terraform fonctionne ?](#2-comment-terraform-fonctionne-)
3. [Le langage HCL](#3-le-langage-hcl)
4. [Les concepts fondamentaux](#4-les-concepts-fondamentaux-terraform)
5. [Terraform avec AWS — Pas à pas](#5-terraform-avec-aws--pas-à-pas)
6. [Les commandes Terraform](#6-les-commandes-terraform)
7. [Les bonnes pratiques](#7-les-bonnes-pratiques-terraform)

### PARTIE 2 — KUBERNETES
8. [C'est quoi Kubernetes ?](#8-cest-quoi-kubernetes-)
9. [L'architecture de Kubernetes](#9-larchitecture-de-kubernetes)
10. [Les objets Kubernetes](#10-les-objets-kubernetes)
11. [Les fichiers YAML Kubernetes](#11-les-fichiers-yaml-kubernetes)
12. [kubectl — La télécommande de K8s](#12-kubectl--la-télécommande-de-k8s)
13. [Déployer une vraie application](#13-déployer-une-vraie-application)
14. [Concepts avancés](#14-concepts-avancés)
15. [Terraform + Kubernetes ensemble](#15-terraform--kubernetes-ensemble)

---

---

# PARTIE 1 — TERRAFORM 🌍

---

## 1. C'est quoi Terraform ?

### L'analogie du chef cuisinier 👨‍🍳

Imagine que tu veux ouvrir un restaurant. Tu as deux options :

**Option A — À la main (sans Terraform) :**
1. Tu appelles AWS par téléphone et tu demandes un serveur
2. Tu cliques partout dans la console AWS pour configurer le réseau
3. Tu configures manuellement chaque paramètre
4. Si tu veux refaire la même chose demain, tu recommences tout
5. Si tu fais une erreur, tu ne sais pas quoi changer

**Option B — Avec Terraform :**
1. Tu écris une "recette" (un fichier texte) qui décrit ton restaurant
2. Terraform lit la recette et construit tout automatiquement
3. La même recette peut être réutilisée à l'infini
4. Si tu veux changer quelque chose, tu modifies la recette et Terraform met à jour

> 💡 **Définition officielle :** Terraform est un outil d'**Infrastructure as Code (IaC)** — il permet de décrire une infrastructure informatique (serveurs, réseaux, bases de données) sous forme de fichiers texte, et de la créer/modifier/supprimer automatiquement.

### Pourquoi c'est révolutionnaire ?

| Sans Terraform | Avec Terraform |
|----------------|----------------|
| Cliquer dans des menus pendant des heures | Une commande : `terraform apply` |
| Impossible de reproduire exactement | Identique à chaque fois |
| Difficile de voir ce qui a changé | `git diff` sur les fichiers |
| Erreurs humaines fréquentes | Automatique = moins d'erreurs |
| Documentation souvent obsolète | Le code IS la documentation |

### Terraform supporte quoi ?

Terraform fonctionne avec **plus de 1000 fournisseurs** :

```
☁️  Cloud public     : AWS, Azure, Google Cloud, Oracle Cloud
🏢  On-premise       : VMware, OpenStack
🗄️  Bases de données : MySQL, PostgreSQL, MongoDB Atlas
🔀  DNS & réseau     : Cloudflare, Akamai
📦  Containers       : Docker, Kubernetes
🔐  Sécurité        : Vault, Auth0
```

---

## 2. Comment Terraform fonctionne ?

### Le cycle de vie Terraform

```
┌─────────────────────────────────────────────────────────┐
│                   TERRAFORM WORKFLOW                     │
│                                                         │
│   Écrire         Planifier        Appliquer             │
│   ──────         ─────────        ─────────             │
│                                                         │
│  .tf files  →  terraform    →  terraform               │
│  (code)         plan            apply                   │
│                 │                │                      │
│                 ▼                ▼                      │
│            Affiche ce       Crée/Modifie/               │
│            qui va           Supprime les                 │
│            changer          ressources                   │
│                                                         │
│                   ┌─────────────┐                       │
│                   │  terraform  │                       │
│                   │   .tfstate  │                       │
│                   │  (mémoire)  │                       │
│                   └─────────────┘                       │
│            Terraform se souvient de ce qu'il a créé     │
└─────────────────────────────────────────────────────────┘
```

### Le fichier State — La mémoire de Terraform

**C'est quoi le State ?**

Terraform garde un fichier appelé `terraform.tfstate` (format JSON) qui contient :
- Toutes les ressources qu'il a créées
- Leurs identifiants AWS (ID de l'EC2, du VPC, etc.)
- Leurs configurations actuelles

**Pourquoi c'est important ?**

```
Situation : Tu as créé un VPC avec Terraform.
            Ensuite tu changes le nom du VPC dans ton code.

Sans State : Terraform ne sait pas que le VPC existe déjà
             → Il en crée un nouveau ! (problème)

Avec State : Terraform compare le code vs l'état actuel
             → Il modifie le VPC existant (correct ✓)
```

### Comment Terraform compare-t-il ?

```
Code Terraform        State actuel         AWS réel
(ce que tu veux)   (ce que T. sait)    (ce qui existe)
      │                   │                   │
      └────────────┬───────┘                  │
                   │ compare                  │
                   ▼                          │
              Différences                     │
              détectées ──────────────────────►
                              APPLY : met AWS à jour
```

---

## 3. Le langage HCL

### HCL = HashiCorp Configuration Language

HCL est le langage utilisé par Terraform. C'est un langage **déclaratif** — tu décris CE QUE tu veux, pas COMMENT le faire.

### La syntaxe de base

```hcl
# Ceci est un commentaire

# Structure de base d'un bloc Terraform :
TYPE "NOM_PROVIDER" "NOM_LOGIQUE" {
  argument1 = valeur1
  argument2 = valeur2
}
```

**Exemple concret :**

```hcl
# Créer une instance EC2 sur AWS
resource "aws_instance" "mon_serveur" {
#  ──────────────  ────────────────
#  TYPE = aws_instance  NOM = mon_serveur (tu choisis)

  ami           = "ami-0a2e7efb4257c0907"   # L'image Ubuntu à utiliser
  instance_type = "t2.micro"                # Le type de machine
}
```

### Les types de blocs

#### 1. `resource` — Créer une ressource

```hcl
# Créer un bucket S3
resource "aws_s3_bucket" "mes_fichiers" {
  bucket = "mon-bucket-unique-123"
}

# Créer une instance EC2
resource "aws_instance" "serveur_web" {
  ami           = "ami-12345"
  instance_type = "t2.micro"
  tags = {
    Name = "Serveur Web"
  }
}
```

#### 2. `variable` — Définir des paramètres réutilisables

```hcl
# Sans variable (mauvaise pratique) :
resource "aws_instance" "serveur" {
  instance_type = "t2.micro"    # Valeur codée en dur
}

# Avec variable (bonne pratique) :
variable "type_instance" {
  description = "Type d'instance EC2 à créer"
  type        = string
  default     = "t2.micro"    # Valeur par défaut
}

resource "aws_instance" "serveur" {
  instance_type = var.type_instance    # On utilise la variable
}

# Avantage : changer "t2.micro" en "t3.small" = modifier une seule ligne
```

#### 3. `output` — Afficher des informations après apply

```hcl
# Afficher l'IP publique de l'instance après création
output "ip_publique" {
  description = "IP publique du serveur"
  value       = aws_instance.serveur_web.public_ip
}

# Après terraform apply, tu verras :
# Outputs:
# ip_publique = "54.23.45.67"
```

#### 4. `data` — Lire des informations existantes

```hcl
# Récupérer des infos sur une ressource AWS existante
# (sans la créer)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]    # Canonical (éditeur d'Ubuntu)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*-22.04-amd64-server-*"]
  }
}

# Utiliser dans une resource :
resource "aws_instance" "serveur" {
  ami = data.aws_ami.ubuntu.id    # L'AMI Ubuntu la plus récente
}
```

#### 5. `locals` — Créer des valeurs calculées

```hcl
locals {
  # Combiner des valeurs
  nom_complet = "${var.projet}-${var.environnement}"
  # → "monprojet-dev"

  tags_communs = {
    Projet      = var.projet
    Createur    = "Terraform"
    DateCreation = "2025"
  }
}

resource "aws_instance" "serveur" {
  ami           = "ami-12345"
  instance_type = "t2.micro"
  tags          = local.tags_communs    # Réutiliser les tags
}
```

### Les types de données en HCL

```hcl
# String (texte)
variable "region" {
  type    = string
  default = "ca-central-1"
}

# Number (nombre)
variable "nb_instances" {
  type    = number
  default = 2
}

# Bool (vrai/faux)
variable "activer_https" {
  type    = bool
  default = true
}

# List (liste)
variable "zones" {
  type    = list(string)
  default = ["ca-central-1a", "ca-central-1b"]
}

# Map (dictionnaire clé-valeur)
variable "tags" {
  type = map(string)
  default = {
    Environnement = "dev"
    Projet        = "mon-app"
  }
}

# Object (objet structuré)
variable "serveur" {
  type = object({
    type   = string
    disque = number
  })
  default = {
    type   = "t2.micro"
    disque = 20
  }
}
```

### Les références entre ressources

```hcl
# Créer un VPC
resource "aws_vpc" "principal" {
  cidr_block = "10.0.0.0/16"
}

# Créer un sous-réseau DANS le VPC
resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.principal.id    # ← Référence au VPC
  cidr_block = "10.0.1.0/24"
  #             TYPE.NOM.ATTRIBUT
  #             aws_vpc.principal.id
}
```

**Syntaxe de référence :**
```
TYPE_RESSOURCE.NOM_LOGIQUE.ATTRIBUT
aws_vpc.principal.id
aws_instance.serveur.public_ip
aws_security_group.web.id
```

---

## 4. Les concepts fondamentaux Terraform

### 4.1 Le Provider

Le Provider est le "plugin" qui connecte Terraform à AWS (ou Azure, ou GCP...).

```hcl
# Configurer le provider AWS
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"   # D'où télécharger le plugin
      version = "~> 5.0"          # Version à utiliser
    }
  }
}

provider "aws" {
  region = "ca-central-1"
  # Les credentials viennent de ~/.aws/credentials
}
```

**Que fait `terraform init` ?**

```bash
terraform init
# → Télécharge le provider AWS (~50 MB)
# → Crée le dossier .terraform/
# → Génère .terraform.lock.hcl (verrouille les versions)
```

### 4.2 Les Modules

Un module = un groupe de ressources réutilisables. C'est comme une fonction en programmation.

```
Sans modules :
  main.tf → 500 lignes de code, tout mélangé

Avec modules :
  modules/
    vpc/         → Tout ce qui concerne le réseau
    ec2/         → Tout ce qui concerne les serveurs
    security/    → Tout ce qui concerne la sécurité

  main.tf → 30 lignes qui appellent les modules
```

```hcl
# Utiliser un module
module "vpc" {
  source = "./modules/vpc"        # Chemin vers le module

  # Paramètres du module
  region     = "ca-central-1"
  cidr_block = "10.0.0.0/16"
}

module "serveur" {
  source = "./modules/ec2"

  vpc_id    = module.vpc.vpc_id    # Utilise la sortie du module vpc
  subnet_id = module.vpc.subnet_id
}
```

### 4.3 Les Workspaces

Les workspaces permettent de gérer plusieurs environnements (dev, staging, prod) avec le même code.

```bash
# Créer un workspace "dev"
terraform workspace new dev

# Créer un workspace "prod"
terraform workspace new prod

# Voir les workspaces
terraform workspace list
# * dev
#   prod

# Switcher vers prod
terraform workspace select prod
```

```hcl
# Dans le code, utiliser le workspace
resource "aws_instance" "serveur" {
  instance_type = terraform.workspace == "prod" ? "t3.medium" : "t2.micro"
  #               Si workspace = prod → t3.medium, sinon → t2.micro
}
```

### 4.4 Les Dépendances

Terraform comprend automatiquement l'ordre de création :

```hcl
# Terraform sait qu'il doit créer le VPC AVANT le subnet
# car le subnet référence le VPC

resource "aws_vpc" "main" {          # Créé en premier
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public" {     # Créé en deuxième
  vpc_id     = aws_vpc.main.id       # ← Dépendance implicite
  cidr_block = "10.0.1.0/24"
}

resource "aws_instance" "web" {      # Créé en dernier
  subnet_id = aws_subnet.public.id   # ← Dépendance implicite
  # ...
}
```

**Dépendance explicite (quand pas de référence directe) :**

```hcl
resource "aws_s3_bucket" "logs" {
  bucket = "mes-logs"
}

resource "aws_instance" "web" {
  ami           = "ami-12345"
  instance_type = "t2.micro"

  depends_on = [aws_s3_bucket.logs]    # Attendre que le bucket soit créé
}
```

---

## 5. Terraform avec AWS — Pas à pas

### 5.1 Ton premier fichier Terraform

Créons quelque chose de très simple : un VPC et une instance EC2.

**Structure :**
```
mon-projet/
├── main.tf
├── variables.tf
└── outputs.tf
```

**`variables.tf` :**
```hcl
variable "region" {
  default = "ca-central-1"
}

variable "nom_projet" {
  default = "mon-premier-projet"
}
```

**`main.tf` :**
```hcl
# ─── Provider ──────────────────────────────────────
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# ─── VPC ───────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name    = "${var.nom_projet}-vpc"
    Createur = "Terraform"
  }
}

# ─── Sous-réseau ───────────────────────────────────
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.nom_projet}-subnet"
  }
}

# ─── Internet Gateway ──────────────────────────────
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.nom_projet}-igw"
  }
}

# ─── Security Group ────────────────────────────────
resource "aws_security_group" "web" {
  name   = "${var.nom_projet}-sg"
  vpc_id = aws_vpc.main.id

  # Autoriser SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Autoriser HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Autoriser tout le trafic sortant
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ─── Instance EC2 ──────────────────────────────────
resource "aws_instance" "web" {
  ami                    = "ami-0a2e7efb4257c0907"   # Ubuntu 22.04
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]

  tags = {
    Name = "${var.nom_projet}-serveur"
  }
}
```

**`outputs.tf` :**
```hcl
output "ip_publique" {
  value = aws_instance.web.public_ip
}

output "vpc_id" {
  value = aws_vpc.main.id
}
```

### 5.2 Exécuter Terraform

```bash
# Étape 1 : Initialiser
terraform init
# Télécharge le provider AWS

# Étape 2 : Vérifier la syntaxe
terraform validate
# Success! The configuration is valid.

# Étape 3 : Formater le code (optionnel mais recommandé)
terraform fmt

# Étape 4 : Voir ce qui va être créé
terraform plan
# Terraform will perform the following actions:
#
#   # aws_instance.web will be created
#   + resource "aws_instance" "web" {
#       + ami           = "ami-0a2e7efb4257c0907"
#       + instance_type = "t2.micro"
#       ...
#     }
#
# Plan: 5 to add, 0 to change, 0 to destroy.

# Étape 5 : Créer l'infrastructure
terraform apply
# Do you want to perform these actions? yes

# Étape 6 : Voir les outputs
terraform output
# ip_publique = "54.23.45.67"
# vpc_id = "vpc-0abc123"
```

### 5.3 Modifier l'infrastructure

```bash
# Tu changes instance_type de t2.micro à t2.small dans main.tf

terraform plan
# ~ aws_instance.web will be updated in-place
#   ~ instance_type = "t2.micro" -> "t2.small"
# Plan: 0 to add, 1 to change, 0 to destroy.

terraform apply
# Applique le changement sans recréer l'instance
```

### 5.4 Supprimer l'infrastructure

```bash
terraform destroy
# Terraform will destroy all resources.
# Do you really want to destroy? yes

# Tout est supprimé !
# IMPORTANT : Toujours faire ça après les tests pour éviter les frais AWS
```

---

## 6. Les commandes Terraform

```bash
# ─────────────────────────────────────────────────
# COMMANDES ESSENTIELLES
# ─────────────────────────────────────────────────

terraform init          # Initialiser le projet (à faire une fois)
terraform plan          # Voir ce qui va changer (toujours faire avant apply)
terraform apply         # Créer/modifier l'infrastructure
terraform destroy       # TOUT supprimer

# ─────────────────────────────────────────────────
# COMMANDES UTILES
# ─────────────────────────────────────────────────

terraform validate      # Vérifier la syntaxe HCL
terraform fmt           # Formater automatiquement le code
terraform output        # Afficher les outputs
terraform show          # Afficher l'état actuel

# Voir l'état d'une ressource spécifique
terraform state show aws_instance.web

# Lister toutes les ressources dans le state
terraform state list

# Appliquer sans demander de confirmation (pour CI/CD)
terraform apply -auto-approve

# Plan avec sauvegarde du plan
terraform plan -out=monplan.tfplan
terraform apply monplan.tfplan

# Cibler une ressource spécifique
terraform apply -target=aws_instance.web
terraform destroy -target=aws_instance.web
```

---

## 7. Les bonnes pratiques Terraform

### 7.1 Organisation des fichiers

```
projet-terraform/
├── main.tf           # Ressources principales
├── variables.tf      # Toutes les variables
├── outputs.tf        # Tous les outputs
├── providers.tf      # Configuration des providers
├── versions.tf       # Versions requises
├── locals.tf         # Variables calculées
└── terraform.tfvars  # Valeurs des variables (NE PAS committer si secrets)
```

### 7.2 Le fichier .tfvars

```hcl
# terraform.tfvars — Valeurs concrètes des variables
region       = "ca-central-1"
nom_projet   = "eventick"
environnement = "dev"
```

```bash
# Utiliser un fichier de variables
terraform apply -var-file="dev.tfvars"
terraform apply -var-file="prod.tfvars"
```

### 7.3 Le .gitignore Terraform

```gitignore
# Fichiers à NE PAS committer

# State files (contiennent des infos sensibles)
*.tfstate
*.tfstate.backup
.terraform/

# Fichiers de variables avec secrets
terraform.tfvars

# Plans sauvegardés
*.tfplan
```

### 7.4 Nommer les ressources clairement

```hcl
# ❌ Mauvais nommage
resource "aws_instance" "a" { }
resource "aws_vpc" "x" { }

# ✅ Bon nommage
resource "aws_instance" "web_server" { }
resource "aws_vpc" "main_network" { }
```

---

---

# PARTIE 2 — KUBERNETES ☸️

---

## 8. C'est quoi Kubernetes ?

### L'analogie de l'orchestre 🎼

Imagine un orchestre symphonique :
- Les musiciens = tes applications (containers)
- Le chef d'orchestre = Kubernetes
- La partition = tes fichiers YAML

Sans chef d'orchestre, les musiciens jouent n'importe comment. Avec le chef, tout est coordonné, et si un musicien tombe malade, il est immédiatement remplacé.

**Kubernetes fait pareil avec tes containers :**
- Il démarre les containers
- Il les redémarre si ils tombent en panne
- Il les distribue sur plusieurs serveurs
- Il les met à l'échelle selon la charge
- Il gère le réseau entre eux
- Il fait des mises à jour sans interruption

### Pourquoi Kubernetes ? Le problème des containers seuls

```
PROBLÈME : Tu as 10 containers à gérer sur 5 serveurs

Sans Kubernetes (à la main) :
  - Surveiller chaque container manuellement
  - Redémarrer à la main en cas de crash
  - Load balancing manuel
  - Mises à jour = downtime
  - Cauchemar opérationnel

Avec Kubernetes :
  - Surveillance automatique
  - Auto-healing (redémarrage automatique)
  - Load balancing intégré
  - Rolling updates (zéro downtime)
  - Un seul outil pour tout gérer
```

### Kubernetes vs Docker

```
Docker    : "Je crée et exécute UN container"
Kubernetes: "Je gère DES CENTAINES de containers sur des dizaines de serveurs"

Analogie :
Docker    = Un camion de livraison
Kubernetes = FedEx (le système qui coordonne tous les camions)
```

### Les origines de Kubernetes

- Créé par **Google** en 2014
- Basé sur Borg (le système interne de Google qui tourne depuis 2003)
- Open-source depuis 2014
- Aujourd'hui maintenu par la **CNCF** (Cloud Native Computing Foundation)
- Utilisé par Netflix, Airbnb, Spotify, AWS, Azure, Google Cloud

---

## 9. L'architecture de Kubernetes

### Vue d'ensemble

```
┌─────────────────────────────────────────────────────────────────────┐
│                        CLUSTER KUBERNETES                            │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                    CONTROL PLANE (Master)                    │   │
│  │                                                              │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │   │
│  │  │  API Server  │  │  Scheduler   │  │  Controller Mgr  │  │   │
│  │  │   (cerveau)  │  │  (planifie)  │  │  (surveille)     │  │   │
│  │  └──────────────┘  └──────────────┘  └──────────────────┘  │   │
│  │  ┌──────────────┐                                           │   │
│  │  │    etcd      │                                           │   │
│  │  │  (mémoire)   │                                           │   │
│  │  └──────────────┘                                           │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                              │                                      │
│           ┌──────────────────┼──────────────────┐                  │
│           │                  │                  │                  │
│  ┌────────────────┐  ┌───────────────┐  ┌───────────────┐         │
│  │   WORKER 1     │  │   WORKER 2    │  │   WORKER 3    │         │
│  │                │  │               │  │               │         │
│  │  ┌──────────┐  │  │  ┌─────────┐  │  │  ┌─────────┐  │         │
│  │  │  Pod 1   │  │  │  │  Pod 3  │  │  │  │  Pod 5  │  │         │
│  │  │ frontend │  │  │  │ backend │  │  │  │ backend │  │         │
│  │  └──────────┘  │  │  └─────────┘  │  │  └─────────┘  │         │
│  │  ┌──────────┐  │  │  ┌─────────┐  │  │  ┌─────────┐  │         │
│  │  │  Pod 2   │  │  │  │  Pod 4  │  │  │  │  Pod 6  │  │         │
│  │  │ frontend │  │  │  │ database│  │  │  │ frontend│  │         │
│  │  └──────────┘  │  │  └─────────┘  │  │  └─────────┘  │         │
│  │                │  │               │  │               │         │
│  │  kubelet       │  │  kubelet      │  │  kubelet      │         │
│  │  kube-proxy    │  │  kube-proxy   │  │  kube-proxy   │         │
│  └────────────────┘  └───────────────┘  └───────────────┘         │
└─────────────────────────────────────────────────────────────────────┘
```

### Le Control Plane (Cerveau du cluster)

#### API Server
```
C'est le point d'entrée de tout.
Quand tu tapes kubectl get pods, tu parles à l'API Server.
Quand une application interne veut savoir l'état du cluster, elle appelle l'API Server.
C'est comme la réception d'une entreprise : tout passe par là.
```

#### etcd
```
C'est la BASE DE DONNÉES de Kubernetes.
Stocke TOUT l'état du cluster :
  - Combien de pods existent ?
  - Sur quel serveur tourne tel pod ?
  - Quelle est la configuration d'un Service ?

Si etcd est perdu = le cluster perd sa mémoire.
C'est pourquoi on le sauvegarde constamment.
```

#### Scheduler
```
Le Scheduler décide SUR QUEL SERVEUR faire tourner un pod.

Il analyse :
  - Les ressources disponibles sur chaque serveur (CPU, RAM)
  - Les contraintes définies dans le pod (labels, affinité)
  - L'état actuel du cluster

Exemple :
  "Ce pod a besoin de 512Mo RAM.
   Worker1 a 200Mo libre → Non
   Worker2 a 800Mo libre → Oui !"
```

#### Controller Manager
```
Surveille en permanence l'état du cluster.

"Tu m'as dit que tu veux 3 replicas du backend.
Je compte... 2 replicas. Il en manque un !
Je demande à créer un nouveau pod backend."

C'est le garant que l'état RÉEL = état DÉSIRÉ.
```

### Les Worker Nodes (Les serveurs qui font le travail)

#### kubelet
```
Agent installé sur chaque Worker.
Reçoit les instructions du Control Plane.
Lance et surveille les containers sur son serveur.

"Control Plane dit : lance ce pod ici."
kubelet : "OK, je le lance avec containerd."
```

#### kube-proxy
```
Gère le réseau sur chaque Worker.
Permet aux pods de communiquer entre eux.
Implémente les règles des Services.

Sans kube-proxy : les pods ne peuvent pas se parler.
```

#### Container Runtime
```
Le moteur qui exécute réellement les containers.
Peut être : containerd, CRI-O, Docker
Par défaut en K8s 1.24+ : containerd
```

---

## 10. Les objets Kubernetes

### 10.1 Pod — L'unité de base

**C'est quoi un Pod ?**

```
Un Pod = le plus petit déployable dans Kubernetes

Un Pod contient :
  - 1 ou plusieurs containers (Docker)
  - Un espace réseau partagé
  - Un espace de stockage partagé

Analogie : Une maison (Pod) avec des colocataires (containers).
Ils partagent la même adresse (IP) et le même espace de vie.
```

```yaml
# Un pod simple avec un seul container
apiVersion: v1
kind: Pod
metadata:
  name: mon-premier-pod
spec:
  containers:
    - name: nginx
      image: nginx:alpine
      ports:
        - containerPort: 80
```

**Caractéristiques importantes des Pods :**

```
✓ Chaque Pod a sa propre IP interne
✓ Plusieurs containers dans un Pod se voient via localhost
✗ Les Pods sont ÉPHÉMÈRES — si un Pod meurt, son IP change
✗ On ne crée JAMAIS des Pods directement en production
  → On utilise des Deployments qui gèrent les Pods
```

### 10.2 Deployment — Gérer des Pods

**C'est quoi un Deployment ?**

```
Un Deployment dit à Kubernetes :
"Je veux que 3 copies (replicas) de ce Pod tournent EN PERMANENCE."

Si un Pod meurt → Kubernetes en recrée un automatiquement.
Si tu veux mettre à jour → Kubernetes fait une Rolling Update.
Si la mise à jour échoue → Kubernetes revient en arrière (rollback).
```

```yaml
# Un Deployment avec 3 replicas
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mon-backend

spec:
  replicas: 3              # Je veux 3 copies du pod
  
  selector:
    matchLabels:
      app: backend         # Gérer les pods avec ce label

  template:                # Modèle du pod à créer
    metadata:
      labels:
        app: backend       # Label du pod (doit matcher le selector)
    
    spec:
      containers:
        - name: backend
          image: mon-image:v1.0
          ports:
            - containerPort: 3000
```

**Visualisation d'un Deployment :**

```
Deployment "mon-backend" (replicas: 3)
│
├── Pod backend-abc123 → Running sur Worker1
├── Pod backend-def456 → Running sur Worker2
└── Pod backend-ghi789 → Running sur Worker3

Si backend-abc123 crash :
Deployment détecte : "J'ai seulement 2 replicas, j'en veux 3!"
→ Crée automatiquement Pod backend-jkl012 sur Worker1
```

### 10.3 Service — Le réseau entre Pods

**Problème sans Service :**

```
Les pods ont des IPs qui CHANGENT à chaque redémarrage.

Exemple :
  Backend veut parler à la DB.
  DB Pod IP = 10.244.1.5
  La DB crashe et redémarre.
  DB Pod IP = 10.244.2.8  (DIFFÉRENT !)
  Backend ne sait plus où trouver la DB !
```

**Solution : Le Service**

```
Un Service = une IP STABLE et un nom DNS qui pointe toujours
             vers les bons pods (même si les pods changent d'IP)

Exemple avec Service :
  Service "database-service" IP stable = 10.96.0.100
  Backend fait toujours des requêtes vers 10.96.0.100
  Le Service redirige vers le bon Pod DB, peu importe son IP
```

**Les 4 types de Services :**

```
1. ClusterIP (par défaut)
   ─────────────────────
   IP accessible SEULEMENT à l'intérieur du cluster.
   Pour communication interne entre pods.
   Exemple : Le backend accède à la DB via ClusterIP.

2. NodePort
   ────────
   Expose un port sur CHAQUE serveur (worker) du cluster.
   Accessible depuis l'extérieur via IP_SERVEUR:PORT.
   Port entre 30000-32767.
   Exemple : http://54.23.45.67:30080

3. LoadBalancer
   ────────────
   Crée un Load Balancer externe (ex: AWS ELB).
   IP publique automatique.
   Le plus utilisé en production sur le cloud.
   Exemple : http://54.23.45.67 (port 80)

4. ExternalName
   ─────────────
   Alias DNS vers un service externe.
   Exemple : Pointer vers une DB RDS AWS par nom.
```

```yaml
# Service ClusterIP — Interne seulement
apiVersion: v1
kind: Service
metadata:
  name: database-service

spec:
  type: ClusterIP          # Seulement accessible dans le cluster
  selector:
    app: database          # Cible les pods avec label app=database
  ports:
    - port: 5432           # Port du Service
      targetPort: 5432     # Port du container

---
# Service NodePort — Accessible de l'extérieur
apiVersion: v1
kind: Service
metadata:
  name: frontend-service

spec:
  type: NodePort
  selector:
    app: frontend
  ports:
    - port: 80             # Port interne
      targetPort: 80       # Port du container
      nodePort: 30080      # Port externe (accès depuis internet)
```

### 10.4 Namespace — Isoler les ressources

```yaml
# Un namespace isole les ressources
# Comme des dossiers dans un ordinateur

apiVersion: v1
kind: Namespace
metadata:
  name: production

---
# Déployer dans un namespace
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: production    # ← Spécifier le namespace
```

```bash
# Sans namespace : ressources dans "default"
kubectl get pods                     # Cherche dans "default"
kubectl get pods -n production       # Cherche dans "production"
kubectl get pods --all-namespaces    # Cherche partout
```

### 10.5 ConfigMap — Configuration externe

```yaml
# ConfigMap = fichier de configuration stocké dans K8s
# Ne pas mettre de secrets ici ! (Utiliser Secret à la place)

apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config

data:
  # Variables de configuration
  DATABASE_HOST: "database-service"
  DATABASE_PORT: "5432"
  APP_ENV: "production"
  LOG_LEVEL: "info"
  
  # Ou même un fichier de config entier
  app.properties: |
    server.port=3000
    database.pool.size=10
    cache.enabled=true
```

```yaml
# Utiliser le ConfigMap dans un Pod
spec:
  containers:
    - name: backend
      image: mon-image:v1
      envFrom:
        - configMapRef:
            name: app-config    # Injecte toutes les clés comme variables d'env
```

### 10.6 Secret — Données sensibles

```yaml
# Secret = comme ConfigMap, mais encodé en base64 et chiffré
# Pour les mots de passe, clés API, certificats

apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
type: Opaque

data:
  # Les valeurs DOIVENT être en base64
  # echo -n "monmotdepasse" | base64
  password: bW9ubW90ZGVwYXNzZQ==
  username: cG9zdGdyZXM=
```

```bash
# Encoder en base64 :
echo -n "monmotdepasse" | base64
# bW9ubW90ZGVwYXNzZQ==

# Décoder :
echo "bW9ubW90ZGVwYXNzZQ==" | base64 -d
# monmotdepasse
```

```yaml
# Utiliser un Secret dans un Pod
spec:
  containers:
    - name: backend
      env:
        - name: DB_PASSWORD          # Nom de la variable d'env dans le container
          valueFrom:
            secretKeyRef:
              name: db-credentials   # Nom du Secret
              key: password          # Clé dans le Secret
```

### 10.7 PersistentVolume — Stockage persistant

**Problème :** Les containers sont éphémères. Si un Pod meurt, ses données disparaissent.

**Solution :** Les PersistentVolumes (PV) et PersistentVolumeClaims (PVC).

```
PersistentVolume (PV) = Un disque physique disponible
PersistentVolumeClaim (PVC) = La demande d'un pod pour utiliser un disque

Analogie :
PV = Un appartement disponible à la location
PVC = Ta demande de location
Kubernetes = L'agence qui fait le matching
```

```yaml
# PersistentVolumeClaim — Demande de stockage
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: database-storage

spec:
  accessModes:
    - ReadWriteOnce      # Un seul pod peut lire/écrire à la fois
  resources:
    requests:
      storage: 5Gi       # Je veux 5 Go

---
# Utiliser le PVC dans un Pod
spec:
  containers:
    - name: postgres
      image: postgres:15
      volumeMounts:
        - name: data-volume
          mountPath: /var/lib/postgresql/data    # Où monter le disque dans le container
  
  volumes:
    - name: data-volume
      persistentVolumeClaim:
        claimName: database-storage    # Référencer le PVC
```

### 10.8 Ingress — Le routeur HTTP

```
Sans Ingress :
  frontend-service  → NodePort 30080 → http://IP:30080
  backend-service   → NodePort 30081 → http://IP:30081
  api-service       → NodePort 30082 → http://IP:30082

Avec Ingress :
  http://monapp.com/         → frontend-service
  http://monapp.com/api      → backend-service
  http://api.monapp.com      → api-service

Un seul point d'entrée, avec du routage basé sur l'URL !
```

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: mon-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /

spec:
  rules:
    - host: monapp.com           # Domaine
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: frontend-service
                port:
                  number: 80
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: backend-service
                port:
                  number: 3000
```

---

## 11. Les fichiers YAML Kubernetes

### Structure d'un fichier YAML K8s

```yaml
# CHAQUE fichier K8s a ces 4 champs obligatoires :

apiVersion: apps/v1        # Version de l'API K8s
kind: Deployment           # Type d'objet
metadata:                  # Informations sur l'objet
  name: mon-deployment
  namespace: default
  labels:
    app: monapp
spec:                      # La configuration (varie selon le kind)
  replicas: 3
  ...
```

### Le rôle des Labels et Selectors

**C'est LE concept le plus important de Kubernetes !**

```yaml
# Labels = étiquettes collées sur les objets
# Selector = filtre pour sélectionner des objets par leurs labels

# Le Deployment CRÉE des Pods avec ce label :
template:
  metadata:
    labels:
      app: backend         # Label collé sur chaque Pod créé
      version: "1.0"

# Le Service SÉLECTIONNE les Pods avec ce label :
spec:
  selector:
    app: backend           # "Je veux envoyer du trafic aux pods avec app=backend"
```

```
Visualisation :

Pod backend-111  [label: app=backend] ←─────┐
Pod backend-222  [label: app=backend] ←─────┤ Service "backend-svc"
Pod backend-333  [label: app=backend] ←─────┘  selector: app=backend

Pod frontend-111 [label: app=frontend] ← Ignoré par ce Service
```

### Comprendre les ressources CPU et mémoire

```yaml
resources:
  requests:                # Minimum garanti
    memory: "128Mi"        # 128 Mebibytes
    cpu: "100m"            # 100 millicores = 0.1 CPU
  limits:                  # Maximum autorisé
    memory: "256Mi"
    cpu: "500m"            # 500 millicores = 0.5 CPU
```

**Explication des unités :**

```
CPU :
  1000m (millicores) = 1 CPU complet
  500m               = 0.5 CPU (la moitié)
  100m               = 0.1 CPU (un dixième)

Mémoire :
  Mi = Mebibytes (1 Mi = 1.048 MB)
  Gi = Gibibytes (1 Gi = 1.073 GB)
  128Mi ≈ 128 MB
  1Gi   ≈ 1 GB
```

### Les Probes — Vérifications de santé

```yaml
containers:
  - name: backend
    image: mon-image:v1
    
    # Liveness Probe : "Est-ce que ce container est vivant ?"
    # Si ça échoue → Kubernetes redémarre le container
    livenessProbe:
      httpGet:
        path: /health      # Route à appeler
        port: 3000
      initialDelaySeconds: 30    # Attendre 30s avant le premier check
      periodSeconds: 10          # Vérifier toutes les 10s
      failureThreshold: 3        # 3 échecs → redémarrer
    
    # Readiness Probe : "Ce container est-il prêt à recevoir du trafic ?"
    # Si ça échoue → K8s retire ce pod du load balancer (mais ne le redémarre pas)
    readinessProbe:
      httpGet:
        path: /ready
        port: 3000
      initialDelaySeconds: 10
      periodSeconds: 5
```

**Différence Liveness vs Readiness :**

```
Liveness  = "Je suis vivant ?"
            → Réponse NON = REDÉMARRER le container

Readiness = "Je suis prêt à travailler ?"
            → Réponse NON = Ne plus m'envoyer de trafic (mais ne pas me tuer)

Exemple :
  Backend qui se connecte à la DB au démarrage.
  Liveness = OK dès que le process tourne
  Readiness = OK seulement quand la connexion DB est établie
```

---

## 12. kubectl — La télécommande de K8s

### Les commandes essentielles

```bash
# ══════════════════════════════════════════
# VOIR LES RESSOURCES
# ══════════════════════════════════════════

# Lister les pods
kubectl get pods
kubectl get pods -n mon-namespace
kubectl get pods --all-namespaces
kubectl get pods -o wide    # Plus de détails (IP, Node)

# Lister les deployments
kubectl get deployments
kubectl get deploy          # Raccourci

# Lister les services
kubectl get services
kubectl get svc             # Raccourci

# Lister les nodes (serveurs)
kubectl get nodes

# Tout en une commande
kubectl get all -n mon-namespace
kubectl get all --all-namespaces

# ══════════════════════════════════════════
# DÉPLOYER DES RESSOURCES
# ══════════════════════════════════════════

# Appliquer un fichier YAML
kubectl apply -f deployment.yaml

# Appliquer tous les fichiers YAML d'un dossier
kubectl apply -f ./k8s/

# Supprimer une ressource
kubectl delete -f deployment.yaml
kubectl delete pod mon-pod
kubectl delete deployment mon-deployment

# ══════════════════════════════════════════
# DÉBOGUER
# ══════════════════════════════════════════

# Voir les logs d'un pod
kubectl logs mon-pod
kubectl logs mon-pod -f         # Suivre en temps réel (comme tail -f)
kubectl logs mon-pod -c backend # Si le pod a plusieurs containers

# Voir les logs d'un deployment (tous les pods)
kubectl logs -l app=backend

# Décrire une ressource (très utile pour déboguer)
kubectl describe pod mon-pod
kubectl describe deployment mon-deployment
kubectl describe service mon-service

# Entrer dans un container (comme SSH)
kubectl exec -it mon-pod -- bash
kubectl exec -it mon-pod -c backend -- /bin/sh

# ══════════════════════════════════════════
# MISE À L'ÉCHELLE
# ══════════════════════════════════════════

# Changer le nombre de replicas
kubectl scale deployment mon-deployment --replicas=5

# ══════════════════════════════════════════
# MISES À JOUR
# ══════════════════════════════════════════

# Mettre à jour l'image d'un deployment
kubectl set image deployment/mon-deployment backend=mon-image:v2.0

# Voir le statut d'un rollout
kubectl rollout status deployment/mon-deployment

# Voir l'historique des mises à jour
kubectl rollout history deployment/mon-deployment

# Revenir en arrière (rollback)
kubectl rollout undo deployment/mon-deployment

# ══════════════════════════════════════════
# AUTRES UTILES
# ══════════════════════════════════════════

# Voir les ressources utilisées (CPU, RAM)
kubectl top nodes
kubectl top pods

# Port forwarding (accéder à un pod depuis ta machine locale)
kubectl port-forward pod/mon-pod 8080:3000
# → http://localhost:8080 redirige vers le pod port 3000

# Afficher la config kubectl actuelle
kubectl config view
kubectl config current-context
kubectl config get-contexts
```

### Comprendre les statuts des Pods

```
STATUS          SIGNIFICATION
──────────────────────────────────────────────────────
Pending         K8s cherche un serveur pour placer le pod
Running         Le pod tourne normalement ✓
Succeeded       Le pod a terminé avec succès (jobs)
Failed          Le pod a planté et ne sera pas redémarré
CrashLoopBackOff Le pod crashe en boucle → bug dans le code
ImagePullBackOff K8s ne peut pas télécharger l'image Docker
ContainerCreating Le container est en cours de démarrage
Terminating     Le pod est en cours de suppression
Unknown         K8s a perdu le contact avec le noeud
```

**Que faire en cas de problème ?**

```bash
# Pod en CrashLoopBackOff
kubectl logs mon-pod --previous     # Voir les logs de la tentative précédente
kubectl describe pod mon-pod        # Voir l'historique des événements

# Pod en Pending
kubectl describe pod mon-pod        # Chercher "Events:" en bas
# Causes fréquentes :
#  - Insufficient memory (pas assez de RAM disponible)
#  - No nodes available (tous les serveurs sont pleins)
#  - Unbound PVC (le disque demandé n'existe pas)

# Pod en ImagePullBackOff
kubectl describe pod mon-pod
# Causes :
#  - Image Docker qui n'existe pas
#  - Mauvais nom ou tag de l'image
#  - Docker Hub est inaccessible
#  - Credentials Docker Hub manquants pour image privée
```

---

## 13. Déployer une vraie application

### Architecture de l'exemple

```
┌────────────────────────────────────────────────────┐
│                  Namespace: ma-app                 │
│                                                    │
│  Internet                                          │
│     │                                              │
│     ▼                                              │
│  ┌──────────────────────┐                          │
│  │ Service frontend     │ NodePort:30000           │
│  │ (NodePort)           │                          │
│  └──────────┬───────────┘                          │
│             │ load balance                         │
│     ┌───────┴───────┐                              │
│     ▼               ▼                              │
│  Pod frontend    Pod frontend                      │
│     │               │                              │
│     └───────┬───────┘                              │
│             │                                      │
│  ┌──────────▼───────────┐                          │
│  │ Service backend       │ ClusterIP               │
│  │ (ClusterIP)          │                          │
│  └──────────┬───────────┘                          │
│             │                                      │
│     ┌───────┴───────┐                              │
│     ▼               ▼                              │
│  Pod backend     Pod backend                       │
│     │               │                              │
│     └───────┬───────┘                              │
│             │                                      │
│  ┌──────────▼───────────┐                          │
│  │ Service postgres      │ ClusterIP               │
│  │ (ClusterIP)          │                          │
│  └──────────┬───────────┘                          │
│             │                                      │
│          Pod postgres                              │
│             │                                      │
│          [PVC 2Gi]                                 │
└────────────────────────────────────────────────────┘
```

### Fichiers complets avec explications

**`00-namespace.yaml` :**
```yaml
# Créer le namespace en premier
apiVersion: v1
kind: Namespace
metadata:
  name: ma-app
  labels:
    project: devops-demo
```

**`01-secret.yaml` :**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-secret
  namespace: ma-app
type: Opaque
data:
  # echo -n "postgres" | base64 → cG9zdGdyZXM=
  DB_USER: cG9zdGdyZXM=
  # echo -n "monmotdepasse" | base64 → bW9ubW90ZGVwYXNzZQ==
  DB_PASSWORD: bW9ubW90ZGVwYXNzZQ==
  # echo -n "appdb" | base64 → YXBwZGI=
  DB_NAME: YXBwZGI=
```

**`02-postgres.yaml` :**
```yaml
# PVC — Demande de stockage persistant
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
  namespace: ma-app
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 2Gi

---
# Deployment PostgreSQL
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
  namespace: ma-app
spec:
  replicas: 1            # Toujours 1 pour une DB (sinon problème de données)
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:15-alpine
          env:
            - name: POSTGRES_DB
              valueFrom:
                secretKeyRef:
                  name: db-secret
                  key: DB_NAME
            - name: POSTGRES_USER
              valueFrom:
                secretKeyRef:
                  name: db-secret
                  key: DB_USER
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: db-secret
                  key: DB_PASSWORD
          ports:
            - containerPort: 5432
          volumeMounts:
            - name: postgres-data
              mountPath: /var/lib/postgresql/data
      volumes:
        - name: postgres-data
          persistentVolumeClaim:
            claimName: postgres-pvc

---
# Service PostgreSQL — accessible via "postgres-service:5432" dans le cluster
apiVersion: v1
kind: Service
metadata:
  name: postgres-service
  namespace: ma-app
spec:
  type: ClusterIP
  selector:
    app: postgres
  ports:
    - port: 5432
      targetPort: 5432
```

**`03-backend.yaml` :**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: ma-app
spec:
  replicas: 2            # 2 copies pour la redondance
  selector:
    matchLabels:
      app: backend
  strategy:
    type: RollingUpdate   # Mise à jour progressive (zéro downtime)
    rollingUpdate:
      maxUnavailable: 1   # Jamais plus d'1 pod indispo en même temps
      maxSurge: 1         # Peut créer 1 pod supplémentaire pendant la MAJ
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
        - name: backend
          image: VOTRE_DOCKERHUB/devops-backend:v1.0
          ports:
            - containerPort: 3000
          env:
            - name: DB_HOST
              value: "postgres-service"   # Nom DNS du Service postgres
            - name: DB_PORT
              value: "5432"
            - name: DB_NAME
              valueFrom:
                secretKeyRef:
                  name: db-secret
                  key: DB_NAME
            - name: DB_USER
              valueFrom:
                secretKeyRef:
                  name: db-secret
                  key: DB_USER
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: db-secret
                  key: DB_PASSWORD
          livenessProbe:
            httpGet:
              path: /health
              port: 3000
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /health
              port: 3000
            initialDelaySeconds: 10
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
  namespace: ma-app
spec:
  type: ClusterIP         # Interne seulement (le frontend l'appelle en interne)
  selector:
    app: backend
  ports:
    - port: 3000
      targetPort: 3000
```

**`04-frontend.yaml` :**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: ma-app
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
          image: VOTRE_DOCKERHUB/devops-frontend:v1.0
          ports:
            - containerPort: 80
          livenessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 10
            periodSeconds: 10
          resources:
            requests:
              memory: "64Mi"
              cpu: "50m"
            limits:
              memory: "128Mi"
              cpu: "200m"

---
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
  namespace: ma-app
spec:
  type: NodePort           # Accessible depuis l'extérieur
  selector:
    app: frontend
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30000      # Accès : http://IP_SERVEUR:30000
```

**Déployer tout :**

```bash
# Appliquer dans l'ordre (les dépendances d'abord)
kubectl apply -f 00-namespace.yaml
kubectl apply -f 01-secret.yaml
kubectl apply -f 02-postgres.yaml
kubectl apply -f 03-backend.yaml
kubectl apply -f 04-frontend.yaml

# Ou tout d'un coup (K8s gère l'ordre)
kubectl apply -f ./k8s/

# Vérifier que tout tourne
kubectl get all -n ma-app

# Voir les pods avec plus de détails
kubectl get pods -n ma-app -o wide

# Surveiller le déploiement en temps réel
kubectl get pods -n ma-app -w
```

### Suivre une Rolling Update

```bash
# Mettre à jour l'image du backend vers v2.0
kubectl set image deployment/backend backend=VOTRE_DOCKERHUB/devops-backend:v2.0 -n ma-app

# Observer la mise à jour en temps réel
kubectl rollout status deployment/backend -n ma-app
# Waiting for deployment "backend" rollout to finish: 1 out of 2 new replicas have been updated...
# Waiting for deployment "backend" rollout to finish: 1 old replicas are pending termination...
# deployment "backend" successfully rolled out

# Si quelque chose ne va pas, rollback !
kubectl rollout undo deployment/backend -n ma-app
```

---

## 14. Concepts avancés

### 14.1 HorizontalPodAutoscaler (HPA)

```yaml
# Augmenter automatiquement le nombre de pods selon la charge CPU
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: backend-hpa
  namespace: ma-app
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: backend
  minReplicas: 2           # Minimum 2 pods
  maxReplicas: 10          # Maximum 10 pods
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70    # Si CPU > 70% → ajouter des pods
```

```
Scénario :
  Trafic normal  → 2 pods (minimum)
  Trafic x5      → HPA détecte CPU > 70% → ajoute des pods → 5 pods
  Trafic revient → HPA réduit les pods → 2 pods
```

### 14.2 ResourceQuota — Limiter un namespace

```yaml
# Empêcher un namespace de consommer trop de ressources du cluster
apiVersion: v1
kind: ResourceQuota
metadata:
  name: ma-app-quota
  namespace: ma-app
spec:
  hard:
    pods: "10"                   # Max 10 pods
    requests.cpu: "2"            # Max 2 CPU total
    requests.memory: 2Gi         # Max 2 Go RAM total
    limits.cpu: "4"
    limits.memory: 4Gi
    persistentvolumeclaims: "3"  # Max 3 volumes
```

### 14.3 DaemonSet — Un pod sur chaque nœud

```yaml
# Un DaemonSet s'assure qu'UN pod tourne sur CHAQUE nœud
# Utilisé pour : logging, monitoring, réseau

apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-exporter
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: node-exporter
  template:
    metadata:
      labels:
        app: node-exporter
    spec:
      containers:
        - name: node-exporter
          image: prom/node-exporter:latest
          # Collecte des métriques sur chaque serveur
```

### 14.4 Job et CronJob — Tâches ponctuelles

```yaml
# Job — Une tâche qui s'exécute une fois et se termine
apiVersion: batch/v1
kind: Job
metadata:
  name: migration-db
spec:
  template:
    spec:
      containers:
        - name: migrate
          image: mon-app:v1
          command: ["node", "migrate.js"]
      restartPolicy: OnFailure    # Réessayer si ça échoue

---
# CronJob — Une tâche planifiée (comme cron Linux)
apiVersion: batch/v1
kind: CronJob
metadata:
  name: backup-db
spec:
  schedule: "0 2 * * *"          # Toutes les nuits à 2h du matin
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: backup
              image: postgres:15
              command: ["pg_dump", "-h", "postgres-service", "appdb"]
          restartPolicy: OnFailure
```

---

## 15. Terraform + Kubernetes ensemble

### Comment ils travaillent ensemble ?

```
TERRAFORM                        KUBERNETES
─────────────────────────────────────────────────────────
Crée l'infrastructure AWS        Gère les containers
  - VPC, Subnets                 dessus
  - EC2 (les serveurs K8s)
  - Security Groups
  - Elastic IPs

Résultat : Des serveurs vides    Résultat : App déployée
           prêts pour K8s        sur ces serveurs
```

### Workflow complet

```bash
# ÉTAPE 1 : Terraform crée l'infrastructure AWS
cd terraform/
terraform init
terraform apply
# → 2 instances EC2, VPC, Security Groups créés

# ÉTAPE 2 : Ansible configure Kubernetes sur ces serveurs
cd ../ansible/
ansible-playbook playbook.yml
# → kubeadm, kubelet, kubectl installés
# → Cluster K8s initialisé

# ÉTAPE 3 : kubectl déploie l'application
cd ../k8s/
kubectl apply -f .
# → Pods, Services, Volumes créés
# → Application disponible !
```

### Terraform peut aussi gérer des ressources K8s !

```hcl
# Avec le provider Kubernetes dans Terraform
provider "kubernetes" {
  host = aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(
    aws_eks_cluster.main.certificate_authority[0].data
  )
}

# Créer un Namespace via Terraform
resource "kubernetes_namespace" "app" {
  metadata {
    name = "ma-app"
    labels = {
      environment = "prod"
    }
  }
}

# Créer un Deployment via Terraform
resource "kubernetes_deployment" "backend" {
  metadata {
    name      = "backend"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  spec {
    replicas = 3
    selector {
      match_labels = {
        app = "backend"
      }
    }
    template {
      metadata {
        labels = {
          app = "backend"
        }
      }
      spec {
        container {
          name  = "backend"
          image = "mon-image:v1"
          port {
            container_port = 3000
          }
        }
      }
    }
  }
}
```

---

## 📊 Récapitulatif visuel — Ce qu'on a appris

### Terraform en un coup d'œil

```
Fichiers .tf (HCL)
│
├── provider.tf    → "Je veux travailler avec AWS"
├── variables.tf   → "Voici mes paramètres configurables"
├── main.tf        → "Voici les ressources à créer"
└── outputs.tf     → "Voici ce que je veux voir à la fin"

Commandes :
  terraform init    → Télécharger les plugins
  terraform plan    → Voir ce qui va changer
  terraform apply   → Créer/modifier l'infra
  terraform destroy → Tout supprimer
```

### Kubernetes en un coup d'œil

```
Objets K8s essentiels :

Namespace    → Isoler les ressources (comme un dossier)
Pod          → 1+ containers qui tournent ensemble
Deployment   → Gérer N replicas d'un Pod avec auto-healing
Service      → Accéder aux pods via IP/DNS stable
ConfigMap    → Stocker la configuration (non-sensible)
Secret       → Stocker les mots de passe (encodé)
PVC          → Demander du stockage persistant
Ingress      → Routage HTTP basé sur URL/domaine

Commandes :
  kubectl apply -f fichier.yaml    → Déployer
  kubectl get pods                 → Voir les pods
  kubectl logs pod-name            → Voir les logs
  kubectl describe pod pod-name    → Déboguer
  kubectl exec -it pod -- bash     → Entrer dans un container
```

### La chaîne DevOps complète

```
CODE                INFRA               CONFIG            DEPLOY
─────               ─────               ──────            ──────

Écrire              Terraform           Ansible           Kubernetes
l'application  →    crée le VPC,   →    configure    →    orchestre
(Node.js,           les EC2, les        les serveurs      les containers
 React,             Security Groups     (Docker,          (Pod, Deployment,
 Dockerfile)        sur AWS             K8s tools)        Service)
```

---

## 🎓 Exercices pratiques pour pratiquer

### Exercice 1 — Terraform (15 minutes)

```bash
# Créer un bucket S3 avec Terraform
mkdir exercice-terraform && cd exercice-terraform

cat > main.tf << 'EOF'
provider "aws" {
  region = "ca-central-1"
}

resource "aws_s3_bucket" "mon_bucket" {
  bucket = "mon-bucket-devops-VOTRE_NOM-123"
}

output "bucket_name" {
  value = aws_s3_bucket.mon_bucket.id
}
EOF

terraform init
terraform plan
terraform apply
terraform destroy   # Ne pas oublier !
```

### Exercice 2 — Kubernetes (20 minutes)

```bash
# Sur ton cluster K8s, déployer Nginx et l'exposer

cat > nginx-test.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-test
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx-test
  template:
    metadata:
      labels:
        app: nginx-test
    spec:
      containers:
        - name: nginx
          image: nginx:alpine
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  type: NodePort
  selector:
    app: nginx-test
  ports:
    - port: 80
      targetPort: 80
      nodePort: 31000
EOF

kubectl apply -f nginx-test.yaml
kubectl get pods
kubectl get services
# Accéder : http://IP_SERVEUR:31000

# Tester le scaling
kubectl scale deployment nginx-test --replicas=5
kubectl get pods

# Nettoyer
kubectl delete -f nginx-test.yaml
```

### Exercice 3 — Comprendre les Services (10 minutes)

```bash
# Entrer dans un pod et tester la résolution DNS interne
kubectl exec -it POD_BACKEND -- /bin/sh

# Dans le container :
curl http://backend-service:3000/health
curl http://postgres-service:5432
nslookup postgres-service
```

---

## 📚 Ressources pour aller plus loin

```
Terraform :
  📖 Documentation officielle : registry.terraform.io
  🎓 Tutoriels HashiCorp     : developer.hashicorp.com/terraform/tutorials
  🔧 Exemples AWS            : github.com/hashicorp/terraform-provider-aws

Kubernetes :
  📖 Documentation officielle : kubernetes.io/docs
  🎮 Playground interactif   : killercoda.com (gratuit)
  🎮 Playground interactif   : labs.play-with-k8s.com (gratuit)
  📺 Tutoriels vidéo         : youtube.com/@TechWorldwithNana

Livres recommandés :
  "Terraform: Up & Running" — Yevgeniy Brikman
  "Kubernetes: Up and Running" — Kelsey Hightower
```

---

*Cours rédigé pour Collège Boréal — Computer Systems Technician — Projet Final DevOps AWS*  
*Niveau : Débutant → Intermédiaire | Compatible avec le guide de déploiement AWS*