# ════════════════════════════════════════════════════════════════
# DOCKERFILE — NetPulse Backend (Node.js 18 Alpine)
# ════════════════════════════════════════════════════════════════

FROM node:18-alpine

LABEL maintainer="devops-student"
LABEL version="2.0"
LABEL description="NetPulse Backend API — Métriques réseau Kubernetes"

# Répertoire de travail
WORKDIR /app

# Copier les dépendances en premier (optimisation cache Docker)
COPY package.json package-lock.json* ./

# Installer uniquement les dépendances de production
RUN npm install --only=production

# Copier le code source
COPY . .

# Utilisateur non-root (sécurité)
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

# Port exposé
EXPOSE 3000

# Variables d'environnement par défaut
ENV NODE_ENV=production \
    PORT=3000

# Démarrage
CMD ["node", "server.js"]