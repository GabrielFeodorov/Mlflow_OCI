output "BASTION_PUBLIC_IP" { value = var.public_edge_node ? module.bastion.public_ip : "No public IP assigned" }

output "INFO" { value = "CloudInit on Bastion host drives mlflow deployment.  Login to Bastion host and check /var/log/OKE-mlflow-initialize.log for status and Load Balancer Address" }
