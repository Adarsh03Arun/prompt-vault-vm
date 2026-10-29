# auth/jwt-github — GitOps secret_id minter (GitHub OIDC)

A second JWT auth mount, separate from `auth/jwt` (Keycloak, the human
Admin-UI path). OpenBao's JWT backend takes one issuer per mount
([JWT/OIDC auth method](https://openbao.org/docs/auth/jwt/) — "If multiple
methods are needed, another instance of the backend can be mounted and
configured at a different path"), so GitHub Actions OIDC cannot share
Keycloak's `auth/jwt`.

Issuer is GitHub's documented OIDC provider
(`https://token.actions.githubusercontent.com`) — see
[Configuring OpenID Connect in HashiCorp Vault](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-hashicorp-vault).
The same discovery URL works against OpenBao's JWT method because the
protocol is OIDC, not Vault-specific.

## What this role can do

One role, `gitops-secret-id-minter`, bound to `gitops-secret-id-mint.hcl`:
it can POST `auth/approle/role/gitops-pipeline/secret-id` and nothing
else. The resulting OpenBao token is single-use (`token_num_uses=1`) and
lives two minutes. It cannot write prompts — that stays with the
`gitops-pipeline` AppRole (`../policies/gitops-pipeline-write.hcl`).

`bound_claims` pins the identity to:

- this repository (`GITHUB_OIDC_BOUND_REPOSITORY` at bootstrap)
- the `prod` GitHub Environment (the workflow already declares
  `environment: prod`)
- `event_name=push` (Dependabot OIDC tokens use `dynamic` — excluded)
- this specific workflow file, any ref (`job_workflow_ref` glob)

`bound_audiences` is `openbao` by default; the workflow must request that
audience when fetching the OIDC token, otherwise login fails. GitHub JWTs
always carry an `aud` claim, and OpenBao requires `bound_audiences` to
match at least one of them for JWT roles.

## What this does not do

- Does not replace AppRole as the GitOps writer.
- Does not deploy a separate broker HTTP service — OpenBao itself is the
  exchange, which is the shape GitHub's own Vault OIDC guide uses. The
  "minimal service" mentioned in the old workflow comment was an example,
  not a second piece of infra.
- Does not make OpenBao internet-facing. The runner still has to be able
  to reach OpenBao (today that's the `gitops-pipeline` tag on
  `allow_cicd_to_openbao` in `terraform/network.tf`). GitHub-hosted
  `ubuntu-latest` cannot, per GitHub's own Vault OIDC note about
  self-hosted runners when Vault isn't public.

## Bootstrap

`scripts/bootstrap_openbao.sh` enables `auth/jwt-github` when
`GITHUB_OIDC_BOUND_REPOSITORY` is set (`owner/repo`). Unset, it skips
with a message — same shape as the parked kill-switch path, so local
bootstrap without a real GitHub repo still works.
