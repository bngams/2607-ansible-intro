# app2 — l'application a ajouter (exercice)

Une app simple (nginx) livree par une autre equipe dev. Objectif : la faire router
**automatiquement** par le proxy des ops.

```bash
docker compose up -d
```

Puis, cote OPS, ajoutez UNE ligne dans l'annuaire
`infra/projects/haproxy/inventory.ini` :

```ini
[apps]
app1 ansible_connection=community.docker.docker
app2 ansible_connection=community.docker.docker   # <- la seule modification
```

et rejouez :

```bash
cd infra/projects/haproxy && ansible-playbook -i inventory.ini site.yml
curl -sL http://localhost:8088/app2
```
