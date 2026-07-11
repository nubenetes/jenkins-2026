# =============================================================================
# jenkins-2026 Backstage image - HOST-BUILD pattern (backstage.io/docs/deployment/docker)
# =============================================================================
# Built by .github/workflows/Day2.publish.06-backstage.yml, which runs the
# expensive steps on the runner FIRST:
#   yarn install && yarn tsc && yarn build:backend
# and then:  docker build -f packages/backend/Dockerfile .   (context = backstage/)
# The build:backend step produces packages/backend/dist/skeleton.tar.gz (the
# monorepo package.json skeleton) + bundle.tar.gz (the compiled backend + the
# frontend bundle via the app link: dependency).
#
# Base: node:24-trixie-slim - the current upstream recommendation (Node 24 on
# Debian 13, verified 2026-07-11). NO build-essential/g++/libsqlite3: this app
# has no scaffolder (no isolated-vm) and no sqlite (pg is pure JS), so nothing
# compiles natively at install time - keep the image slim.
FROM node:24-trixie-slim

ENV NODE_ENV=production

# TechDocs local builder: mkdocs + the techdocs-core plugin, in a venv (Debian
# trixie is PEP 668 "externally managed" - system pip installs are refused).
# Pinned per docs/602 (mkdocs-techdocs-core 1.7.0 = latest, pypi 2026-06-10).
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 python3-venv \
    && rm -rf /var/lib/apt/lists/* \
    && python3 -m venv /opt/mkdocs \
    && /opt/mkdocs/bin/pip install --no-cache-dir mkdocs-techdocs-core==1.7.0
ENV PATH="/opt/mkdocs/bin:${PATH}"

# yarn 4.8.1 via corepack (reads packageManager from package.json).
RUN corepack enable

USER node
WORKDIR /app

# 1) the monorepo skeleton (all package.json files) + the lockfile the CI's own
# `yarn install` generated on the runner - enough for a production-only install.
COPY --chown=node:node .yarnrc.yml package.json yarn.lock backstage.json ./
COPY --chown=node:node packages/backend/dist/skeleton.tar.gz ./
RUN tar xzf skeleton.tar.gz && rm skeleton.tar.gz

RUN yarn workspaces focus --all --production \
    && rm -rf "$(yarn cache clean --all 2>/dev/null; echo /home/node/.yarn/berry/cache)" || true

# 2) the compiled backend + frontend bundle, then the runtime config.
COPY --chown=node:node packages/backend/dist/bundle.tar.gz ./
RUN tar xzf bundle.tar.gz && rm bundle.tar.gz
COPY --chown=node:node app-config.yaml ./

# The chart overrides args to add extra --config files (e.g. the backend-TLS
# overlay ConfigMap); this default matches helm/backstage/values.yaml.
CMD ["node", "packages/backend", "--config", "app-config.yaml"]
