#!/usr/bin/env bash
# resources/patch-app-source.sh
# ---------------------------------------------------------------------------
# SHARED per-app source patch — the SINGLE SOURCE OF TRUTH applied by ALL FOUR
# CI engines (Jenkins / Tekton / Argo Workflows / GitHub Actions) right after
# the app fork is checked out, BEFORE build. Idempotent; a no-op for any
# service that needs no patching.
#
# WHY THIS EXISTS
#   The microservices forks are kept as CLEAN, UNMODIFIED upstream JHipster
#   samples (so they track upstream and stay honest demos). The 'gateway'
#   upstream (jhipster/jhipster-sample-app-gateway) is generated for MySQL, but
#   this platform runs PostgreSQL (CloudNativePG). Rather than diverge the fork,
#   every engine converts the gateway to PostgreSQL + a NoOp cache HERE, at
#   build time. One script, four engines — no drift.
#   See docs/402-PIPELINES_AS_CODE.md § "Shared app-source patch".
#
# USAGE: patch-app-source.sh <service-name> [app-source-dir]
# ---------------------------------------------------------------------------
set -euo pipefail
SERVICE="${1:?usage: patch-app-source.sh <service-name> [app-source-dir]}"
cd "${2:-.}"

case "${SERVICE}" in
  gateway) ;;
  *) echo "patch-app-source: no patch needed for '${SERVICE}'."; exit 0 ;;
esac

echo "patch-app-source: patching 'gateway' -> PostgreSQL + NoOp cache..."

# 1) Drop the Hibernate 2nd-level @Cache from the reactive User entity (no hibernate-core here).
if [ -f src/main/java/io/github/jhipster/sample/domain/User.java ]; then
  sed -i '/org.hibernate.annotations.Cache/d' src/main/java/io/github/jhipster/sample/domain/User.java
  sed -i '/@Cache(usage = CacheConcurrencyStrategy/d' src/main/java/io/github/jhipster/sample/domain/User.java
fi

# 2) Declare the cache-name constants UserService references (paired with the NoOp cache below).
if [ -f src/main/java/io/github/jhipster/sample/repository/UserRepository.java ]; then
  sed -i '/public interface UserRepository/a \    String USERS_BY_LOGIN_CACHE = "usersByLogin";\n    String USERS_BY_EMAIL_CACHE = "usersByEmail";' src/main/java/io/github/jhipster/sample/repository/UserRepository.java
fi

# 3) MySQL -> PostgreSQL drivers / dialect / URLs in the pom.
if [ -f pom.xml ]; then
  sed -i 's|<groupId>com.mysql</groupId>|<groupId>org.postgresql</groupId>|g' pom.xml
  sed -i 's|<artifactId>mysql-connector-j</artifactId>|<artifactId>postgresql</artifactId>|g' pom.xml
  sed -i 's|<groupId>io.asyncer</groupId>|<groupId>org.postgresql</groupId>|g' pom.xml
  sed -i 's|<artifactId>r2dbc-mysql</artifactId>|<artifactId>r2dbc-postgresql</artifactId>|g' pom.xml
  sed -i 's|<artifactId>mysql</artifactId>|<artifactId>postgresql</artifactId>|g' pom.xml
  sed -i 's|<liquibase-plugin.driver>com.mysql.cj.jdbc.Driver</liquibase-plugin.driver>|<liquibase-plugin.driver>org.postgresql.Driver</liquibase-plugin.driver>|g' pom.xml
  sed -i 's|<liquibase-plugin.hibernate-dialect>org.hibernate.dialect.MySQL8Dialect</liquibase-plugin.hibernate-dialect>|<liquibase-plugin.hibernate-dialect>org.hibernate.dialect.PostgreSQLDialect</liquibase-plugin.hibernate-dialect>|g' pom.xml
  sed -i 's|jdbc:mysql://localhost:3306/jhipsterSampleGateway|jdbc:postgresql://localhost:5432/jhipsterSampleGateway|g' pom.xml
fi

# 4) MySQL -> PostgreSQL URLs in application-prod.yml.
if [ -f src/main/resources/config/application-prod.yml ]; then
  sed -i 's|jdbc:mysql://localhost:3306/jhipsterSampleGateway.*|jdbc:postgresql://localhost:5432/jhipsterSampleGateway|g' src/main/resources/config/application-prod.yml
  sed -i 's|r2dbc:mysql://localhost:3306/jhipsterSampleGateway.*|r2dbc:postgresql://localhost:5432/jhipsterSampleGateway|g' src/main/resources/config/application-prod.yml
fi

# 5) Point the test DB container at Postgres so test sources still COMPILE (`clean verify`
#    test-compiles even with -DskipITs). NOTE: the older per-engine copies pre-date the
#    v9.1.0 DatabaseTestcontainer and omit this line — centralising fixes that drift.
if [ -f src/test/java/io/github/jhipster/sample/config/DatabaseTestcontainer.java ]; then
  sed -i 's|org.testcontainers.containers.MySQLContainer|org.testcontainers.containers.PostgreSQLContainer|g; s|MySQLContainer|PostgreSQLContainer|g; s|"mysql:[0-9.]*"|"postgres:16-alpine"|g; /\.withConfigurationOverride(/d' src/test/java/io/github/jhipster/sample/config/DatabaseTestcontainer.java
fi

# 6) Provide a NoOpCacheManager so the (kept) cache code wires up against no real cache.
mkdir -p src/main/java/io/github/jhipster/sample/config
cat > src/main/java/io/github/jhipster/sample/config/CacheConfiguration.java <<'EOF'
package io.github.jhipster.sample.config;

import org.springframework.cache.CacheManager;
import org.springframework.cache.annotation.EnableCaching;
import org.springframework.cache.support.NoOpCacheManager;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
@EnableCaching
public class CacheConfiguration {

    @Bean
    public CacheManager cacheManager() {
        return new NoOpCacheManager();
    }
}
EOF

echo "patch-app-source: 'gateway' patched -> PostgreSQL + NoOp cache."
