# Copyright 2024 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

locals {
  additional_labels = tomap({
    for item in split(",", var.additional_labels) :
    split("=", item)[0] => split("=", item)[1]
  })
}

resource "kubernetes_service" "inference_service" {
  metadata {
    name = "gemma-2b-it-service"
    labels = {
      app = "gemma-2b-it"
    }
    namespace = var.namespace
    annotations = {
      "cloud.google.com/load-balancer-type" = "Internal"
      "cloud.google.com/neg"                = "{\"ingress\":true}"
    }
  }
  spec {
    selector = {
      app = "gemma-2b-it"
    }
    session_affinity = "ClientIP"
    port {
      protocol    = "TCP"
      port        = 80
      target_port = 8080
    }

    type = "LoadBalancer"
  }
}

resource "kubernetes_deployment" "inference_deployment" {
  timeouts {
    create = "30m"
  }
  metadata {
    name      = "gemma-2b-it"
    namespace = var.namespace
    labels = merge({
      app = "gema-2b-it"

    }, local.additional_labels)
  }

  spec {
    # It takes more than 10m for the deployment to be ready on Autopilot cluster
    # Set the progress deadline to 60m to avoid the deployment controller
    # considering the deployment to be failed
    progress_deadline_seconds = 3600
    replicas                  = 1

    selector {
      match_labels = merge({
        app = "gemma-2b-it"
      }, local.additional_labels)
    }

    template {
      metadata {
        labels = merge({
          app = "gemma-2b-it"
        }, local.additional_labels)
      }

      spec {

        #init_container {
        #  name  = "download-extract-models"
        #  image = "google/cloud-sdk:473.0.0-alpine"
        #  command = ["/bin/sh", "-c"]
        #  args = [
        #    "gsutil cp -r gs://vertex-model-garden-public-us/gemma.tar.gz /model-data/ && tar -xzvf /model-data/gemma.tar.gz -C /model-data/"
        #  ]
        #  volume_mount {
        #    mount_path = "/model-data"
        #    name       = "model-storage"
        #  }
        #}

        

        

        container {
          image = "us-docker.pkg.dev/vertex-ai/vertex-vision-model-garden-dockers/pytorch-hf-tgi-serve:20240220_0936_RC01"
          name  = "gemma-2b-it"

          port {
            name           = "metrics"
            container_port = 8080
            protocol       = "TCP"
          }

          args = ["--model-id", "$(MODEL_ID)"]

          #env {
          #  name  = "MODEL_ID"
          #  value = "/model/gemma/gemma-2b-it"
          #}

          env {
            name  = "MODEL_ID"
            value = "google/gemma-1.1-2b-it"
          }

          #env {
          #  name  = "NUM_SHARD"
          #  value = "1"
          #}

          env {
            name  = "SHARDED"
            value = "false"
          }

          env {
            name  = "HUGGING_FACE_HUB_TOKEN"
            value = var.hf_token
          }

          env {
            name  = "PORT"
            value = "8080"
          }

          resources {
            limits = {
              "nvidia.com/gpu" = "1"
            }
            requests = {
                
              "ephemeral-storage" = "50Gi"
              "nvidia.com/gpu"    = "1"
            }
          }

          volume_mount {
            mount_path = "/dev/shm"
            name       = "dshm"
          }

          volume_mount {
            mount_path = "/data"
            name       = "data"
          }

          volume_mount {
            mount_path = "/model"
            name       = "model-storage"
            read_only  = "true"
          }

          #liveness_probe {
          #http_get {
          #path = "/"
          #port = 8080

          #http_header {
          #name  = "X-Custom-Header"
          #value = "Awesome"
          #}
          #}

          #initial_delay_seconds = 3
          #period_seconds        = 3
          #}
        }

        volume {
          name = "dshm"
          empty_dir {
            medium = "Memory"
          }
        }

        volume {
          name = "data"
          empty_dir {}
        }

        volume {
          name = "model-storage"
          empty_dir {}
        }

        node_selector = merge({
          "cloud.google.com/gke-accelerator" = "nvidia-l4"
          }, var.autopilot_cluster ? {
          "cloud.google.com/gke-ephemeral-storage-local-ssd" = "true"
          "cloud.google.com/compute-class"                   = "Accelerator"
        } : {})
      }
    }
  }
}
