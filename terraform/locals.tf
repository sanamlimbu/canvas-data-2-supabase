locals {
  service_name = "canvas-data-2"
  package_path = "${path.module}/tf_generated/packages"
  archive_path = "${path.module}/tf_generated/${local.service_name}.zip"
}