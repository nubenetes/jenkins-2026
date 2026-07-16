#!/usr/bin/env python3
"""
Guard: every Jenkins behaviour value that reaches a BUILD AGENT must roll the
controller when it changes.

The failure this prevents (lived, 2026-07-16): flipping Binary Authorization off
updated the jenkins-credentials Secret's `binauthz-enabled` to "false", but the
controller did NOT restart — because that key was absent from
`banner_links_checksum` in scripts/04-jenkins.sh — so the running agent kept
`BINAUTHZ_ENABLED=true` and every build failed at sign-and-attest against an
attestor a binauthz-off Day1 had already destroyed.

The chain a value travels:
  jenkins-credentials Secret key
    -> (helm/jenkins/values-common.yaml containerEnv secretKeyRef) CONTROLLER env
    -> (jenkins/casc/jcasc-base.yaml globalNodeProperties ${VAR:-def}) AGENT env
The controller resolves those envs at STARTUP and bakes them into the node
properties, so a Secret change with no controller roll leaves the agent stale.

INVARIANT (this guard): for every Secret key that becomes an AGENT env via that
chain, the value-source that feeds it (the shell variable in 04-jenkins that also
builds `banner_links_checksum`) must be present in that checksum. If it isn't,
flipping it silently strands the agent — fail the build here instead.

Exit 0 = parity holds. Exit 1 = a key is missing from the checksum.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
JCASC = ROOT / "jenkins/casc/jcasc-base.yaml"
VALUES = ROOT / "helm/jenkins/values-common.yaml"
SCRIPT = ROOT / "scripts/04-jenkins.sh"


def die(msg):
    print(f"::error::{msg}")
    sys.exit(1)


def main():
    jcasc = JCASC.read_text(encoding="utf-8")
    values = VALUES.read_text(encoding="utf-8")
    script = SCRIPT.read_text(encoding="utf-8")

    # 1. AGENT envs: every ${VAR:-...} referenced under globalNodeProperties.
    gnp = jcasc.split("globalNodeProperties", 1)
    if len(gnp) < 2:
        die("no globalNodeProperties block in jcasc-base.yaml — chain changed, re-check this guard")
    agent_vars = set(re.findall(r"\$\{([A-Z0-9_]+)(?::-[^}]*)?\}", gnp[1]))

    # 2. controller containerEnv: env NAME -> secret key (only jenkins-credentials).
    #    Blocks look like:  - name: FOO \n ... secretKeyRef: name: jenkins-credentials \n key: bar
    name_to_key = {}
    for m in re.finditer(
        r"-\s*name:\s*([A-Z0-9_]+)\b.*?secretKeyRef:.*?name:\s*jenkins-credentials.*?key:\s*([a-z0-9-]+)",
        values, re.S,
    ):
        name_to_key[m.group(1)] = m.group(2)

    # 3. secret key -> jq arg var (`"key":$jqvar`) -> shell source (`--arg jqvar "${SHELL}"`).
    key_to_jq = dict(re.findall(r'"([a-z0-9-]+)":\$(\w+)', script))
    jq_to_shell = {}
    for m in re.finditer(r'--arg\s+(\w+)\s+"(\$\{[^"}]+\})"', script):
        var = re.sub(r"[${}]", "", m.group(2)).split(":-")[0].strip()
        jq_to_shell[m.group(1)] = var

    # 4. the checksum text (source of truth for "what rolls the controller").
    mc = re.search(r"banner_links_checksum=.*?sha256sum", script, re.S)
    if not mc:
        die("no banner_links_checksum in 04-jenkins.sh — chain changed, re-check this guard")
    checksum = mc.group(0)

    # 5. join. IN SCOPE: keys the 04-jenkins jq payload BUILDS from config (traceable to
    #    a `--arg` shell var) — those are exactly what banner_links_checksum exists to
    #    cover, and what today's bug was. OUT OF SCOPE: credentials (git-token,
    #    registry-*, oidc-*, admin-password) reach the agent too, but they are provisioned
    #    separately (not by that jq payload), a rotation is a different operation, and
    #    their VALUE must never enter a logged checksum. Those are skipped, listed for
    #    transparency. (Limitation: a config flag wired to the agent WITHOUT going through
    #    the jq payload would also be skipped — but that is not the established pattern;
    #    every config flag here flows through `--arg`.)
    missing = []
    checked = []
    skipped = []
    for var in sorted(agent_vars):
        key = name_to_key.get(var)
        if not key:
            continue  # agent env not secret-backed (static default) — cannot go stale
        jq = key_to_jq.get(key)
        shell = jq_to_shell.get(jq) if jq else None
        if not shell:
            skipped.append((var, key))  # credential / not config-derived — out of scope
            continue
        checked.append((var, key, shell))
        if shell not in checksum:
            missing.append(
                f"{var} (secret key '{key}', value ${{{shell}}}) is NOT in banner_links_checksum"
            )

    print(f"Jenkins flag-parity guard: {len(checked)} config-derived agent values checked, "
          f"{len(skipped)} credentials skipped.")
    for var, key, shell in checked:
        print(f"  ok    {var:28} <- {key:24} <- ${shell}")
    for var, key in skipped:
        print(f"  skip  {var:28} <- {key:24} (credential, provisioned separately)")

    if missing:
        print()
        for m in missing:
            print(f"::error::flag-parity: {m}")
        die(
            "A Jenkins Secret value reaches a build agent but flipping it would NOT roll "
            "the controller — the agent would run on the stale value. Add its shell "
            "variable to banner_links_checksum in scripts/04-jenkins.sh. "
            "See the guard header and docs/401-JENKINS.md."
        )

    print("\n✅ every agent-facing Secret value is covered by the controller-roll checksum.")


if __name__ == "__main__":
    main()
