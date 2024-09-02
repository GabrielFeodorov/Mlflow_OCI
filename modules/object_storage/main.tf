resource "oci_objectstorage_bucket" "these" {
    count          = var.useExistingBucket ? 0 : 1
    compartment_id = var.compartment_ocid
    name = "mlflow_bucket_${random_string.deploy_id.result}"
    namespace = data.oci_objectstorage_namespace.existing.namespace
    access_type = "NoPublicAccess"
    object_events_enabled = true
    storage_tier = "Standard"
}