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
  name  = "wp"
  image = docker_image.wp.image_id
  ports {
    internal = 80
    external = 8080
  }
  networks_advanced { name = docker_network.wp.name }
  depends_on = [docker_container.db]
}

# Terraform genere l'inventaire pour Ansible
resource "local_file" "inventory" {
  filename = "${path.module}/inventory.ini"
  content  = <<-EOT
    [wordpress]
    ${docker_container.wordpress.name} ansible_connection=community.docker.docker
    [db]
    ${docker_container.db.name} ansible_connection=community.docker.docker
  EOT
}
