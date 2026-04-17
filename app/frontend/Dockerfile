# ════════════════════════════════════════════════════════════════
# DOCKERFILE — NetPulse Frontend (Nginx Alpine)
# ════════════════════════════════════════════════════════════════

FROM nginx:alpine

LABEL maintainer="devops-student"
LABEL version="2.0"
LABEL description="NetPulse Frontend — Dashboard de surveillance réseau K8s"

# Config Nginx personnalisée
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Dashboard HTML
COPY index.html /usr/share/nginx/html/

EXPOSE 80