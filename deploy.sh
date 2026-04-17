#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════
# deploy.sh — NetPulse : Déploiement complet en une commande
# Usage : ./deploy.sh [build|infra|config|app|all|status|clean]
# ════════════════════════════════════════════════════════════════

set -euo pipefail

# ─── Couleurs ──────────────────────────────────────────────────
TEAL='\033[0;36m'; GREEN='\033[0;32m'; RED='\033[0;31m'
AMBER='\033[0;33m'; BOLD='\033[1m'; RESET='\033[0m'

log()  { echo -e "${TEAL}${BOLD}[NetPulse]${RESET} $*"; }
ok()   { echo -e "${GREEN}  ✔ $*${RESET}"; }
warn() { echo -e "${AMBER}  ⚠ $*${RESET}"; }
err()  { echo -e "${RED}  ✘ $*${RESET}"; exit 1; }

DOCKER_USER="${DOCKER_USER:-arsprod01}"

# ════════════════════════════════════════════════════════════════
# ÉTAPE 1 — Build et push des images Docker
# ════════════════════════════════════════════════════════════════
step_build() {
  log "Build des images Docker NetPulse..."

  docker build -t "${DOCKER_USER}/netpulse-backend:v2.0"  ./app/backend/
  docker build -t "${DOCKER_USER}/netpulse-frontend:v2.0" ./app/frontend/
  ok "Images buildées"

  log "Push vers Docker Hub..."
  docker push "${DOCKER_USER}/netpulse-backend:v2.0"
  docker push "${DOCKER_USER}/netpulse-frontend:v2.0"
  ok "Images publiées sur Docker Hub"
}

# ════════════════════════════════════════════════════════════════
# ÉTAPE 2 — Provisionnement infrastructure AWS (Terraform)
# ════════════════════════════════════════════════════════════════
step_infra() {
  log "Provisionnement AWS avec Terraform..."
  cd terraform/

  terraform init
  terraform validate
  terraform plan -out=netpulse.tfplan
  terraform apply netpulse.tfplan

  # Récupérer les IPs et mettre à jour l'inventaire Ansible
  MASTER_IP=$(terraform output -raw master_public_ip)
  WORKER_IP=$(terraform output -raw worker_public_ip)

  cd ..
  cat > ansible/inventory.ini <<EOF
[master]
k8s-master ansible_host=${MASTER_IP} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/devops-aws-key

[workers]
k8s-worker ansible_host=${WORKER_IP} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/devops-aws-key

[k8s_nodes:children]
master
workers

[k8s_nodes:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
ansible_python_interpreter=/usr/bin/python3
EOF

  ok "Infrastructure créée — Master: ${MASTER_IP} | Worker: ${WORKER_IP}"
  echo ""
  echo "  URLs après déploiement :"
  echo "  🌐 NetPulse  : http://${MASTER_IP}:30000"
  echo "  📊 Grafana   : http://${MASTER_IP}:31000"
  echo "  🔥 Prometheus: http://${MASTER_IP}:31001"
}

# ════════════════════════════════════════════════════════════════
# ÉTAPE 3 — Configuration K8s + Cilium + Monitoring (Ansible)
# ════════════════════════════════════════════════════════════════
step_config() {
  log "Configuration du cluster avec Ansible..."

  # Attendre que les instances EC2 soient accessibles via SSH
  log "Attente disponibilité SSH (60s)..."
  sleep 60

  ansible-playbook \
    -i ansible/inventory.ini \
    ansible/playbook.yml \
    --timeout=600 \
    -v

  ok "Cluster configuré — Cilium + Hubble + Prometheus + Grafana installés"
}

# ════════════════════════════════════════════════════════════════
# ÉTAPE 4 — Déploiement des manifests K8s (app + policies)
# ════════════════════════════════════════════════════════════════
step_app() {
  log "Déploiement des manifests Kubernetes..."

  MASTER_IP=$(cd terraform && terraform output -raw master_public_ip 2>/dev/null || \
    grep ansible_host ansible/inventory.ini | head -1 | awk '{print $2}' | cut -d= -f2)

  # Appliquer tous les manifests dans l'ordre numéroté
  for manifest in k8s/*.yaml; do
    log "Applying $(basename ${manifest})..."
    ssh -i ~/.ssh/devops-aws-key -o StrictHostKeyChecking=no \
      ubuntu@${MASTER_IP} \
      "kubectl apply -f -" < "${manifest}"
  done

  ok "Manifests appliqués"

  log "Attente que les pods soient Running..."
  ssh -i ~/.ssh/devops-aws-key -o StrictHostKeyChecking=no \
    ubuntu@${MASTER_IP} \
    "kubectl wait --for=condition=ready pod --all -n netpulse --timeout=300s || true"

  step_status
}

# ════════════════════════════════════════════════════════════════
# Statut du cluster
# ════════════════════════════════════════════════════════════════
step_status() {
  MASTER_IP=$(cd terraform && terraform output -raw master_public_ip 2>/dev/null || \
    grep ansible_host ansible/inventory.ini | head -1 | awk '{print $2}' | cut -d= -f2)

  echo ""
  log "═══════════════════════════════════════"
  log "        STATUT NETPULSE CLUSTER"
  log "═══════════════════════════════════════"

  ssh -i ~/.ssh/devops-aws-key -o StrictHostKeyChecking=no ubuntu@${MASTER_IP} bash <<'REMOTE'
    echo ""
    echo "── NODES ──"
    kubectl get nodes -o wide

    echo ""
    echo "── PODS netpulse ──"
    kubectl get pods -n netpulse -o wide

    echo ""
    echo "── PODS monitoring ──"
    kubectl get pods -n monitoring --no-headers | head -10

    echo ""
    echo "── SERVICES ──"
    kubectl get svc -n netpulse
    kubectl get svc -n monitoring | grep -E "grafana|prometheus"

    echo ""
    echo "── CILIUM ──"
    cilium status --brief 2>/dev/null || echo "(cilium CLI non disponible ici)"

    echo ""
    echo "── NETWORK POLICIES ──"
    kubectl get ciliumnetworkpolicies -n netpulse
REMOTE

  echo ""
  ok "Master IP : ${MASTER_IP}"
  echo -e "  🌐 ${BOLD}NetPulse${RESET}  → http://${MASTER_IP}:30000"
  echo -e "  📊 ${BOLD}Grafana${RESET}   → http://${MASTER_IP}:31000   (admin / netpulse2025)"
  echo -e "  🔥 ${BOLD}Prometheus${RESET}→ http://${MASTER_IP}:31001"
  echo -e "  🐝 ${BOLD}Hubble UI${RESET} → kubectl port-forward -n kube-system svc/hubble-ui 12000:80"
}

# ════════════════════════════════════════════════════════════════
# Nettoyage complet (destroy Terraform)
# ════════════════════════════════════════════════════════════════
step_clean() {
  warn "Destruction de toute l'infrastructure AWS..."
  read -p "Confirmer ? (yes/no) : " confirm
  [[ "${confirm}" == "yes" ]] || { log "Annulé."; exit 0; }
  cd terraform && terraform destroy -auto-approve
  ok "Infrastructure détruite"
}

# ════════════════════════════════════════════════════════════════
# Point d'entrée
# ════════════════════════════════════════════════════════════════
CMD="${1:-all}"

echo ""
echo -e "${TEAL}${BOLD}"
echo "  ███╗   ██╗███████╗████████╗██████╗ ██╗   ██╗██╗     ███████╗███████╗"
echo "  ████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██║   ██║██║     ██╔════╝██╔════╝"
echo "  ██╔██╗ ██║█████╗     ██║   ██████╔╝██║   ██║██║     ███████╗█████╗  "
echo "  ██║╚██╗██║██╔══╝     ██║   ██╔═══╝ ██║   ██║██║     ╚════██║██╔══╝  "
echo "  ██║ ╚████║███████╗   ██║   ██║     ╚██████╔╝███████╗███████║███████╗"
echo "  ╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝      ╚═════╝ ╚══════╝╚══════╝╚══════╝"
echo -e "${RESET}"
echo -e "  Stack : ${TEAL}Terraform${RESET} → ${TEAL}Ansible${RESET} → ${TEAL}K8s${RESET} + ${TEAL}Cilium${RESET} + ${TEAL}Hubble${RESET} + ${TEAL}Prometheus${RESET} + ${TEAL}Grafana${RESET}"
echo ""

case "${CMD}" in
  build)  step_build ;;
  infra)  step_infra ;;
  config) step_config ;;
  app)    step_app ;;
  status) step_status ;;
  clean)  step_clean ;;
  all)
    step_build
    step_infra
    step_config
    step_app
    ;;
  *)
    echo "Usage : ./deploy.sh [build|infra|config|app|all|status|clean]"
    echo ""
    echo "  build  — Build + push images Docker"
    echo "  infra  — Terraform : créer EC2, VPC, Security Groups"
    echo "  config — Ansible : installer K8s, Cilium, Hubble, Prometheus, Grafana"
    echo "  app    — kubectl : déployer NetPulse + NetworkPolicies"
    echo "  all    — Tout enchaîner (build → infra → config → app)"
    echo "  status — Afficher l'état du cluster"
    echo "  clean  — Détruire toute l'infrastructure"
    ;;
esac