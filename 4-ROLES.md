# 4 — Structurer avec les rôles

Suite de [3](3-VAULT.md). Nos playbooks grossissent (tâches, templates, handlers,
variables…). On les **factorise en rôles** : des briques **réutilisables** et **rangées** selon
une structure standard. C'est ce qu'on avait entr'aperçu en [1](1-FIRST-PLAYBOOK.md) avec
`bootstrap_python` ; on le fait pour de vrai maintenant qu'on a aussi des **handlers** et des
**templates** à ranger.

### Ressources utiles

- [Rôles](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_reuse_roles.html) ·
  [Collections](https://docs.ansible.com/ansible/latest/collections_guide/index.html) ·
  [`requirements.yml` / Galaxy](https://docs.ansible.com/ansible/latest/galaxy/user_guide.html)
- [Molecule](https://ansible.readthedocs.io/projects/molecule/) (tests de rôles)

---

## La structure d'un rôle

Un rôle = un dossier sous `roles/`, avec des **sous-dossiers à noms imposés**. Ansible y cherche
automatiquement chaque type de contenu (toujours dans un `main.yml`) :

```
roles/apache/
├── tasks/main.yml        # les tâches (le cœur)
├── handlers/main.yml     # les handlers (notify)
├── templates/            # les fichiers .j2
├── files/                # les fichiers à copier tels quels
├── defaults/main.yml     # variables par défaut (priorité BASSE → surchargeables)
├── vars/main.yml         # variables internes (priorité haute)
└── meta/main.yml         # métadonnées (dépendances, infos Galaxy)
```

> **`defaults/` vs `vars/`** : `defaults/` = valeurs **par défaut** qu'on s'attend à **surcharger**
> (depuis l'inventaire, le playbook, `-e`…) ; `vars/` = valeurs **internes** au rôle, qu'on ne
> surcharge pas (priorité plus haute). Règle simple : **ce qui est configurable → `defaults/`**.

### Créer le squelette

```bash
ansible-galaxy role init roles/apache      # génère toute l'arborescence ci-dessus
```

---

## Refactor : du playbook aux rôles

On reprend le playbook Apache de [2](2-VARS-TEMPLATES-HANDLERS.md) et on le découpe en
**deux rôles** : `bootstrap_python` (l'amorçage) et `apache` (le serveur web).

### Rôle `apache`

`roles/apache/tasks/main.yml` :

```yaml
- name: Installer les paquets web
  ansible.builtin.apt:
    name: "{{ apache_packages }}"
    state: present
    update_cache: true

- name: Déployer le vhost (template)
  ansible.builtin.template:
    src: site.conf.j2                      # cherché dans roles/apache/templates/
    dest: /etc/apache2/sites-available/000-default.conf
    mode: "0644"
  notify: Recharger Apache                 # handler défini dans roles/apache/handlers/

- name: Démarrer et activer Apache
  ansible.builtin.service:
    name: apache2
    state: started
    enabled: true
```

`roles/apache/handlers/main.yml` :

```yaml
- name: Recharger Apache
  ansible.builtin.service:
    name: apache2
    state: reloaded
```

`roles/apache/defaults/main.yml` (les variables **surchargeables**) :

```yaml
apache_packages:
  - apache2
  - php
  - libapache2-mod-php
http_port: 80
site_title: "Mon site"
admin_email: "ops@example.com"
```

`roles/apache/templates/site.conf.j2` : *(le template de 2, déplacé ici)*

> Remarquez : **plus de chemins `templates/…`** dans les tâches — depuis un rôle, Ansible
> cherche directement dans `roles/apache/templates/`. Tout est rangé à sa place.

### Le playbook devient minuscule

```yaml
# site.yml
- name: Configurer le serveur web
  hosts: web
  become: true
  roles:
    - bootstrap_python
    - apache
```

> **🧪 Manip — refactor en rôles**
>
> 1. `ansible-galaxy role init roles/apache` puis `roles/bootstrap_python`.
> 2. Déplacez tâches / handler / template / variables dans les bons sous-dossiers (ci-dessus).
> 3. Réduisez `site.yml` à la liste de `roles:`.
> 4. `ansible-playbook -i inventory.ini site.yml` → **même résultat** qu'en 2, mais rangé.
> 5. Surchargez une valeur : passez `-e site_title="Autre titre"` → le `defaults/` est bien
>    écrasé.
>
> *Observation : le comportement ne change pas ; la **structure** oui — réutilisable, lisible,
> testable.*

---

## Réutiliser des rôles & collections externes — `requirements.yml`

On n'écrit pas tout soi-même : la communauté publie des **rôles** et des **collections** sur
**Ansible Galaxy**. On les déclare dans un `requirements.yml` :

```yaml
# requirements.yml
collections:
  - name: community.docker          # notre connexion conteneurs (0)
  - name: community.general         # ex. le module htpasswd (3)
roles:
  - name: geerlingguy.apache        # un rôle Apache tout fait, très utilisé
```

Installation :

```bash
ansible-galaxy install -r requirements.yml
```

> **À retenir :** on **versionne** `requirements.yml` (pas les rôles/collections téléchargés).
> En CI, un `ansible-galaxy install -r requirements.yml` précède le `ansible-playbook` — comme
> un `npm install` ou un `terraform init`.

---

## Bonus — tester un rôle avec Molecule

**Molecule** est un **framework de tests** pour les rôles (et collections) Ansible. Il teste un
rôle de façon isolée : il **crée** une instance (souvent un conteneur Docker), **applique** le
rôle (*converge*), **vérifie** le résultat (*verify*), puis **détruit**.

```bash
pip install molecule molecule-plugins[docker]
cd roles/apache
molecule init scenario           # crée molecule/default/
molecule test                    # create → converge → verify → destroy
```

> Cycle utile en CI : un rôle modifié déclenche `molecule test` → on sait **avant** de déployer
> si le rôle est sain. *(Bonus, hors fil rouge.)*

---

## Recap

- Un **rôle** = un dossier structuré (`tasks/`, `handlers/`, `templates/`, `defaults/`, `vars/`,
  `meta/`) — créé via `ansible-galaxy role init`.
- **`defaults/`** (surchargeable) vs **`vars/`** (interne) ; le configurable va en `defaults/`.
- Le **playbook** se réduit à une liste de **`roles:`** → lisible et réutilisable.
- **`requirements.yml`** (+ `ansible-galaxy install`) pour les rôles/collections **externes**.
- **Molecule** pour **tester** un rôle (bonus).

➡️ **[5 — Deux façons de monter les conteneurs (Terraform vs Ansible)](5-TERRAFORM-VS-ANSIBLE.md)**
