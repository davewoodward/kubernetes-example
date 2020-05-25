provider "google" {
  version     = "~> 3.22"
  credentials = file("account.json")
  project     = "kubernetes-example-278112"
}

resource "google_container_cluster" "primary" {
  name     = "my-gke-cluster"
  location = "us-central1"

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1

  master_auth {
    client_certificate_config {
      issue_client_certificate = true
    }
  }

  # provisioner "local-exec" {
  #   command = "gcloud container clusters get-credentials ${google_container_cluster.gke-cluster.name} --zone  ${google_container_cluster.gke-cluster.zone} --project [PROJECT_ID]"
  # }
}

resource "google_container_node_pool" "primary_preemptible_nodes" {
  name       = "my-node-pool"
  location   = "us-central1"
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
}

resource "kubernetes_namespace" "example" {
  metadata {
    name = "my-first-namespace"
  }
}

resource "kubernetes_pod" "test" {
  metadata {
    name = "terraform-example"
    namespace = "my-first-namespace"
  }

  spec {
    container {
      image = "nginx:1.7.9"
      name  = "example"

      env {
        name  = "environment"
        value = "test"
      }

      liveness_probe {
        http_get {
          path = "/nginx_status"
          port = 80

          http_header {
            name  = "X-Custom-Header"
            value = "Awesome"
          }
        }

        initial_delay_seconds = 3
        period_seconds        = 3
      }
    }

    dns_config {
      nameservers = ["1.1.1.1", "8.8.8.8", "9.9.9.9"]
      searches    = ["example.com"]

      option {
        name  = "ndots"
        value = 1
      }

      option {
        name = "use-vc"
      }
    }

    dns_policy = "None"
  }
}

output ca_certificate {
  value       = google_container_cluster.primary.master_auth.0.cluster_ca_certificate
  sensitive   = false
  description = "Base64 encoded public certificate that is the root of trust for the cluster."
}

output client_certificate {
  value       = google_container_cluster.primary.master_auth.0.client_certificate
  sensitive   = false
  description = "Base64 encoded public certificate used by clients to authenticate to the cluster endpoint."
}

output client_key {
  value       = google_container_cluster.primary.master_auth.0.client_key
  sensitive   = true
  description = "Base64 encoded private key used by clients to authenticate to the cluster endpoint."
}

output endpoint {
  value       = google_container_cluster.primary.endpoint
  sensitive   = false
  description = "The IP address of this cluster's Kubernetes master."
}
