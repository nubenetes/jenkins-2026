#!/bin/bash
# migrate.sh - Automated Modernization Script for Jenkins-2026
# Migrates legacy Microservices to JHipster 8+ (Java 21, Spring Boot 3, Angular 18)
set -euo pipefail

echo ">>> Starting Microservices Modernization to JHipster 2026 Standards..."

# 1. Install JHipster CLI globally
if ! command -v jhipster &> /dev/null; then
    echo ">>> Installing JHipster CLI..."
    npm install -g generator-jhipster@latest
fi

# 2. Setup Modernization Workspace
MOD_DIR="modernization"
mkdir -p "$MOD_DIR"
cp apps.jdl "$MOD_DIR/"
cd "$MOD_DIR"

# 3. Generate Microservices Architecture from JDL
echo ">>> Generating boilerplate from apps.jdl..."
jhipster jdl apps.jdl --no-insight --skip-git --skip-install --force

# 4. Post-processing Kubernetes Manifests for OTel
echo ">>> Injecting OpenTelemetry auto-instrumentation annotations..."
if [ -d "kubernetes" ]; then
    cd kubernetes
    # Search for Deployment YAMLs and inject the OTel annotation into the pod template metadata
    # This ensures the OTel Operator picks up the pods for auto-instrumentation.
    find . -name "*-deployment.yml" -exec sed -i '/template:/a \    metadata:\n      annotations:\n        instrumentation.opentelemetry.io/inject-java: "true"' {} +
    cd ..
else
    echo "!!! Warning: 'kubernetes' directory not found. Manifest generation might have failed."
fi

# 5. Build & Push Container Images with Google Jib
echo ">>> Building and Pushing images to GHCR using Jib..."
# Note: Ensure GH_USER and GH_TOKEN are set in your environment
GH_USER="${GH_USER:-your-github-username}"
GH_TOKEN="${GH_TOKEN:-your-github-token}"

for app in gateway customers billing; do
  if [ -d "$app" ]; then
    echo ">>> Building $app..."
    cd "$app"
    ./mvnw -B -ntp jib:build \
      -Djib.to.image="ghcr.io/nubenetes/$app:latest" \
      -Djib.to.auth.username="$GH_USER" \
      -Djib.to.auth.password="$GH_TOKEN"
    cd ..
  fi
done

echo ">>> Modernization Complete!"
echo ">>> Modernized code and manifests are located in the '$MOD_DIR' directory."
echo ">>> Update your Jenkins seed jobs to point to these new modules."
