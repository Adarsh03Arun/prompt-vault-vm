# Transit unsealer on the same stack as OpenBao. Shamir — root of auto-unseal.
# OpenBao reaches this over the Compose network (https://openbao-unsealer:8200).

storage "raft" {
  path    = "/openbao/file"
  node_id = "unsealer-node"
}

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/openbao/certs/openbao-unsealer.crt"
  tls_key_file  = "/openbao/certs/openbao-unsealer.key"
}

api_addr     = "https://openbao-unsealer:8200"
cluster_addr = "https://openbao-unsealer:8201"

ui = true
