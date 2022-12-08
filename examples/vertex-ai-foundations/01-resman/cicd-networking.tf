/**
 * Copyright 2022 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

# tfdoc:file:description CI/CD resources for the networking branch.

# source repository

module "branch-network-cicd-repo" {
  source = "../modules/source-repository"
  for_each = (
    try(local.cicd_repositories.networking.type, null) == "sourcerepo"
    ? { 0 = local.cicd_repositories.networking }
    : {}
  )
  project_id = var.automation.project_id
  name       = each.value.name
  iam = {
    "roles/source.admin"  = [module.branch-network-sa.iam_email]
    "roles/source.reader" = [module.branch-network-sa-cicd.0.iam_email]
  }
  triggers = {
    fast-02-networking = {
      filename        = ".cloudbuild/workflow.yaml"
      included_files  = ["**/*tf", ".cloudbuild/workflow.yaml"]
      service_account = module.branch-network-sa-cicd.0.id
      substitutions   = {}
      template = {
        project_id  = null
        branch_name = each.value.branch
        repo_name   = each.value.name
        tag_name    = null
      }
    }
  }
  depends_on = [module.branch-network-sa-cicd]
}

# SA used by CI/CD workflows to impersonate automation SAs

module "branch-network-sa-cicd" {
  source = "../modules/iam-service-account"
  for_each = (
    try(local.cicd_repositories.networking.name, null) != null
    ? { 0 = local.cicd_repositories.networking }
    : {}
  )
  project_id   = var.automation.project_id
  name         = "prod-resman-net-1"
  display_name = "Terraform CI/CD stage 2 networking service account."
  prefix       = var.prefix
  iam = (
    each.value.type == "sourcerepo"
    # used directly from the cloud build trigger for source repos
    ? {
      "roles/iam.serviceAccountUser" = local.automation_resman_sa
    }
    # impersonated via workload identity federation for external repos
    : {
      "roles/iam.workloadIdentityUser" = [
        each.value.branch == null
        ? format(
          local.identity_providers[each.value.identity_provider].principalset_tpl,
          var.automation.federated_identity_pool,
          each.value.name
        )
        : format(
          local.identity_providers[each.value.identity_provider].principal_tpl,
          var.automation.federated_identity_pool,
          each.value.name,
          each.value.branch
        )
      ]
    }
  )
  iam_project_roles = {
    (var.automation.project_id) = ["roles/logging.logWriter"]
  }
  iam_storage_roles = {
    (var.automation.outputs_bucket) = ["roles/storage.objectViewer"]
  }
}
