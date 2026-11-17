terraform {
  required_version = ">= 1.4.0"
}

resource "terraform_data" "compose" {
  triggers_replace = filesha256("${path.module}/../docker/docker-compose.yml")

  provisioner "local-exec" {
    interpreter = ["powershell.exe", "-NoProfile", "-NonInteractive", "-Command"]
    environment = {
      COMPOSE_PROJECT_DIR = abspath("${path.module}/../docker")
      COMPOSE_ENV_FILE    = abspath("${path.module}/../docker/.env")
      COMPOSE_FILE_PATH   = abspath("${path.module}/../docker/docker-compose.yml")
    }
    command = <<-EOT
      docker compose --project-directory $env:COMPOSE_PROJECT_DIR --env-file $env:COMPOSE_ENV_FILE -f $env:COMPOSE_FILE_PATH up -d --build
      if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    EOT
  }
}
