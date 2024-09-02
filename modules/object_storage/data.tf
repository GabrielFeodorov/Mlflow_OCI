resource "random_string" "deploy_id" {
  length  = 4
  special = false
}



data "oci_objectstorage_namespace" "existing" {
    compartment_id = var.compartment_ocid
}