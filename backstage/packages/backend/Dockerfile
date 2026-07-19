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
# Debian 13, verified 2026-07-11). Still NO build-essential/g++/libsqlite3, even
# with the scaffolder now on board: isolated-vm 6.x ships prebuilds/linux-x64, so
# node-gyp-build resolves a binary and nothing compiles at install time (verified
# in this exact base image). pg is pure JS. Keep the image slim.
FROM node:24-trixie-slim

ENV NODE_ENV=production

# REQUIRED by the scaffolder's isolated-vm on Node >= 20 — without it every template
# RUN fails at the first step with:
#   "the scaffolder backend plugin requires that it be started with the
#    --no-node-snapshot option"
# Nothing static catches this: the image builds, the pod starts, the plugin registers
# its actions and the template renders — it only surfaces when a task actually
# executes. (Node's startup snapshot is incompatible with isolated-vm creating its
# own V8 isolates; upstream's own Dockerfile carries the same line.)
ENV NODE_OPTIONS=--no-node-snapshot

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

# NUMERIC uid (node = 1000 in the official images), not `USER node`: the chart
# runs with securityContext runAsNonRoot, and kubelet cannot verify a
# NON-NUMERIC image user is non-root -> CreateContainerConfigError (found on
# the first live rollout). A numeric USER satisfies the check with no chart
# override.
USER 1000
WORKDIR /app

# 1) the monorepo skeleton (all package.json files) + the lockfile the CI's own
# `yarn install` generated on the runner - enough for a production-only install.
COPY --chown=node:node .yarnrc.yml package.json yarn.lock backstage.json ./
COPY --chown=node:node .yarn ./.yarn
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
