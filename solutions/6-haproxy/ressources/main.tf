# "Ce que DEV livre" : la stack applicative (réseau + db + wp) + l'inventaire des BACKENDS.
# (Le reverse proxy n'est PAS ici : c'est l'OPS qui possède et déploie son propre edge.)

resource "docker_image" "mysql" { name = "mysql:8.0" }
resource "docker_image" "wp" { name = "wordpress:latest" }

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

resource "docker_container" "wordpress" {
  name       = "wp"
  image      = docker_image.wp.image_id
  env        = ["WORDPRESS_DB_HOST=db"]
  depends_on = [docker_container.db]
  networks_advanced { name = docker_network.wp.name }
}

# Inventaire des BACKENDS publié pour l'ops (handoff dev → ops).
resource "local_file" "inventory_backends" {
  filename = "${path.module}/inventory-backends.ini"
  content  = <<-EOT
    [wordpress]
    wp ansible_connection=community.docker.docker

    [db]
    db ansible_connection=community.docker.docker
  EOT
}
