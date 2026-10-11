## ADR-002: From hand-built hosts to Ansible to containers (Phase 1-2)
- Hand-built (Phase 1): ~__ min replay, not idempotent, no change report, host-specific.
- Ansible (Phase 2): one command, idempotent (2nd run changed=0), drift detection with --check --diff,
  secrets from SSM at runtime, `make up` builds the shop in ~__ min.
- Still painful: build tools on the server, 10-15 min boot, deploy = restart processes in place,
  "works on this host" config (127.0.0.1 ports), every server must be converged.
- Next: package each service as an immutable container image (Phase 3); keep Ansible for OS/baseline work.
