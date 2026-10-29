# Prompt Vault VM drop

Keycloak (shared IAM) and OpenBao + unsealer. Same VM, two folders.

Laptop `gcloud compute scp` is not required. Clone this repo **on the VM**
(Cloud Console → Compute Engine → SSH in the browser).

```
sudo apt-get update
sudo apt-get install -y git
git clone https://github.com/Adarsh03Arun/prompt-vault-vm.git ~/tch
```

If the repo is private, use device login first:

```
# install gh if needed, then:
gh auth login
git clone https://github.com/Adarsh03Arun/prompt-vault-vm.git ~/tch
```

Then copy the running stacks into home:

```
cp -a ~/tch/vm/keycloak ~/keycloak
cp ~/tch/keycloak/realm-export.json ~/keycloak/
cp -a ~/tch/vm/openbao ~/openbao
cp -a ~/tch/scripts ~/openbao/scripts
```

Bring-up: `~/keycloak` first, then `~/openbao`. Details in `vm/README.md`.
Do not commit `.env` or `secrets/`.
