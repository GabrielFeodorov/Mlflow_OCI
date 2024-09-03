output bucket_name {
    value = var.useExistingBucket ? null : oci_objectstorage_bucket.these.0.name
}


output obj_storage_namespace {
    value = data.oci_objectstorage_namespace.existing.namespace
}