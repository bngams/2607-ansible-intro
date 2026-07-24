# Provisionner la CIBLE applicative + sa base, et publier l'inventaire.
# Les noms (app1, db, wpnet) sont ceux que consommera le chapitre 6.
resource "docker_image" "mysql" { name = "mysql:8.0" }
resource "docker_image" "debian" { name = "debian:12" }

resource "docker_network" "wp" { name = "wpnet" }

resource "docker_container" "db" {
  name  = "db"
  image = docker_image.mysql.image_id
  env = [
    "MYSQL_ROOT_PASSWORD=rootpw",
    "MYSQL_DATABASE=wordpress",
  ]
  networks_advanced { name = docker_network.wp.name }
}

# La cible applicative : un conteneur NU, qu'Ansible configurera ensuite.
# (Au chapitre 6, c'est le role publie par les ops qui y installera WordPress.)
resource "docker_container" "app1" {
  name    = "app1"
  image   = docker_image.debian.image_id
  command = ["sleep", "infinity"]
  networks_advanced { name = docker_network.wp.name }
  depends_on = [docker_container.db]
}

# Terraform GENERE l'inventaire pour Ansible.
# Le groupe [apps] est la convention reprise par l'annuaire du chapitre 6.
resource "local_file" "inventory" {
  filename = "${path.module}/inventory.ini"
  content  = <<-EOT
    [apps]
    ${docker_container.app1.name} ansible_connection=community.docker.docker

    [db]
    ${docker_container.db.name} ansible_connection=community.docker.docker
  EOT
}
