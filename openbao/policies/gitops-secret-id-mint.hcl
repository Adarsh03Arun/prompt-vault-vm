# Bound to the jwt-github role gitops-secret-id-minter — the GitHub Actions
# OIDC identity that mints a one-time secret_id for gitops-pipeline.
#
# Least privilege by construction: this identity can mint a secret_id for
# exactly one AppRole and cannot write (or read) prompts, sign, list, or
# touch the kill switch. The AppRole itself remains the sole writer
# (gitops-pipeline-write.hcl, architecture doc §3.8).
#
# OpenBao AppRole generate-secret-id is POST
# auth/approle/role/:role_name/secret-id — capability "update".
# Source: https://openbao.org/api-docs/auth/approle/

path "auth/approle/role/gitops-pipeline/secret-id" {
  capabilities = ["update"]
}
