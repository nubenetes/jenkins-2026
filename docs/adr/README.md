# Architecture Decision Records (ADRs)

Short, dated records of **significant, hard-to-reverse decisions** and the
alternatives that were rejected — so a decision isn't silently re-litigated
later. Like [runbooks](../README.md#runbooks--validated-live-procedures), ADRs
are **leaf documents**: numbered `NNNN-title.md`, **not** part of the 100→903
prev/next nav chain, and linked *from* the numbered guide whose subsystem they
concern. The deep *how/why* stays in the numbered guides; the ADR captures the
**decision + trade-offs**.

| ADR | Decision | Companion guide(s) |
| :--- | :--- | :--- |
| [0001. Intra-cluster TLS & supply-chain admission](./0001-intra-cluster-security-and-supply-chain-admission.md) | Adopt **Cloud Service Mesh (standalone)** for east-west identity mTLS (opt-in, mutually exclusive with backend TLS) + **Binary Authorization** for supply-chain admission (opt-in, orthogonal); reject Istio-self-managed / Traefik / other meshes | [506](../506-SERVICE-MESH.md) · [507](../507-BINARY-AUTHORIZATION.md) · [504](../504-BACKEND_TLS.md) |

## Adding an ADR

Copy the structure of `0001-…`: **Status** (Proposed / Accepted / Superseded, dated) ·
**Context** · **Decision Drivers** · **Considered Options** (with a comparison
matrix) · **Decision Outcome** · **Consequences** · **Links**. Use the next free
`NNNN`. Add a row above and a pointer from the relevant numbered guide.
