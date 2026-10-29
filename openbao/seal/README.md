# Seal (auto-unseal) — configurable, not a fixed choice

OpenBao encrypts everything behind a master key; a sealed server can't
decrypt anything, including on restart. By default that means a human
supplies Shamir key shares after every restart. These three options
decide whether (and how) that's automated instead.

**Default, chosen for the MVP (resolved 2026-10-26): `transit`.** Picked
over `gcpckms` for the same org constraint as elsewhere in this folder -
minimal dependence on the cloud provider beyond plain VMs, even though
every VM today happens to be on GCP - and picked over `shamir` because
it automates unsealing instead of requiring a human on every restart,
without taking on cloud-provider lock-in to get there. All three options
are selected via `openbao_seal_mode` in `../../terraform/variables.tf`
and rendered into `../config.hcl.tmpl` via the matching fragment in this
folder; a Terraform `check` block fails fast if `transit` is selected
without the connection details it needs (see below).

| Mode | File | Cloud dependency | Notes |
|---|---|---|---|
| `transit` | `transit.hcl.tmpl` | None beyond a VM | **The MVP default.** A second, small, already-unsealed OpenBao/Vault instance does the unsealing via its own Transit engine. Cloud-agnostic. |
| `shamir` | *(no fragment — omits the seal stanza entirely)* | None | Zero infra, zero config, real human effort on every restart. Selectable, not the default. |
| `gcpckms` | `gcpckms.hcl.tmpl` | GCP Cloud KMS (GCP-specific API, key, IAM binding) | Operationally simplest *if* already committed to GCP - but every piece of it is non-portable. Not chosen, for exactly that reason. |

Switching modes is a Terraform variable change (`openbao_seal_mode`),
not a redesign - see `terraform/openbao_vm.tf` for how the fragment gets
picked and rendered.

**Not provisioned here**: the `transit` unsealer instance itself (its own
small VM, its own OpenBao install, its own Transit key) isn't built out
by this Terraform - only the connection details (`transit_unsealer_*`
variables) that the *main* OpenBao instance uses to reach it. Standing
up that small instance is a separate, much smaller task than anything
else in this folder - likely a plain-VM/Docker setup in the same spirit
as `../../keycloak/VM-SETUP.md`, not a new Terraform module.
