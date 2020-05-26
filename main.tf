variable "password" {}

locals {
  username = "admin"
}

provider "google" {
  version     = "~> 3.22"

  credentials = file("account.json")
  project     = "kubernetes-example-278112"
  region      = "us-central1"
  zone        = "us-central1-a"
}

provider "null" {
  version     = "~> 2.1"
}

resource "google_container_cluster" "primary" {
  name     = "my-gke-cluster"


  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1

  master_auth {
    client_certificate_config {
      issue_client_certificate = true
    }
    password = var.password
    username = local.username
  }
}

# resource "null_resource" "get_credentials" {
#   provisioner "local-exec" {
#     command = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --project \"kubernetes-example-278112\""
#   }
# }

resource "google_container_node_pool" "primary_preemptible_nodes" {
  name       = "my-node-pool"
  cluster    = google_container_cluster.primary.name
  node_count = 1

  node_config {
    preemptible  = true
    machine_type = "n1-standard-1"

    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]
  }
}

provider "kubernetes" {
  version                = "~> 1.11"

  client_certificate     = base64decode(google_container_cluster.primary.master_auth.0.client_certificate)
  client_key             = base64decode(google_container_cluster.primary.master_auth.0.client_key)
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth.0.cluster_ca_certificate)
  host                   = "https://${google_container_cluster.primary.endpoint}"
  load_config_file       = "false"
  password               = var.password
  username               = local.username
}

resource "kubernetes_namespace" "example" {
  metadata {
    name = "my-first-namespace"
  }

  depends_on = [
    google_container_cluster.primary,
    google_container_node_pool.primary_preemptible_nodes
  ]
}

resource "kubernetes_pod" "test" {
  metadata {
    name = "terraform-example"
    namespace = "my-first-namespace"
    labels = {
      app = "TheApp"
    }
  }

  spec {
    container {
      image = "nginx:latest"
      name  = "example"
      port {
        container_port = 80
      }

    #   env {
    #     name  = "environment"
    #     value = "test"
    #   }

      liveness_probe {
        http_get {
          path = "/"
          port = 80

          # http_header {
          #   name  = "X-Custom-Header"
          #   value = "Awesome"
          # }
        }

        initial_delay_seconds = 3
        period_seconds        = 3
      }
    }

    # dns_config {
    #   nameservers = ["1.1.1.1", "8.8.8.8", "9.9.9.9"]
    #   searches    = ["example.com"]

    #   option {
    #     name  = "ndots"
    #     value = 1
    #   }

    #   option {
    #     name = "use-vc"
    #   }
    # }

    # dns_policy = "None"
  }


  depends_on = [
    google_container_cluster.primary,
    google_container_node_pool.primary_preemptible_nodes
  ]
}

resource "kubernetes_service" "example" {
  metadata {
    name = "terraform-example"
    namespace = "my-first-namespace"
  }

  spec {
    selector = {
      app = "TheApp"
    }
    session_affinity = "ClientIP"
    port {
      port        = 80
      target_port = 80
    }
    type = "LoadBalancer"
  }
}

resource "kubernetes_ingress" "example" {
  metadata {
    name = "example-ingress"
    namespace = "my-first-namespace"
  }

  spec {
    backend {
      service_name = "terraform-example"
      service_port = 80
    }

    rule {
      http {
        path {
          backend {
            service_name = "terraform-example"
            service_port = 80
          }

          path = "/*"
        }
      }
    }

    tls {
      secret_name = "tls-secret"
    }
  }
}

output "endpoint" {
  value = kubernetes_ingress.example.load_balancer_ingress
}
