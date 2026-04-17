#  Surveillance Réseau Kubernetes
### Projet DevOps — Collège Boréal | AWS + Terraform + Ansible + K8s + Cilium + Hubble + Prometheus + Grafana

---

## Vue d'ensemble

**NetPulse** est un dashboard de surveillance réseau déployé sur Kubernetes. Il visualise en temps réel les flux réseau entre pods grâce à **Cilium/Hubble**, expose des métriques à **Prometheus**, et les affiche dans **Grafana**.

```
[Terraform] → EC2 (master + worker)
[Ansible]   → K8s + Cilium (CNI eBPF) + Hubble + Prometheus + Grafana
[K8s]       → NetPulse (frontend + backend + postgres) + NetworkPolicies
```

---

## Stack technique

| Composant | Rôle |
|-----------|------|
| **Terraform** | Infrastructure AWS (VPC, EC2, Security Groups, EIP) |
| **Ansible** | Configuration K8s, installation Cilium via Helm |
| **Cilium** | CNI eBPF — remplace Flannel + kube-proxy, applique les NetworkPolicies L7 |
| **Hubble** | Interface de visualisation des flux réseau (UI + Relay) |
| **Prometheus** | Scraping métriques Cilium (`hubble_*`) + application (`netpulse_*`) |
| **Grafana** | Dashboards provisionnés automatiquement |
| **NetPulse** | App (Node.js + React + PostgreSQL) exposant ses propres métriques |

---

## Structure du projet

```
netpulse/
├── deploy.sh                     # Script de déploiement complet
├── terraform/
│   ├── main.tf                   # EC2 master + worker
│   ├── vpc.tf                    # VPC, subnets, IGW
│   ├── security_groups.tf        # Firewall (ports Cilium + monitoring)
│   ├── variables.tf
│   └── outputs.tf
├── ansible/
│   ├── inventory.ini
│   └── playbook.yml              # 5 plays : base → master → workers → monitoring → app
├── app/
│   ├── docker-compose.yml        # Test local
│   ├── backend/
│   │   ├── server.js             # API REST + endpoint /metrics (Prometheus)
│   │   ├── package.json
│   │   └── Dockerfile
│   └── frontend/
│       ├── index.html            # Dashboard (canvas réseau + tableau flux)
│       ├── nginx.conf
│       └── Dockerfile
└── k8s/
    ├── 01-namespace.yaml
    ├── 02-postgres.yaml
    ├── 03-backend.yaml           # Deployment + ServiceMonitor Prometheus
    ├── 04-frontend.yaml          # Deployment + ConfigMap Nginx
    ├── 05-cilium-policies.yaml   # CiliumNetworkPolicies (ALLOW/DROP)
    └── 06-grafana-dashboard.yaml # Dashboard JSON + datasource provisionnés
```

---

## Déploiement

### Prérequis
```bash
# Outils requis sur votre machine locale
terraform --version   # >= 1.0
ansible --version     # >= 2.14
docker --version
aws configure         # credentials AWS configurés
```

### Déploiement complet
```bash
./deploy.sh all
# Enchaîne : build → infra → config → app
```

### Étape par étape
```bash
./deploy.sh build    # 1. Build + push images Docker Hub
./deploy.sh infra    # 2. Terraform : créer EC2, VPC, EIP
./deploy.sh config   # 3. Ansible : K8s + Cilium + Prometheus + Grafana
./deploy.sh app      # 4. kubectl : manifests NetPulse + NetworkPolicies
./deploy.sh status   # Voir l'état du cluster
./deploy.sh clean    # Détruire l'infrastructure
```

### Test local (sans AWS)
```bash
cd app/
docker compose up -d
# → http://localhost (dashboard NetPulse)
# → http://localhost:3000/api/flows (API)
# → http://localhost:3000/metrics (Prometheus format)
```

---

## URLs d'accès (après déploiement)

| Service | URL | Credentials |
|---------|-----|-------------|
| **NetPulse Dashboard** | `http://MASTER_IP:30000` | — |
| **Grafana** | `http://MASTER_IP:31000` | admin / netpulse2025 |
| **Prometheus** | `http://MASTER_IP:31001` | — |
| **Hubble UI** | `kubectl port-forward -n kube-system svc/hubble-ui 12000:80` | — |
| **Backend API** | `http://MASTER_IP:30001/api/flows` | — |

---

## Ce que Cilium apporte vs Flannel

| Flannel (ancien) | Cilium (nouveau) |
|-----------------|-----------------|
| CNI basique (L3) | CNI eBPF (L3/L4/L7) |
| Pas de NetworkPolicy L7 | NetworkPolicy HTTP (méthode, path) |
| kube-proxy (iptables) | kube-proxy replacement (eBPF) |
| Pas de visibilité réseau | Hubble : flux réseau en temps réel |
| Pas de métriques réseau | `hubble_*` metrics dans Prometheus |

### Métriques Cilium dans Prometheus
```promql
# Flux bloqués par politique réseau
sum(increase(hubble_drop_total[1h]))

# Flux par verdict (ALLOW/DROP)
rate(hubble_flows_processed_total{verdict="DROPPED"}[1m])

# Latence DNS
histogram_quantile(0.99, hubble_dns_response_rate_bucket)
```

---

## NetworkPolicies expliquées

Le fichier `k8s/05-cilium-policies.yaml` définit :

1. **`default-deny-all`** — bloque tout le trafic dans le namespace `netpulse`
2. **`allow-frontend-to-backend`** — autorise uniquement `GET/POST /api/*` et `GET /health`
3. **`allow-backend-to-postgres`** — autorise uniquement TCP 5432
4. **`allow-prometheus-scrape-backend`** — autorise `GET /metrics`
5. **`allow-dns-egress`** — autorise la résolution DNS (kube-dns)

Le trafic **frontend → postgres** est intentionnellement absent → il apparaîtra en **DROP** dans Hubble, et sera compté dans `hubble_drop_total{reason="POLICY_DENIED"}` dans Prometheus.

---

## Grafana — Dashboard provisionné

Le dashboard `k8s/06-grafana-dashboard.yaml` est chargé automatiquement au démarrage de Grafana. Il contient :
- Flux ALLOW vs DROP (Hubble)
- Drops par raison (POLICY_DENIED, etc.)
- Métriques nœuds (CPU, RAM, réseau RX/TX)
- Alertes actives (NetPulse app)
- Pods K8s running

---

## Pour la démo

```bash
# 1. Voir les flux réseau en temps réel (CLI Hubble)
hubble observe --namespace netpulse --follow

# 2. Voir uniquement les DROPs
hubble observe --namespace netpulse --verdict DROPPED --follow

# 3. Statut Cilium
cilium status

# 4. Vérifier les policies
kubectl get ciliumnetworkpolicies -n netpulse

# 5. Tester un DROP volontaire (depuis un pod)
kubectl run test --image=busybox -n netpulse --rm -it -- \
  wget -T3 postgres-service:5432  # → bloqué par Cilium
```
