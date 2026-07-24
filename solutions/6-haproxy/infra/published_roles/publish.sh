#!/usr/bin/env bash
# Cote OPS : "publier" un role = le versionner dans un depot Git et le TAGUER.
# En entreprise ce serait un push sur GitLab/GitHub ; ici, un depot local suffit
# pour que les projets dev puissent le consommer via requirements.yml.
set -euo pipefail
cd "$(dirname "$0")/wordpress"

if [ ! -d .git ]; then
  git init -q .
fi
git add -A
git -c user.email=ops@example.com -c user.name=equipe-ops \
    commit -qm "role wordpress" 2>/dev/null || echo "(rien de nouveau a committer)"
git tag -f v1.0.0 -m "v1.0.0" >/dev/null

echo "Role publie : $(pwd)"
echo "Version     : $(git tag | tr '\n' ' ')"
