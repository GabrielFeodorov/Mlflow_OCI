# Mlflow on OCI OKE
This quickstart template deploys [Mlflow](https://mlflow.org/) on [Oracle Kubernetes Engine (OKE)](https://docs.oracle.com/en-us/iaas/Content/ContEng/Concepts/contengoverview.htm).

# Pre-Requisites
Please read the following prerequisites sections thoroughly prior to deployment.

## Instance Principals & IAM Policy
Deployment depends on use of [Instance Principals](https://docs.oracle.com/en-us/iaas/Content/Identity/Tasks/callingservicesfrominstances.htm) via OCI CLI to generate kube config for use with kubectl.  You should create a [dynamic group](https://docs.oracle.com/en-us/iaas/Content/Identity/Tasks/managingdynamicgroups.htm) for the compartment where you are deploying Mlflow.

	instance.compartment.id='ocid.comp....'

After creating the group, you should set specific [IAM policies](https://docs.oracle.com/en-us/iaas/Content/Identity/Reference/policyreference.htm) for OCI service interaction:

	Allow dynamic-group Mlflow to manage cluster-family in compartment Mlflow
	Allow dynamic-group Mlflow to manage object-family in compartment Mlflow
	Allow dynamic-group Mlflow to manage virtual-network-family in compartment Mlflow



## Mlflow image
Deployment depends on a Mlflow image that will be used to create the Mlflow app.
You can use whatever tool you're confortable with to build and push the image.
The content of the image is found in the **mlflow_image** folder.
We're going to use [OCI Container Registry](https://docs.oracle.com/en-us/iaas/Content/Registry/Concepts/registryoverview.htm) to store it.
### Steps to create the Mlflow image:
1. [Create repository in OCI Container Registry](https://docs.oracle.com/en-us/iaas/Content/Registry/Tasks/registrycreatingarepository.htm#top).
	- You have to make sure your OKE can access the repository in case it's private.
	- Set the name of the repository followed by the /mlflow. Example: ```<repository_name>/mlflow```
2. Building the image.
	- Go to **mlflow_image** folder.
	- Run the command ```docker build --platform linux/amd64 -t mlflow:latest .```
3. [Pushing the image to OCI Container Registry](https://docs.oracle.com/en-us/iaas/Content/Registry/Tasks/registrypushingimagesusingthedockercli.htm#Pushing_Images_Using_the_Docker_CLI).
	- ```docker login ocir.<region>.oci.oraclecloud.com```
	- ```docker tag mlflow:latest ocir.<region>.oci.oraclecloud.com/<tenancy-namespace/<repository_name>/mlflow:latest```
	- ```podman push ocir.<region>.oci.oraclecloud.com/<tenancy-namespace>/<repository_name>/mlflow:latest```


## Storing Mlflow artifacts to OCI Bucket
Deployment depends on an [OCI Object Storage](https://docs.oracle.com/en-us/iaas/Content/Object/Concepts/objectstorageoverview.htm) Bucket to store the artifacts.
You can use an existing Bucket or let the automation create one for you.
To access the bucket, Mlflow uses [Customer Secret Key](https://docs.oracle.com/en-us/iaas/Content/Rover/IAM/User_Credentials/Secret_Keys/customer-secret-key_management.htm).

Steps:
1. [Create a Secret Key](https://docs.oracle.com/en-us/iaas/Content/Rover/IAM/User_Credentials/Secret_Keys/create_customer-secret-key.htm#CreateCustomerSecretKey).
2. Note down the secret key, you will use it in the **customer_secret_key** variable when deploying the Stack.
3. Note down the access key, you will use it in the **customer_access_key** variable when deploying the Stack.



## Mlflow access and Oracle IDCS Authentication
### Reserved public ip
Deployment depends on a public ip for the Load Balancer. This is used to create the certificates and the authentication in the Oracle IDCS APP if you decide to use it. Go to [Create a Reserved Public IP](https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/reserved-public-ip-create.htm).


### Authentication using Oracle IDCS
1. Create an Oracle IDCS Integration Application

- Nativagate to [Oracle Identity Domains](https://cloud.oracle.com/identity/domains) in the OCI Console and click on your current domain.
- Select **Integrated Applications** from the left-side menu and click **Add application**.
- Select **Confidential Application** and click **Launch workflow**.
- Add a name and description and click on **Next**.
- **Configure OAuth**
	- **Resource server configuration** select **Skip for later**.
	- **Client configuration** select **CConfigure this application as a client now**.
	- Check the boxes for **Client credentials** and **Authorization code**.
	- **Redirect URL** - add **https://mlflow.<reserved_public_ip>.nip.io/oauth2/callback**
	- Scroll down to **Client ip address** and select **Anywhere**
	- **Token issuance policy**, **Authorized resources** select **All**.
	- Click on **Next**.
- **Web tier policy** select **Skip and do later** and click on **Finish**.
- Click on **Activate** to activate your application.
- On the left side of your Application select **Users** or **Groups** to authorize users or groups to authenticate using this Application.



2. Collecting your Application information for the Deployment.
You will need the Application **Client ID** and **Client secret** and your **OCI Domain URL**
- Client ID and Client secret
  - On your Application page, select **OAuth configuration** from the left side.
  - Under **General Information**
  	- Note down **Client ID**
  	- Under **Client secret** click on **Show secret** and note it down.
- OCI Domain URL
  - Go to [Oracle Identity Domains](https://cloud.oracle.com/identity/domains) click on your current domain.
  - Under **Domain Information** you will find **Domain URL**. Note it down.



3. Enabling Oracle Authentication when deploying the ORM Stack for Mlflow.
- In the **Configure variables** page of the stack
- Under **Mlflow Configuration**
- Check the box for **Configure authentication with Oracle IDCS**
  - for **OCI Identity Domain URL** add your **OCI Domain URL**. The format is **https://idcs-xxxxxxxxxxxxxxxxxxxxxx.identity.oraclecloud.com**.
  - for **OCI Integrated Application Client ID** add your **Client ID**.
  - for **OCI Integrated Application Client Secret** add your **Client secret**.


# Deployment
This deployment uses [Oracle Resource Manager](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Concepts/resourcemanager.htm) and consists of a VCN,an Object Storage Bucket,an OKE Cluster with Node Pool, and an Edge node.   The Edge node installs OCI CLI, Kubectl, Mlflow and configures everything. This is done using [cloudinit](userdata/cloudinit.sh) - the build process is logged in ``/var/log/OKE-mlflow-initialize.log``.

*Note that you should select shapes and scale your node pool as appropriate for your workload.*

This template deploys the following by default:

* Virtual Cloud Network
  * Public (Edge) Subnet
  * Private Subnet
  * Internet Gateway
  * NAT Gateway
  * Service Gateway
  * Route tables
  * Security Lists
    * TCP 22 for Edge SSH on public subnet
    * Ingress to both subnets from VCN CIDR
    * Egress to Internet for both subnets
* OCI Bucket
* OCI Virtual Machine Edge Node
* OKE Cluster and Node Pool
* Load Balancer

Simply click the Deploy to OCI button to create an ORM stack, then walk through the menu driven deployment.  Once the stack is created, use the menu to Plan and Apply the template.

[![Deploy to Oracle Cloud](https://oci-resourcemanager-plugin.plugins.oci.oraclecloud.com/latest/deploy-to-oracle-cloud.svg)](https://console.us-ashburn-1.oraclecloud.com/resourcemanager/stacks/create?region=home&zipUrl=https://github.com/GabrielFeodorov/Mlflow_OCI/archive/refs/heads/main.zip)

## OKE post-deployment
Please wait for 10-12 minutes until the cloud init script installs and configures everything.


You can check status of the OKE cluster using the following kubectl commands:

	kubectl get all -A

### Mlflow Access


	ssh -i ~/.ssh/PRIVATE_KEY opc@EDGE_NODE_IP
	cat /var/log/OKE-mlflow-initialize.log|egrep -i "Point your browser to"

	Note: The certificate created for this deployment is a self signed certificate and hence the browser will issue warning. It needs to be accepted. 

Login using Oracle IDCS. If you're not using Oracle IDCS for auth, you will not have an authentication form.

### Destroying the Stack
Note that with the inclusion of SSL Load Balancer, you will need to remove the `` ingress-nginx-controller `` service before you destroy the stack, or you will get an error. 

	kubectl delete svc ingress-nginx-controller -n ingress-nginx

This will remove the service, then you can destroy the build without errors.
