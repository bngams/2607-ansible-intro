# 1 — Premier playbook : fichier, service, Apache

Suite de [0](0-SETUP.md). On apprend les **fondamentaux** sur **un seul conteneur** :
gérer un **fichier**, un **service**, et monter un **serveur Apache**. C'est la base que tous
les chapitres suivants réutilisent.

### Ressources utiles

- [Playbooks (intro)](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_intro.html) ·
  [Inventaires](https://docs.ansible.com/ansible/latest/inventory_guide/intro_inventory.html)
- Modules : [`file`](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/file_module.html) ·
  [`copy`](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/copy_module.html) ·
  [`apt`](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/apt_module.html) ·
  [`service`](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/service_module.html) ·
  [`raw`](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/raw_module.html)

---

## La cible : un conteneur `debian:12`

On part d'une image **minimale** (`debian:12`) — volontairement, pour rencontrer un **piège
classique** : une image minimale **n'a pas Python**, or Ansible en a besoin sur la cible.

```bash
docker run -d --name web1 debian:12 sleep infinity
```

### L'inventaire

L'**inventaire** déclare **qui** Ansible doit configurer : des **hôtes** rangés en **groupes**,
chacun avec d'éventuelles **variables**. Objectif ici : juste comprendre la structure (détails
dans la [doc inventaires](https://docs.ansible.com/ansible/latest/inventory_guide/intro_inventory.html)).

Deux formats équivalents — **INI** (compact) :

```ini
# inventory.ini
[web]                                          # un groupe "web"
web1 ansible_connection=community.docker.docker http_port=80   # hôte + variables

[web:vars]                                     # variables communes au groupe "web"
admin_email=ops@example.com
```

…ou **YAML** (plus structuré, pratique quand ça grossit) :

```yaml
# inventory.yml
all:
  children:
    web:
      vars:                                    # variables communes au groupe
        admin_email: ops@example.com
      hosts:
        web1:
          ansible_connection: community.docker.docker
          http_port: 80                        # variable propre à l'hôte
```

> Les variables comme `ansible_connection`, `ansible_host`, `ansible_user`… sont des **variables
> de connexion** reconnues par Ansible. On peut aussi mettre des variables « métier » par hôte ou
> par groupe (cf. `group_vars`/`host_vars` en [2](2-VARS-TEMPLATES-HANDLERS.md)).

Pour ce chapitre, on utilise le format **INI** ci-dessus.

---

## Le piège : pas de Python dans l'image

> **🧪 Manip — constater le problème**
>
> ```bash
> ansible -i inventory.ini web -m ping
> ```
> Échec :
> ```
> "module_stderr": "/bin/sh: 1: /usr/bin/python3: not found"
> ```
>
> *La plupart des modules Ansible s'exécutent **en Python sur la cible**. Une image minimale n'en
> a pas → il faut l'installer d'abord.*

### La solution : le module `raw` (qui n'a PAS besoin de Python)

Le module **`raw`** exécute une commande shell brute, **sans** Python — parfait pour
**amorcer** (bootstrap) Python sur la cible.

```yaml
# bootstrap.yml
- name: Bootstrap Python sur des cibles minimales
  hosts: web
  gather_facts: false          # pas de facts tant que Python n'est pas là
  tasks:
    - name: Python est-il présent ?
      ansible.builtin.raw: command -v python3
      register: pycheck
      changed_when: false
      failed_when: false

    - name: Installer Python (apt) si absent
      ansible.builtin.raw: apt-get update -y && apt-get install -y python3
      when: pycheck.rc != 0
```

> **🧪 Manip — amorcer Python puis re-ping**
>
> ```bash
> ansible-playbook -i inventory.ini bootstrap.yml
> ansible -i inventory.ini web -m ping        # → pong (Python est là maintenant)
> ```
>
> *Observation : on a contourné l'absence de Python avec `raw`, puis Ansible fonctionne
> normalement. En [4](4-ROLES.md) on en fera un **rôle réutilisable** (`bootstrap_python`).*

---

## Tâche 1 — Gérer un fichier

```yaml
# playbook.yml
- name: Configurer le serveur web
  hosts: web
  become: true
  tasks:
    - name: Déposer une page d'accueil
      ansible.builtin.copy:
        content: "<h1>Configuré par Ansible</h1>\n"
        dest: /var/www/html/index.html
        mode: "0644"
```

> `become: true` = élévation de privilèges (root) — l'équivalent de `sudo`.

---

## Tâche 2 — Installer un paquet + gérer un service (Apache)

```yaml
    - name: Installer Apache
      ansible.builtin.apt:
        name: apache2
        state: present
        update_cache: true

    - name: Démarrer et activer Apache
      ansible.builtin.service:
        name: apache2
        state: started
        enabled: true
```

> `state: present` (le paquet doit être là), `state: started` (le service doit tourner) : on
> décrit **l'état voulu**, pas les commandes. Ansible ne fait quelque chose **que si** ce n'est
> pas déjà le cas — c'est l'**idempotence**.

---

## Exécuter le playbook complet

On rassemble tout dans **un seul playbook**, dans l'ordre **logique** : amorcer Python →
**installer** le serveur → déposer son **contenu** → s'assurer qu'il **tourne**. (Les tâches 1 et
2 ci-dessus sont présentées dans l'ordre d'apprentissage ; ici on remet l'ordre d'exécution
naturel.) L'amorçage Python sera **extrait dans un rôle réutilisable** (`bootstrap_python`) au
chapitre [4](4-ROLES.md) ; ici on le garde en tâche inline.

```yaml
# site.yml — tout-en-un pour ce chapitre
- hosts: web
  gather_facts: false
  become: true
  tasks:
    - name: Bootstrap Python
      ansible.builtin.raw: command -v python3 || (apt-get update -y && apt-get install -y python3)
      changed_when: false

    - name: Installer Apache
      ansible.builtin.apt: { name: apache2, state: present, update_cache: true }

    - name: Page d'accueil
      ansible.builtin.copy:
        content: "<h1>Configuré par Ansible</h1>\n"
        dest: /var/www/html/index.html
        mode: "0644"

    - name: Démarrer et activer Apache
      ansible.builtin.service: { name: apache2, state: started, enabled: true }
```

> **🧪 Manip — configurer puis vérifier**
>
> ```bash
> ansible-playbook -i inventory.ini site.yml
>
> # tester depuis le conteneur (il n'expose pas de port ici)
> docker exec web1 curl -s localhost | head -1     # → <h1>Configuré par Ansible</h1>
> ```
>
> *Observation : un conteneur nu est devenu un serveur web configuré, en déclaratif.*

---

## L'idempotence en action

> **🧪 Manip — rejouer = aucun changement**
>
> ```bash
> ansible-playbook -i inventory.ini site.yml
> ```
> Au 2e passage, le récap affiche **`changed=0`** (tout est déjà dans l'état voulu) :
> ```
> web1 : ok=4  changed=0  unreachable=0  failed=0
> ```
>
> *Observation : rejouer un playbook est **sûr**. C'est LA propriété qui rend Ansible fiable —
> on peut relancer autant qu'on veut, il ne fait que le nécessaire.*

> **Idempotence (Ansible) vs state (Terraform).** Même objectif : ne pas refaire le travail,
> mais deux mécanismes opposés :
> - **Terraform** garde un **state** et compare trois états : *voulu* (votre code `.tf`),
>   *enregistré* (le `tfstate` = ce que TF croit avoir créé), *réel* (ce que l'API renvoie au
>   `refresh`). Le `plan` **montre** les écarts (drift), et comme TF gère un **ensemble délimité**
>   de ressources (il connaît la liste complète de ce qu'il gère), il peut aussi en **supprimer**.
> - **Ansible** n'a **pas de state** : à chaque exécution il **vérifie la réalité** tâche par
>   tâche et corrige si besoin. Il **rattrape** donc la dérive en re-jouant… mais **ne la signale
>   pas**, et **seulement** sur ce que votre playbook déclare (un paquet ajouté à la main hors
>   playbook, il l'ignore).
>
> Résumé : **TF = voir la dérive** (rapport, périmètre maîtrisé) ; **Ansible = corriger la
> dérive** par ré-assertion (mais sans rapport, et limité à ce qu'on a écrit). Ni l'un ni
> l'autre « meilleur » dans l'absolu — deux modèles.

### Nettoyage — et l'absence de « destroy »

> **Pas d'équivalent `terraform destroy` en Ansible.** Sans state, Ansible ne sait pas
> « défaire tout ce qu'il a fait ». Pour retirer quelque chose, on écrit des **tâches inverses
> explicites** (`state: absent`, service `stopped`…), souvent dans un playbook `uninstall.yml`
> dédié. Ici, la cible étant un conteneur jetable, on le supprime simplement :

```bash
docker rm -f web1
```

---

## Vers un rôle (aperçu)

Notre bloc d'amorçage Python peut être **autonome et réutilisable** : c'est le candidat parfait
pour un **rôle**. Un rôle n'est pas un simple fichier : c'est un dossier qui suit une
**arborescence standard** (`tasks/`, `handlers/`, `templates/`, `defaults/`…). Ansible y range
chaque type de contenu à un endroit attendu.

**🧪 Manip (aperçu) — extraire le bootstrap dans un rôle**

1. Créer l'arborescence du rôle (ici, seul `tasks/` nous concerne) :

   ```bash
   mkdir -p roles/bootstrap_python/tasks
   ```

2. **Déplacer** les deux tâches d'amorçage dans `roles/bootstrap_python/tasks/main.yml` :

   ```yaml
   # roles/bootstrap_python/tasks/main.yml
   - name: Python est-il présent ?
     ansible.builtin.raw: command -v python3
     register: pycheck
     changed_when: false
     failed_when: false

   - name: Installer Python (apt) si absent
     ansible.builtin.raw: apt-get update -y && apt-get install -y python3
     when: pycheck.rc != 0
   ```

3. Dans le playbook, **appeler le rôle** au lieu d'écrire les tâches :

   ```yaml
   - hosts: web
     gather_facts: false
     roles:
       - bootstrap_python      # remplace le bloc de tâches inline (Ansible repère directement les rôles dans l'arborescence de fichiers)
   ```

*Observation : le playbook devient plus lisible, et `bootstrap_python` est réutilisable dans
n'importe quel autre projet.*

> Ce n'est qu'un **aperçu** (un rôle à une seule partie). La **structure complète**
> (`handlers/`, `templates/`, `defaults/`, `meta/`…), `requirements.yml` et la réutilisation
> via Galaxy sont vus en [4](4-ROLES.md) — une fois qu'on aura des handlers et des
> templates (2) à y ranger.

---

## Recap

- **Module `raw`** → amorcer Python sur une image minimale (pas de Python = `ping` échoue).
- **`copy`/`file`** → gérer des fichiers ; **`apt`** → paquets ; **`service`** → services.
- **`become: true`** → privilèges root.
- On décrit **l'état voulu** (`present`/`started`) → **idempotence** (rejouer ⇒ `changed=0`).
- **Pas de state ni de `destroy`** comme Terraform : Ansible **corrige** la dérive en re-jouant ;
  pour défaire, on écrit des **tâches inverses** (`state: absent`).
- Un bloc de tâches autonome → candidat à un **rôle** (structure complète en [4](4-ROLES.md)).

➡️ **[2 — Variables, facts, templates Jinja2, handlers](2-VARS-TEMPLATES-HANDLERS.md)**
