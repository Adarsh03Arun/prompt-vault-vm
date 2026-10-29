# PKI scripts — self-hosted, no cloud dependency

Closes two gaps that were previously just "get a certificate somehow"
with no actual tooling: the TLS certs `keycloak/VM-SETUP.md` and
`openbao/VM-SETUP.md` ask for, and the agent/on-call client certs
`scripts/bootstrap_openbao.sh` expects at `AGENT_CA_CERT_PATH` and
`ONCALL_CA_CERT_PATH`.

Plain `openssl`, no cloud KMS, no external CA service — consistent with
the project's cloud-portability constraint. Both scripts were actually
run (in a throwaway Linux container, not just read) on 2026-10-26;
verified: correct cert chain, correct CA extensions, correct SAN on a
server cert, correct key file permissions. One real bug was caught and
fixed in that pass — see `issue_cert.sh`'s own comment.

## The three CAs this project needs — never share one across these

| CA | Signs | Trusted by |
|---|---|---|
| **Server TLS CA** | The Keycloak and OpenBao VMs' own HTTPS certs | Everyone connecting to either server (browsers, backends, agents) |
| **Agent client CA** | AI agent certs for OpenBao's `auth/cert` | Only OpenBao, via `AGENT_CA_CERT_PATH` in `../bootstrap_openbao.sh` |
| **On-call CA** | Break-glass kill-switch certs | Only OpenBao, via `ONCALL_CA_CERT_PATH` in `../bootstrap_openbao.sh` |

Why separate: a compromised agent cert shouldn't let someone impersonate
an on-call engineer's break-glass access, and neither should be able to
mint a cert that passes as the server itself. Mixing these into one CA
collapses three independent trust boundaries into one.

## Usage

```bash
# One CA per trust domain:
./generate_ca.sh "my-org-server-ca" ./server-ca
./generate_ca.sh "my-org-agent-ca" ./agent-ca
./generate_ca.sh "my-org-oncall-ca" ./oncall-ca

# Server cert (needs a SAN matching the real address):
./issue_cert.sh ./server-ca keycloak.internal.example.com ./issued \
  "DNS:keycloak.internal.example.com"

# Agent client cert (CN-matched by OpenBao's allowed_common_names, no SAN):
./issue_cert.sh ./agent-ca nursing-assistant-agent.agents.internal ./issued

# On-call engineer's break-glass cert:
./issue_cert.sh ./oncall-ca jane.oncall.internal ./issued
```

## What this does not solve

- **Distribution.** Getting the issued cert+key onto the right VM, and
  the CA cert onto everything that needs to trust it, is still a manual
  step per deployment.
- **The server TLS CA's own rotation.** Still manual (`CERT_VALIDITY_DAYS`
  override, re-run `issue_cert.sh`) — this CA has to exist *before*
  OpenBao is reachable at all, so it structurally can't depend on
  OpenBao's own PKI engine the way the two client CAs now do (below).

## Rotation for the agent and on-call client CAs — now automated (resolved 2026-10-26)

**Use `rotate_leaf_cert.sh`, not `issue_cert.sh`, for the agent client CA
and the on-call CA.** `../bootstrap_openbao.sh` now defaults
`CERT_ROTATION_MODE=openbao-pki`: it enables OpenBao's own PKI secrets
engine as the root CA for each (`pki-agent`, `pki-oncall` mounts), and
from then on, rotating any individual agent's or on-call engineer's leaf
cert is just:

```bash
BAO_ADDR=https://<openbao-host>:8200 BAO_TOKEN=<narrowly-scoped token> \
  ./rotate_leaf_cert.sh pki-agent agent-cert nursing-assistant-agent.agents.internal ./issued
```

The root CA never moves — only the leaf (what OpenBao's `auth/cert`
actually matches a connecting identity against) rotates, well inside the
role's `ttl` (72h for agent certs, 720h for on-call, both overridable).
That's why this is real rotation and not just reissuance: nothing about
OpenBao's own trust config needs touching again after the one-time
bootstrap, ever, for this to keep working.

Scheduling: `prompt-vault-cert-rotation.service.tmpl` +
`.timer.tmpl` are systemd unit templates — fill in the `__PLACEHOLDERS__`
per identity and `systemctl enable --now` the timer. A token for the
service to use only needs the narrow `<mount>-issue` policy
`../bootstrap_openbao.sh` writes (e.g. `pki-agent-issue`) — never a root
token.

`CERT_ROTATION_MODE=manual` keeps the old external-CA path above
(`generate_ca.sh` + `issue_cert.sh`) for whoever isn't ready to depend on
OpenBao's PKI engine yet — nothing about it changed.

**Verified for real, 2026-10-26**: against the actual running
`prompt-vault-openbao` container (`deploy/identity-vault/docker/`) —
enabled `pki-agent`, generated its root CA, created the `agent-cert`
role, issued a leaf cert with `rotate_leaf_cert.sh`, pointed
`auth/cert/certs/agent-cert-auth` at that PKI engine's own CA cert, and
logged in with the issued leaf cert over real mTLS, receiving the
expected `agent-prompt-read` policy. Then issued a second leaf cert for
the same identity (simulating a rotation) and logged in with *that* one
too, with zero changes to OpenBao's trust config in between — proving
the root-never-moves claim above, not just asserting it.
