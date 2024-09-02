data "oci_identity_availability_domains" "adz" {
  compartment_id = var.compartment_ocid
}

resource "oci_core_instance" "bastion" {
  #availability_domain = data.oci_identity_availability_domains.adz.availability_domains[var.availability_domain].name
  availability_domain = data.template_file.ad_names.*.rendered[0]
  compartment_id      = var.compartment_ocid
  shape               = var.instance_shape
  display_name        = var.instance_name

  dynamic "shape_config" {
    for_each = var.is_flex_bastion_shape ? [1] : []
    content {
      ocpus         = var.bastion_shape_config_ocpus
      memory_in_gbs = var.bastion_shape_config_memory_in_gbs
    }
  }
  source_details {
    source_id   = var.image_id
    source_type = "image"
  }

  create_vnic_details {
    subnet_id        = var.subnet_id
    assign_public_ip = var.public_edge_node
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = var.user_data
  }

  extended_metadata = {
    oke_cluster_id      = var.oke_cluster_id
    nodepool_id         = var.nodepool_id
    availability_domain = data.template_file.ad_names.*.rendered[0]
    obj_storage_namespace   = var.obj_storage_namespace
    bucket_name = var.bucket_name
    customer_access_key = var.customer_access_key
    customer_secret_key = var.customer_secret_key
    mlflow_image = var.mlflow_image
    load_balancer_ip = var.reserved_public_ip
    configure_oracle_auth = var.configure_oracle_auth
    oci_domain = var.oci_domain
    client_id = var.oci_client_id
    client_secret = var.oci_client_secret
  }
}
