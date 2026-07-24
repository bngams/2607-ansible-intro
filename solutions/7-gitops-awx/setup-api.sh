#!/usr/bin/env bash
# Recree TOUTE la configuration GitOps dans Semaphore, via son API.
# Utile pour rejouer la demo sans cliquer (et pour montrer que les objets
# du controleur sont eux aussi "as code").
#
# Usage : ./setup-api.sh
set -euo pipefail
cd "$(dirname "$0")"

BASE=${BASE:-http://127.0.0.1:3000}
USER=${SEM_USER:-admin}
PASS=${SEM_PASS:-changeme}
COOKIE=$(mktemp)
trap 'rm -f "$COOKIE"' EXIT

say() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

# --- 0. le repo surveille doit etre un VRAI depot git ---------------------
say "Depot git local (demo-repo)"
if [ ! -d demo-repo/.git ]; then
  git -C demo-repo init -q .
  git -C demo-repo add -A
  git -C demo-repo -c user.email=dev@example.com -c user.name=demo \
      commit -qm "playbook de reconciliation"
  echo "   depot initialise"
else
  echo "   deja un depot git (ok)"
fi

# --- 1. attendre que l'API reponde ---------------------------------------
say "Attente du controleur ($BASE)"
for _ in $(seq 1 30); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/ping" --max-time 3 || true)" = "200" ] && break
  sleep 2
done
[ "$(curl -s "$BASE/api/ping" --max-time 5)" = "pong" ] || { echo "API injoignable"; exit 1; }
echo "   pong"

# --- 2. login -------------------------------------------------------------
say "Authentification"
curl -sf -c "$COOKIE" -X POST "$BASE/api/auth/login" \
  -H 'Content-Type: application/json' \
  -d "{\"auth\":\"$USER\",\"password\":\"$PASS\"}" -o /dev/null
echo "   connecte en tant que $USER"

api() { curl -sf -b "$COOKIE" "$@"; }
jqid() { python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])'; }

# --- 3. Project -----------------------------------------------------------
say "Project"
PID=$(api -X POST "$BASE/api/projects" -H 'Content-Type: application/json' \
  -d '{"name":"Demo GitOps","alert":false}' | jqid)
echo "   project id=$PID"
P="$BASE/api/project/$PID"

# --- 4. Key Store (aucune auth : le repo est local) -----------------------
say "Key Store (Credential)"
KID=$(api -X POST "$P/keys" -H 'Content-Type: application/json' \
  -d "{\"name\":\"none\",\"type\":\"none\",\"project_id\":$PID}" | jqid)
echo "   key id=$KID"

# --- 5. Repository : OU chercher le code ---------------------------------
say "Repository (Project SCM)"
RID=$(api -X POST "$P/repositories" -H 'Content-Type: application/json' \
  -d "{\"name\":\"demo-repo\",\"project_id\":$PID,\"git_url\":\"/repos/demo-repo\",\"git_branch\":\"main\",\"ssh_key_id\":$KID}" | jqid)
echo "   repository id=$RID  (/repos/demo-repo, branche main)"

# --- 6. Inventory : SUR QUOI jouer ---------------------------------------
say "Inventory"
IID=$(api -X POST "$P/inventory" -H 'Content-Type: application/json' \
  -d "{\"name\":\"local\",\"project_id\":$PID,\"type\":\"static\",\"inventory\":\"[local]\\nlocalhost ansible_connection=local\\n\",\"ssh_key_id\":$KID,\"become_key_id\":$KID}" | jqid)
echo "   inventory id=$IID"

# --- 7. Environment (requis par les templates) ---------------------------
say "Environment"
EID=$(api -X POST "$P/environment" -H 'Content-Type: application/json' \
  -d "{\"name\":\"empty\",\"project_id\":$PID,\"json\":\"{}\",\"env\":\"{}\"}" | jqid)
echo "   environment id=$EID"

# --- 8. Task Template : QUOI jouer ---------------------------------------
say "Task Template (Job Template)"
TID=$(api -X POST "$P/templates" -H 'Content-Type: application/json' \
  -d "{\"project_id\":$PID,\"name\":\"Reconcilier\",\"playbook\":\"site.yml\",\"inventory_id\":$IID,\"repository_id\":$RID,\"environment_id\":$EID,\"app\":\"ansible\",\"type\":\"\"}" | jqid)
echo "   template id=$TID  (playbook site.yml)"

# --- 9. Schedule : QUAND jouer -> c'est CA, le pull ----------------------
say "Schedule (cron)"
# Deux modes possibles, la difference tient au champ "repository_id" :
#   - SANS repository_id -> cron AVEUGLE : rejoue a chaque tick, commit ou pas.
#   - AVEC repository_id -> Semaphore interroge le depot a cet intervalle et ne
#     lance la tache QUE si le SHA a change. C'est l'equivalent API de la case
#     "Auto-run task if new git commit have been found" (cron_format = checkInterval).
# On prend le second : plus proche d'Argo CD/Flux (on reagit a l'etat desire,
# pas a l'horloge).
#
# /!\ Un PUT sur /schedules/{id} SUPPRIME le schedule au lieu de le mettre a
#     jour (204 puis liste vide). Pour le modifier : DELETE puis POST.
api -X POST "$P/schedules" -H 'Content-Type: application/json' \
  -d "{\"project_id\":$PID,\"template_id\":$TID,\"cron_format\":\"* * * * *\",\"active\":true,\"name\":\"on-commit\",\"repository_id\":$RID}" >/dev/null
echo "   declenchement SUR COMMIT (verification toutes les minutes)"

# --- 10. premier run ------------------------------------------------------
say "Lancement d'un premier run"
RUN=$(api -X POST "$P/tasks" -H 'Content-Type: application/json' \
  -d "{\"template_id\":$TID,\"project_id\":$PID,\"debug\":false,\"dry_run\":false}" | jqid)
for _ in $(seq 1 20); do
  ST=$(api "$P/tasks/$RUN" | python3 -c 'import sys,json;print(json.load(sys.stdin)["status"])')
  case "$ST" in success|error|stopped) break;; esac
  sleep 2
done
echo "   task id=$RUN -> $ST"

printf '\n\033[1mPret.\033[0m  UI : %s  (%s / %s)\n' "$BASE" "$USER" "$PASS"
cat <<'TIP'

Le planning ne rejoue PAS toutes les minutes : il attend un NOUVEAU COMMIT.
Pour le declencher (et voir la reconciliation sur evenement) :

  cd demo-repo
  # modifiez site.yml, puis :
  git commit -am "changement d etat desire"
  # -> un run part dans la minute qui suit

Suivre les runs : docker compose logs -f semaphore | grep 'Task added'
TIP
