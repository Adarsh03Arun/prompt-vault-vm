# Keycloak providers

`xelerait-keycloak-theme-26.jar` — XelerAIT login theme (Keycloakify).

Theme name in Admin Console: **`xelerait`**

After `git pull` / clone, when you copy the stack:

```bash
cp -a ~/tch/vm/keycloak ~/keycloak
cp ~/tch/keycloak/realm-export.json ~/keycloak/
# providers/ (including the JAR) is already under vm/keycloak/
cd ~/keycloak
docker compose up -d --force-recreate keycloak
```

Then: Admin Console → realm → Themes → Login theme = **xelerait**.
