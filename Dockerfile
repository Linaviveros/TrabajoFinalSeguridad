# --- Etapa de instalación ---
FROM node:20-bookworm AS installer
WORKDIR /juice-shop

# Copiamos el código primero (si quieres optimizar cache, puedes copiar solo package*.json y luego el resto)
COPY . /juice-shop

# Herramientas necesarias para scripts del proyecto
RUN npm i -g typescript ts-node

# Instala dependencias de producción (sin dev), permitiendo scripts nativos
RUN npm install --omit=dev --unsafe-perm
RUN npm dedupe --omit=dev

# Limpiezas de frontend (igual que tu versión)
RUN rm -rf frontend/node_modules
RUN rm -rf frontend/.angular
RUN rm -rf frontend/src/assets

# Preparación de carpetas y permisos
RUN mkdir -p logs
RUN chown -R 65532 logs
RUN chgrp -R 0 ftp/ frontend/dist/ logs/ data/ i18n/
RUN chmod -R g=u ftp/ frontend/dist/ logs/ data/ i18n/

# NO borrar el dataset del chatbot (requerido para el reto "Chatbot matón")
# RUN rm data/chatbot/botDefaultTrainingData.json || true

# Otras limpiezas que ya tenías
RUN rm ftp/legal.md || true
RUN rm i18n/*.json || true

# SBOM (como lo tenías)
ARG CYCLONEDX_NPM_VERSION=latest
RUN npm install -g @cyclonedx/cyclonedx-npm@$CYCLONEDX_NPM_VERSION
RUN npm run sbom

# --- Etapa para reconstruir libxmljs (workaround) ---
FROM node:20-bookworm AS libxmljs-builder
WORKDIR /juice-shop

# Paquetes de compilación necesarios y limpieza de listas
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential python3 \
 && rm -rf /var/lib/apt/lists/*

# Traemos node_modules ya instalados
COPY --from=installer /juice-shop/node_modules ./node_modules

# Forzamos rebuild limpio de libxmljs
RUN rm -rf node_modules/libxmljs/build && \
    cd node_modules/libxmljs && \
    npm run build

# --- Etapa final (runtime) ---
FROM gcr.io/distroless/nodejs20-debian12
ARG BUILD_DATE
ARG VCS_REF

LABEL maintainer="Bjoern Kimminich <bjoern.kimminich@owasp.org>" \
      org.opencontainers.image.title="OWASP Juice Shop" \
      org.opencontainers.image.description="Probably the most modern and sophisticated insecure web application" \
      org.opencontainers.image.authors="Bjoern Kimminich <bjoern.kimminich@owasp.org>" \
      org.opencontainers.image.vendor="Open Worldwide Application Security Project" \
      org.opencontainers.image.documentation="https://help.owasp-juice.shop" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="17.3.0" \
      org.opencontainers.image.url="https://owasp-juice.shop" \
      org.opencontainers.image.source="https://github.com/juice-shop/juice-shop" \
      org.opencontainers.image.revision=$VCS_REF \
      org.opencontainers.image.created=$BUILD_DATE

WORKDIR /juice-shop

# Copiamos todo lo construido en la etapa installer
COPY --from=installer --chown=65532:0 /juice-shop .

# Sustituimos libxmljs por el rebuild de la etapa builder
COPY --chown=65532:0 --from=libxmljs-builder /juice-shop/node_modules/libxmljs ./node_modules/libxmljs

# Usuario no root (65532 = nonroot en distroless)
USER 65532

# Puerto por defecto de Juice Shop
EXPOSE 3000

# Arranque de la app
CMD ["/juice-shop/build/app.js"]
