# Container image for spring-microservices-angular, built by microservicesImage.groovy.
#
# Build context = the jenkins-2026 repo root (env.WORKSPACE):
#   docker build -f resources/angular/Dockerfile <jenkins-2026-checkout-root>
#
# - microservices-src/  = checkout of spring-microservices-angular (stage 1 input)
# - resources/angular/{nginx.conf,otel-web.js} = this repo's runtime assets

FROM node:20-bookworm AS build
WORKDIR /app
COPY microservices-src/package*.json ./
RUN npm ci
COPY microservices-src/. .
RUN npm run build -- --configuration production --base-href /

FROM nginx:1.27-alpine AS runtime

# Angular CLI >=17 (esbuild) outputs to dist/<project>/browser; the webpack
# builder outputs to dist/<project>. Copy whichever directory contains
# index.html so this Dockerfile works with either.
COPY --from=build /app/dist /tmp/dist
RUN set -eux; \
    src_dir="$(dirname "$(find /tmp/dist -name index.html -print -quit)")"; \
    rm -rf /usr/share/nginx/html/*; \
    cp -r "${src_dir}/." /usr/share/nginx/html/; \
    rm -rf /tmp/dist

COPY resources/angular/nginx.conf /etc/nginx/conf.d/default.conf
COPY resources/angular/otel-web.js /usr/share/nginx/html/otel-web.js

# Allow nginx's runtime directories to be read/written by either:
# - OpenShift's restricted SCC (arbitrary UID, group 0), via the group bits
#   (chgrp 0 + g=u), or
# - helm/microservices's fixed runAsUser/runAsGroup 1000:1000 (GKE/EKS/AKS,
#   matching the Paketo "cnb" UID used by the Java service images), via the
#   owner bits (chown 1000).
RUN chown -R 1000:0 /usr/share/nginx/html /var/cache/nginx /etc/nginx && \
    chmod -R g=u /usr/share/nginx/html /var/cache/nginx /etc/nginx && \
    touch /var/run/nginx.pid && chown 1000:0 /var/run/nginx.pid && chmod g=u /var/run/nginx.pid

USER 1000:0
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
