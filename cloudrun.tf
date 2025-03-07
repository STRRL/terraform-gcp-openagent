resource "random_bytes" "chainlit_auth_secret" {
  length = 32

}

locals {
  env = {
    ENV             = "prod"
    MODEL_NAME      = "gemini-1.5-pro"
    PROJECT_ID      = var.project
    RSS3_DATA_API   = "https://testnet.rss3.io/data"
    RSS3_SEARCH_API = "https://devnet.rss3.io/search"
    NFTSCAN_API_KEY = var.nftscan_api_key
    SERPAPI_API_KEY = var.serp_api_key

    # DB with unix socket
    DB_CONNECTION = "postgresql+psycopg://${google_sql_user.openagent.name}:${random_password.openagent.result}@/${google_sql_database.openagent.name}?host=/cloudsql/${google_sql_database_instance.openagent.connection_name}"
    LLM_API_BASE  = "https://api.openai.com/v1"

    CHAINLIT_AUTH_SECRET = random_bytes.chainlit_auth_secret.result

  }
}

resource "google_cloud_run_v2_service" "openagent" {
  depends_on = [google_sql_database.openagent, postgresql_extension.vector]

  name     = "openagent"
  project  = var.project
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [google_sql_database_instance.openagent.connection_name]
      }
    }

    containers {
      name  = "openagent"
      image = "${var.image_repo}:${var.image_tag}"

      ports {
        container_port = 8000
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "1Gi"
        }
      }

      command = ["python", "main.py"]

      liveness_probe {
        http_get {
          path = "/health"
        }
        initial_delay_seconds = 30
        period_seconds        = 15
        timeout_seconds       = 1
        failure_threshold     = 3
      }

      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }

      dynamic "env" {
        for_each = local.env
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = var.oauth
        content {
          name  = env.key
          value = env.value

        }
      }
    }
  }
}

resource "google_cloud_run_v2_service_iam_member" "openagent" {
  project  = var.project
  location = google_cloud_run_v2_service.openagent.location
  name     = google_cloud_run_v2_service.openagent.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
