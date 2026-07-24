# Projet OPS : déploie LEUR reverse proxy (conteneur HAProxy).
# Rejoint le réseau "wpnet" (créé côté dev) pour joindre les backends par leur nom.
resource "docker_image" "debian" { name = "debian:12" }

resource "docker_container" "proxy" {
  name    = "proxy"
  image   = docker_image.debian.image_id
  command = ["sleep", "infinity"]
  ports {
    internal = 80
    external = 8088
  }
  networks_advanced { name = "wpnet" } # réseau existant (dev)
}
