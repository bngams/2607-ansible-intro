#!/usr/bin/env bash
# Installe les dependances declarees dans requirements.yml.
# Equivalent d'un "npm install" / "terraform init" avant le playbook.
set -euo pipefail
cd "$(dirname "$0")"
OPS_REPO="$(cd ../.. && pwd)"          # racine du lab (ou vit infra/)
sed "s|__OPS_REPO__|$OPS_REPO|" requirements.yml > /tmp/req.$$.yml
ansible-galaxy install -r "/tmp/req.$$.yml" -p ./roles
rm -f "/tmp/req.$$.yml"
