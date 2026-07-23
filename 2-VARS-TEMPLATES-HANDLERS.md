# 2 — Variables, facts, templates Jinja2, handlers

Suite de [1](1-FIRST-PLAYBOOK.md). Les tâches de 1 étaient « en dur ». On les rend
**paramétrables** et **dynamiques** : variables, **facts**, **templates Jinja2** (générer des
fichiers de config), conditions/boucles, et **handlers** (relancer un service *seulement* quand
sa config change).

### Ressources utiles

- [Variables](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_variables.html) ·
  [Facts](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_vars_facts.html) ·
  [group_vars / host_vars](https://docs.ansible.com/ansible/latest/inventory_guide/intro_inventory.html#organizing-host-and-group-variables)
- [Module `template`](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/template_module.html) ·
  [Templating (Jinja2)](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_templating.html)
- [Conditionals (`when`)](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_conditionals.html) ·
  [Loops](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_loops.html) ·
  [Handlers](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_handlers.html)

> On réutilise le conteneur web de 1 : `docker run -d --name web1 debian:12 sleep infinity`
> (et l'inventaire `[web] web1 ansible_connection=community.docker.docker`).

---

## 1. Les variables

On peut définir des variables à plusieurs endroits ; les plus courants :

| Où | Pour quoi |
|---|---|
| `vars:` dans le playbook | variables locales au play |
| **`group_vars/<groupe>.yml`** | variables communes à un **groupe** de l'inventaire (ex. `web`) |
| **`host_vars/<hôte>.yml`** | variables propres à **un hôte** |
| `--extra-vars` / `-e` | en ligne de commande (priorité haute) |

Exemple d'un fichier contenant des variables :

```yaml
# group_vars/web.yml
site_title: "Mon site"
http_port: 80
admin_email: "ops@example.com"
```

On les utilise avec la syntaxe `{{ … }}`. Voici un exemple avec le module
**`ansible.builtin.debug`** (qui sert justement à **afficher** une valeur / un message ; très
pratique pour vérifier le contenu d'une variable) :

```yaml
- name: Afficher le titre du site
  ansible.builtin.debug:
    msg: "Titre = {{ site_title }} (port {{ http_port }})"
```

Et bien sûr dans une vraie tâche :

```yaml
- name: Page d'accueil paramétrée
  ansible.builtin.copy:
    content: "<h1>{{ site_title }}</h1>\n"
    dest: /var/www/html/index.html
```

> **🧪 Manip — une variable au lieu d'une valeur en dur**
>
> Créez `group_vars/web.yml` (comme l'exemple plus haut) avec `site_title`, rejouez le playbook,
> puis changez la valeur et rejouez pour que la page change. *Observation : le « quoi » (config) est séparé du « comment » (tâches).*

---

## 2. Les facts (ce qu'Ansible découvre tout seul)

Les **facts** sont des **données récoltées sur les cibles**, et **exposées par Ansible sous
forme de variables**. Les facts sont ensuite disponibles dans tout le play (tâches, templates,
rôles…).

Sur le play, quand `gather_facts: true`, Ansible **collecte des infos sur la cible** (OS, IP,
CPU, mémoire…) et les expose en variables `ansible_*`.

```yaml
- name: Afficher la distribution et l'IP
  ansible.builtin.debug:
    msg: "{{ inventory_hostname }} = {{ ansible_distribution }} {{ ansible_distribution_version }}, IP {{ ansible_default_ipv4.address | default('n/a') }}"
```

> **🧪 Manip — explorer les facts**
>
> ```bash
> ansible -i inventory.ini web -m setup            # dump TOUS les facts
> ansible -i inventory.ini web -m setup -a 'filter=ansible_distribution*'
> ```
> *Observation : on peut écrire des tâches qui s'adaptent à la cible (ex. `apt` sur Debian,
> `dnf` sur RHEL) grâce à `ansible_distribution`.*

> **`register`** capture le résultat d'une tâche dans une variable (on l'a déjà utilisé pour le
> bootstrap Python : `register: pycheck` → `when: pycheck.rc != 0`).

---

## 3. Conditions et boucles

Exemple d'utilisation des conditions (selon les **facts**) et des boucles :

```yaml
# condition : apt → n'installer que sur Debian/Ubuntu
- name: Installer Apache (familles Debian)
  ansible.builtin.apt:
    name: apache2
    state: present
  when: ansible_os_family == "Debian"

# condition : dnf → sur Fedora / RHEL (successeur de CentOS). Le paquet s'appelle "httpd".
- name: Installer Apache (familles RedHat)
  ansible.builtin.dnf:
    name: httpd
    state: present
  when: ansible_os_family == "RedHat"

# boucle : installer plusieurs paquets (apt → implique aussi Debian)
- name: Installer les paquets web
  ansible.builtin.apt:
    name: "{{ item }}"
    state: present
  when: ansible_os_family == "Debian"
  loop:
    - apache2
    - libapache2-mod-php
    - php
    # ...
```

> **Le module générique `package`.** Plutôt que de gérer `apt` / `dnf` / `yum`… à la main avec
> des `when`, Ansible fournit **[`ansible.builtin.package`](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/package_module.html)**,
> qui **choisit tout seul** le gestionnaire de paquets de la cible :
> ```yaml
> - name: Installer Apache (multi-distro)
>   ansible.builtin.package:
>     name: "{{ apache_pkg }}"     # le NOM du paquet diffère encore (apache2 vs httpd) → variable
>     state: present
> ```
> Il abstrait le **gestionnaire**, mais **pas le nom du paquet** (`apache2` ≠ `httpd`) — on garde
> donc souvent une variable par famille d'OS. Pattern courant : un fichier de variables **par
> famille**, chargé selon `ansible_os_family` :
>
> ```
> vars/
> ├── Debian.yml      # apache_pkg: apache2
> └── RedHat.yml      # apache_pkg: httpd
> ```
> ```yaml
> # dans le play : charger le bon fichier selon l'OS détecté
> - name: Charger les variables propres à l'OS
>   ansible.builtin.include_vars: "vars/{{ ansible_os_family }}.yml"
>
> - name: Installer Apache (multi-distro)
>   ansible.builtin.package:
>     name: "{{ apache_pkg }}"
>     state: present
> ```

---

## 4. Templates Jinja2 — générer un fichier de config

Le module **`template`** prend un fichier `.j2` (avec des `{{ variables }}`/conditions/boucles)
et le **rend** sur la cible. C'est LE moyen de produire des fichiers de configuration
dynamiques — au cœur du J3 (et de l'HAProxy en [6](6-HAPROXY.md)).

`templates/site.conf.j2` (un vhost Apache, paramétré) :

```jinja
# Généré par Ansible — ne pas éditer à la main
<VirtualHost *:{{ http_port }}>
    ServerAdmin {{ admin_email }}
    DocumentRoot /var/www/html
    ServerName {{ site_title | lower | replace(' ', '-') }}
</VirtualHost>
```

La tâche qui le déploie :

```yaml
- name: Déployer le vhost Apache
  ansible.builtin.template:
    src: templates/site.conf.j2
    dest: /etc/apache2/sites-available/000-default.conf
    mode: "0644"
  notify: Recharger Apache        # ← déclenche un handler (section suivante)
```

> **`template` vs `copy`** : `copy` dépose un fichier **tel quel** ; `template` le **rend**
> d'abord (substitue les variables). On utilise `template` dès qu'il y a du dynamique.

---

## 5. Handlers — réagir au changement

Un **handler** est une tâche qui ne s'exécute **que si** elle est **notifiée** par un `notify`,
et **une seule fois** en fin de play. Usage typique : **recharger un service** quand (et
seulement quand) sa config a changé.

```yaml
  handlers:
    - name: Recharger Apache
      ansible.builtin.service:
        name: apache2
        state: reloaded
```

> **Pourquoi c'est important ?** Sans handler, on rechargerait Apache à **chaque** exécution
> (inutile, voire perturbant). Avec `notify` → handler : Apache n'est rechargé **que** si le
> template du vhost a réellement changé. C'est l'idempotence appliquée aux services.

---

## Le playbook assemblé

```yaml
# site.yml
- name: Serveur web paramétré
  hosts: web
  gather_facts: true
  become: true

  tasks:
    - name: Bootstrap Python si besoin
      ansible.builtin.raw: command -v python3 || (apt-get update -y && apt-get install -y python3)
      changed_when: false

    - name: Installer les paquets web
      ansible.builtin.apt:
        name: "{{ item }}"
        state: present
        update_cache: true
      loop: [apache2, php, libapache2-mod-php]

    - name: Déployer le vhost (template)
      ansible.builtin.template:
        src: templates/site.conf.j2
        dest: /etc/apache2/sites-available/000-default.conf
        mode: "0644"
      notify: Recharger Apache

    - name: Démarrer et activer Apache
      ansible.builtin.service:
        name: apache2
        state: started
        enabled: true

  handlers:
    - name: Recharger Apache
      ansible.builtin.service:
        name: apache2
        state: reloaded
```

> **🧪 Manip — le handler ne se déclenche que sur changement**
>
> 1. `ansible-playbook -i inventory.ini site.yml` → 1er run : le template est créé → le handler
>    **`Recharger Apache` s'exécute** (`changed`).
> 2. Rejouer **sans rien changer** → le template est identique → **le handler ne tourne pas**
>    (récap : `changed=0`).
> 3. Changez `http_port` dans `group_vars/web.yml` (ex. `8080`) → rejouer → le template change →
>    **le handler se redéclenche**.
>
> *Observation : Apache n'est rechargé **que** quand sa config bouge. C'est exactement le
> comportement attendu en production.*

Nettoyage : `docker rm -f web1`.

---

## Recap

- **Variables** : `group_vars`/`host_vars`/`vars`/`-e` → séparer la config des tâches.
- **Facts** (`gather_facts`, module `setup`) : Ansible découvre l'OS/IP/… → tâches adaptatives.
- **`when`** (conditions) et **`loop`** (boucles).
- **`template`** (Jinja2) : générer des **fichiers de config dynamiques** (≠ `copy`).
- **Handlers** (`notify`) : relancer un service **seulement quand sa config change**.

➡️ **[3 — Les secrets : Ansible Vault](3-VAULT.md)**
