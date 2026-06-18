# Gemini Developer Assistant Guide - jenkins-2026

Welcome! This repository defines the central Infrastructure, Jenkins pipelines-as-code, and Observability stack for the JHipster-based microservices architecture. It functions as the **source of truth** for pipelines, Helm values, and orchestration scripts.

---

## 🏗️ Repository Architecture

The project is structured logically as follows:

```
├── config/
│   └── config.yaml               # Central configuration file (targets, namespaces, releases)
├── scripts/
│   ├── lib/
│   │   ├── common.sh             # Helper functions (logging, wait_for_deployment, etc.)
│   │   └── config.sh             # Sourced by other scripts; parses config.yaml into J2026_* environment variables
│   ├── 00-check-prereqs.sh
│   ├── 01-namespaces.sh          # Creates namespaces (jenkins, observability, argocd, pgadmin, microservices)
│   ├── 02-otel-operator.sh
│   ├── 03-observability.sh
│   ├── 04-jenkins.sh
│   ├── 08.5-argocd.sh
│   ├── 09-gateway.sh
│   └── down.sh                   # Safely tears down all helm releases and resources
├── jenkins/
│   ├── casc/
│   │   └── jcasc-base.yaml       # Jenkins Configuration as Code (plugins, global configs, library configs)
│   └── pipelines/
│   │   └── seed/
│   │       ├── seed_jobs.groovy  # Job DSL script generating pipelines-as-code
│   │       └── services.yaml     # Microservices registry defining repo URLs, types, ports
├── vars/
│   ├── MicroservicesPipeline.groovy       # Declarative shared library wrapper for JHipster microservices
│   ├── MicroservicesK6SmokePipeline.groovy # Pipeline for triggering k6 integration smoke tests
│   ├── microservicesBuild.groovy          # Maven/Node build execution helper
│   ├── microservicesImage.groovy          # Docker build & push helper via DinD (Docker-in-Docker)
│   ├── microservicesDeploy.groovy         # Triggers gitops config repo updates
│   └── microservicesSmokeTest.groovy      # Validates deployed services (Spring Actuator check)
└── observability/
    ├── otel-collector/           # OTel collector Gateway and Logs agent values
    └── grafana/
        └── dashboards/           # Provisioned Grafana dashboards (k6-smoke, microservices-overview)
```

---

## 🚀 Key Pipelines and Execution Flows

The project is built around a **Unified Pipeline Model**:
1. **Dynamic Configuration**: Jenkins pipelines dynamically fetch configuration from this infra repo's active branch.
2. **Stable Single-Namespace**: All components are deployed to the `microservices` namespace (stable), tracking the `main` branch of upstream repos. The legacy `develop` track is pruned.
3. **Hibernate Annotation Patching**: The reactive Gateway application (`jhipster-sample-app-gateway`) contains Hibernate annotations that fail compilation on modern Java since it uses Spring Data R2DBC instead of JPA. The pipeline (`MicroservicesPipeline.groovy`) automatically patches out these annotations right after checkout.

---

## 🛠️ Operational Tasks & Run Commands

As an AI assistant, follow these standard commands for maintenance:

### 1. Verification & Status Check
Check the rollout status of all services:
```bash
./scripts/status.sh
```

### 2. Full Up / Provision Stack
```bash
./scripts/00-check-prereqs.sh
./scripts/01-namespaces.sh
./scripts/02-otel-operator.sh
./scripts/03-observability.sh
./scripts/08.5-argocd.sh
./scripts/04-jenkins.sh
./scripts/09-gateway.sh
```

### 3. Teardown
```bash
./scripts/down.sh
```

---

## 💡 Troubleshooting and Optimization Tips

1. **Jib/Maven Daemon Issues**: Ensure you run clean compiles with Docker-in-Docker. The shared library handles DinD mounting automatically.
2. **ArgoCD App Synchronization**: The ApplicationSet (`argocd/microservices-appset.yaml`) points to the `jenkins-2026-gitops-config` repository. AppSync triggers automatically when Jenkins commits and pushes updated image tags to the gitops repo.
3. **Observability Logs**: All application logs are forwarded by Loki logs agent to Grafana Cloud. Log-to-trace correlation is established via `trace_id` annotations parsed from standard SLF4J MDC logs.
